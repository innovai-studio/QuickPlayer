package com.quickplayer.quickplayer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Full-song stem separation pipeline: decode -> resample to 44.1 kHz
 * stereo -> run htdemucs ONNX over overlapping segments with a
 * Bartlett-weighted overlap-add -> AAC .m4a per stem.
 *
 * Memory model matters: a full song's 4 stems as float arrays is ~500 MB
 * and blows the Dalvik heap (256 MB), so we (a) keep the decoded input as
 * s16 (~64 MB for 6 min), and (b) overlap-add in a small sliding window,
 * streaming finalized PCM to four temp files which are then AAC-encoded.
 * Peak heap stays a few MB beyond the input. Port of
 * tools/stem_onnx/fullsong_separate.py (verified-good at 2s/3.9s/7.8s).
 */
class StemPipeline(private val env: OrtEnvironment) {

    companion object {
        const val SR = 44100
        const val CHANNELS = 2
        val SOURCES = listOf("drums", "bass", "other", "vocals")
        private const val OVERLAP = 0.25
    }

    fun separate(
        modelPath: String,
        audioPath: String,
        outDir: String,
        threads: Int = 4,
        provider: String = "cpu",
        onProgress: (Double) -> Unit = {},
    ): List<String> {
        val (left, right) = decodeToStereo44k(audioPath)   // planar s16
        val frames = left.size
        onProgress(0.05)

        val session = createSessionWithFallback(modelPath, threads, provider)
        File(outDir).mkdirs()
        // Temp interleaved-s16 PCM sinks, one per stem (freed after encode).
        val pcmFiles = SOURCES.map { File(outDir, "$it.pcm") }
        val sinks = pcmFiles.map { BufferedOutputStream(FileOutputStream(it), 1 shl 16) }

        try {
            val inputNames = session.inputNames.toList()
            // v2.1 model has 2 inputs (mix + spec, native FFT); v2.0 has 1 (mix only).
            val isV21 = "spec" in inputNames
            val mixName = if ("mix" in inputNames) "mix" else inputNames.first()
            val seg = (session.inputInfo[mixName]!!.info as TensorInfo).shape[2].toInt()
            val stride = (seg * (1 - OVERLAP)).toInt()
            val win = bartlett(seg)

            // v2.1 spec parameters (htdemucs: n_fft=4096, hop=1024).
            val nFft = 4096
            val hop = 1024

            val accum = Array(4) { Array(CHANNELS) { FloatArray(seg) } }
            val wsum = FloatArray(seg)
            val chunk = FloatArray(CHANNELS * seg)
            val mixCh = Array(CHANNELS) { FloatArray(seg) }     // reused per segment in v2.1
            val s16 = ByteArrayOutput(stride * CHANNELS * 4 * 2)

            var pos = 0
            while (pos < frames) {
                val len = min(seg, frames - pos)
                java.util.Arrays.fill(chunk, 0f)
                for (i in 0 until len) {
                    chunk[i] = left[pos + i] / 32768f
                    chunk[seg + i] = right[pos + i] / 32768f
                }
                val mixShape = longArrayOf(1, CHANNELS.toLong(), seg.toLong())

                if (isV21) {
                    // v2.1 path: native STFT -> ONNX(mix, spec) -> native iSTFT + xt sum.
                    for (i in 0 until seg) { mixCh[0][i] = chunk[i]; mixCh[1][i] = chunk[seg + i] }
                    val spec = SpecOps.stft(mixCh, nFft, hop)
                    val specShape = longArrayOf(
                        1, CHANNELS.toLong(), spec.fr.toLong(), spec.t.toLong(), 2,
                    )
                    val mixT = OnnxTensor.createTensor(env, FloatBuffer.wrap(chunk), mixShape)
                    val specT = OnnxTensor.createTensor(env, FloatBuffer.wrap(spec.data), specShape)
                    try {
                        session.run(mapOf(mixName to mixT, "spec" to specT)).use { res ->
                            // res[0]=zout (1,4,2,Fr,T,2) ; res[1]=xt (1,4,2,seg)
                            val z = res[0] as OnnxTensor
                            val xt = res[1] as OnnxTensor
                            val zArr = FloatArray(4 * CHANNELS * spec.fr * spec.t * 2)
                            z.floatBuffer.get(zArr)
                            val xtArr = FloatArray(4 * CHANNELS * seg)
                            xt.floatBuffer.get(xtArr)
                            val freqAudio = SpecOps.istft(
                                zArr, 4, CHANNELS, spec.fr, spec.t, nFft, hop, seg,
                            )
                            for (s in 0 until 4) for (c in 0 until CHANNELS) {
                                val dst = accum[s][c]
                                val fa = freqAudio[s][c]
                                val xtBase = (s * CHANNELS + c) * seg
                                for (i in 0 until len) {
                                    dst[i] += (fa[i] + xtArr[xtBase + i]) * win[i]
                                }
                            }
                        }
                    } finally { mixT.close(); specT.close() }
                } else {
                    // v2.0 path: model outputs stems directly.
                    OnnxTensor.createTensor(env, FloatBuffer.wrap(chunk), mixShape).use { input ->
                        session.run(mapOf(mixName to input)).use { res ->
                            @Suppress("UNCHECKED_CAST")
                            val batch = (res[0].value as Array<*>)[0] as Array<*>
                            for (s in 0 until 4) {
                                val srcs = batch[s] as Array<*>
                                for (c in 0 until CHANNELS) {
                                    val chArr = srcs[c] as FloatArray
                                    val dst = accum[s][c]
                                    for (i in 0 until len) dst[i] += chArr[i] * win[i]
                                }
                            }
                        }
                    }
                }
                for (i in 0 until len) wsum[i] += win[i]

                val isLast = pos + len >= frames
                val flushCount = if (isLast) len else stride
                flushWindow(accum, wsum, flushCount, sinks, s16)
                if (!isLast) shiftWindow(accum, wsum, seg, stride)

                pos += stride
                onProgress(0.05 + 0.80 * min(1.0, pos.toDouble() / frames))
            }
            sinks.forEach { it.flush() }
        } finally {
            sinks.forEach { try { it.close() } catch (_: Throwable) {} }
            session.close()
        }

        // Encode each temp PCM -> AAC, then delete the PCM.
        val out = ArrayList<String>(4)
        for (s in 0 until 4) {
            val m4a = File(outDir, "${SOURCES[s]}.m4a")
            AacEncoder.encodePcmFile(pcmFiles[s], m4a, SR)
            pcmFiles[s].delete()
            out.add(m4a.absolutePath)
            onProgress(0.85 + 0.15 * (s + 1) / 4.0)
        }
        onProgress(1.0)
        return out
    }

    /** Write the first [count] finalized frames (normalized by wsum) of
     *  the window to the 4 PCM sinks as interleaved s16. */
    private fun flushWindow(
        accum: Array<Array<FloatArray>>, wsum: FloatArray, count: Int,
        sinks: List<BufferedOutputStream>, buf: ByteArrayOutput,
    ) {
        for (s in 0 until 4) {
            buf.reset()
            val l = accum[s][0]; val r = accum[s][1]
            for (i in 0 until count) {
                val w = max(wsum[i], 1e-6f)
                buf.putShortLE(toS16(l[i] / w))
                buf.putShortLE(toS16(r[i] / w))
            }
            sinks[s].write(buf.array(), 0, buf.size())
        }
    }

    private fun shiftWindow(
        accum: Array<Array<FloatArray>>, wsum: FloatArray, seg: Int, stride: Int,
    ) {
        val keep = seg - stride
        for (s in 0 until 4) for (c in 0 until CHANNELS) {
            val a = accum[s][c]
            System.arraycopy(a, stride, a, 0, keep)
            java.util.Arrays.fill(a, keep, seg, 0f)
        }
        System.arraycopy(wsum, stride, wsum, 0, keep)
        java.util.Arrays.fill(wsum, keep, seg, 0f)
    }

    // --- audio decode + resample (-> planar s16) -------------------------

    private fun decodeToStereo44k(path: String): Pair<ShortArray, ShortArray> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            var track = -1; var fmt: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    track = i; fmt = f; break
                }
            }
            require(track >= 0 && fmt != null) { "no audio track in $path" }
            extractor.selectTrack(track)
            val srcRate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val srcCh = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val durUs = if (fmt.containsKey(MediaFormat.KEY_DURATION))
                fmt.getLong(MediaFormat.KEY_DURATION) else 0L
            val estFrames = if (durUs > 0) (durUs * srcRate / 1_000_000L).toInt() else 1 shl 20

            codec = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
                .apply { configure(fmt, null, null, 0); start() }
            val left = ShortArrayOutput(estFrames); val right = ShortArrayOutput(estFrames)
            val info = MediaCodec.BufferInfo()
            var inDone = false; var outDone = false
            while (!outDone) {
                if (!inDone) {
                    val ii = codec.dequeueInputBuffer(10_000)
                    if (ii >= 0) {
                        val ib = codec.getInputBuffer(ii)!!
                        val sz = extractor.readSampleData(ib, 0)
                        if (sz < 0) { codec.queueInputBuffer(ii, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inDone = true }
                        else { codec.queueInputBuffer(ii, 0, sz, extractor.sampleTime, 0); extractor.advance() }
                    }
                }
                val oi = codec.dequeueOutputBuffer(info, 10_000)
                if (oi >= 0) {
                    val sb = codec.getOutputBuffer(oi)!!.order(ByteOrder.nativeOrder()).asShortBuffer()
                    while (sb.hasRemaining()) {
                        val l = sb.get()
                        if (srcCh >= 2 && sb.hasRemaining()) {
                            val r = sb.get(); left.add(l); right.add(r)
                            var c = 2; while (c < srcCh && sb.hasRemaining()) { sb.get(); c++ }
                        } else { left.add(l); right.add(l) }
                    }
                    codec.releaseOutputBuffer(oi, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outDone = true
                }
            }
            var l = left.toArray(); var r = right.toArray()
            if (srcRate != SR) { l = resampleS16(l, srcRate, SR); r = resampleS16(r, srcRate, SR) }
            return Pair(l, r)
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            try { extractor.release() } catch (_: Throwable) {}
        }
    }

    private fun resampleS16(x: ShortArray, from: Int, to: Int): ShortArray {
        if (from == to || x.isEmpty()) return x
        val ratio = to.toDouble() / from
        val n = (x.size * ratio).toInt()
        val y = ShortArray(n)
        for (i in 0 until n) {
            val sp = i / ratio; val i0 = sp.toInt(); val frac = (sp - i0).toFloat()
            val a = x[min(i0, x.size - 1)].toFloat()
            val b = x[min(i0 + 1, x.size - 1)].toFloat()
            y[i] = (a + (b - a) * frac).toInt().toShort()
        }
        return y
    }

    // --- helpers ----------------------------------------------------------

    /** Create an OrtSession with the requested execution provider, falling
     *  back to plain CPU (MLAS) on any provider-init failure. Lets us
     *  ship NNAPI by default without crashing devices whose NPU drivers
     *  reject the model -- those just get the proven CPU path. */
    private fun createSessionWithFallback(
        modelPath: String, threads: Int, provider: String,
    ): OrtSession {
        fun base(): OrtSession.SessionOptions = OrtSession.SessionOptions().apply {
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT)
            setIntraOpNumThreads(threads)
            try { addConfigEntry("session.use_device_allocator_for_initializers", "1") } catch (_: Throwable) {}
        }
        if (provider.equals("nnapi", ignoreCase = true)) {
            try {
                val opts = base().apply {
                    addNnapi(java.util.EnumSet.noneOf(ai.onnxruntime.providers.NNAPIFlags::class.java))
                }
                return env.createSession(modelPath, opts)
            } catch (e: Throwable) {
                android.util.Log.w("StemPipeline",
                    "NNAPI EP failed, falling back to CPU: ${e.message}")
            }
        }
        return env.createSession(modelPath, base())
    }

    private fun bartlett(m: Int): FloatArray {
        val w = FloatArray(m); val half = (m - 1) / 2.0
        for (n in 0 until m) w[n] = (1.0 - abs((n - half) / half)).toFloat().coerceAtLeast(1e-3f)
        return w
    }

    private fun toS16(f: Float): Short = (max(-1f, min(1f, f)) * 32767f).toInt().toShort()

    /** Growable ShortArray (no boxing) for the decode buffers. */
    private class ShortArrayOutput(initial: Int) {
        private var a = ShortArray(max(initial, 1024)); private var n = 0
        fun add(v: Short) { if (n == a.size) a = a.copyOf(a.size * 2); a[n++] = v }
        fun toArray(): ShortArray = a.copyOf(n)
    }

    /** Reusable little-endian byte buffer for s16 flush. */
    private class ByteArrayOutput(cap: Int) {
        private val a = ByteArray(cap); private var n = 0
        fun reset() { n = 0 }
        fun size() = n
        fun array() = a
        fun putShortLE(v: Short) {
            val i = v.toInt(); a[n++] = (i and 0xFF).toByte(); a[n++] = ((i shr 8) and 0xFF).toByte()
        }
    }
}
