package com.quickplayer.quickplayer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.TensorInfo
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.File
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Full-song stem separation pipeline (P2a): decode -> resample to
 * 44.1 kHz stereo -> run htdemucs ONNX over overlapping segments with a
 * Bartlett-weighted overlap-add -> write 4 stems as raw f32 (planar
 * stereo) for now. This is the on-device port of
 * tools/stem_onnx/fullsong_separate.py (verified-good quality at 2s/3.9s/
 * 7.8s). Segment length is read from the model, so the caller picks the
 * RAM-appropriate model variant.
 *
 * Progress is reported via [onProgress] (0..1). Caller runs this off the
 * main thread (and, in P2b, inside a foreground service).
 */
class StemPipeline(private val env: OrtEnvironment) {

    companion object {
        const val SR = 44100
        const val CHANNELS = 2
        val SOURCES = listOf("drums", "bass", "other", "vocals")
        private const val OVERLAP = 0.25
    }

    /** @return list of 4 output files (drums/bass/other/vocals .f32). */
    fun separate(
        modelPath: String,
        audioPath: String,
        outDir: String,
        threads: Int = 4,
        onProgress: (Double) -> Unit = {},
    ): List<String> {
        val (pcm, frames) = decodeToStereo44k(audioPath)   // (2, frames) planar
        onProgress(0.05)

        val opts = OrtSession.SessionOptions().apply {
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT)
            setIntraOpNumThreads(threads)
        }
        val session = env.createSession(modelPath, opts)
        try {
            val inName = session.inputNames.iterator().next()
            val seg = (session.inputInfo[inName]!!.info as TensorInfo).shape[2].toInt()
            val stride = (seg * (1 - OVERLAP)).toInt()
            val win = bartlett(seg)

            // Accumulators: 4 sources x 2 channels x frames, plus weight sum.
            val out = Array(4) { Array(CHANNELS) { FloatArray(frames) } }
            val wsum = FloatArray(frames)

            val chunk = FloatArray(CHANNELS * seg)
            var pos = 0
            while (pos < frames) {
                val len = min(seg, frames - pos)
                // Fill planar [L.., R..]; zero-pad the tail of the last chunk.
                java.util.Arrays.fill(chunk, 0f)
                for (i in 0 until len) {
                    chunk[i] = pcm[0][pos + i]
                    chunk[seg + i] = pcm[1][pos + i]
                }
                val shape = longArrayOf(1, CHANNELS.toLong(), seg.toLong())
                OnnxTensor.createTensor(env, FloatBuffer.wrap(chunk), shape).use { input ->
                    session.run(mapOf(inName to input)).use { res ->
                        // output (1, 4, 2, seg) row-major
                        val flat = flatten(res[0].value)
                        var k = 0
                        for (s in 0 until 4) for (c in 0 until CHANNELS) {
                            val base = out[s][c]
                            for (i in 0 until seg) {
                                val v = flat[k++]
                                if (i < len) base[pos + i] += v * win[i]
                            }
                        }
                    }
                }
                for (i in 0 until len) wsum[pos + i] += win[i]
                pos += stride
                onProgress(0.05 + 0.85 * min(1.0, pos.toDouble() / frames))
            }

            // Normalize by accumulated weight + encode each stem to AAC
            // (.m4a). Raw f32 would be ~130 MB/stem for a full song; AAC
            // keeps the 4-stem cache to ~10-15 MB.
            val files = ArrayList<String>(4)
            File(outDir).mkdirs()
            for (s in 0 until 4) {
                for (c in 0 until CHANNELS) {
                    val arr = out[s][c]
                    for (i in 0 until frames) arr[i] /= max(wsum[i], 1e-6f)
                }
                val f = File(outDir, "${SOURCES[s]}.m4a")
                AacEncoder.encode(f, out[s], frames, SR)
                files.add(f.absolutePath)
                onProgress(0.90 + 0.10 * (s + 1) / 4.0)  // encode phase
            }
            onProgress(1.0)
            return files
        } finally {
            session.close()
        }
    }

    // --- audio decode + resample ----------------------------------------

    /** Decode any supported file to 44.1 kHz stereo planar f32. */
    private fun decodeToStereo44k(path: String): Pair<Array<FloatArray>, Int> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(path)
            var track = -1
            var fmt: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    track = i; fmt = f; break
                }
            }
            require(track >= 0 && fmt != null) { "no audio track" }
            extractor.selectTrack(track)
            val srcRate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val srcCh = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val mime = fmt.getString(MediaFormat.KEY_MIME)!!

            codec = MediaCodec.createDecoderByType(mime).apply { configure(fmt, null, null, 0); start() }
            // Collect decoded mono-per-channel into growable buffers (planar).
            val left = FloatArrayList(); val right = FloatArrayList()
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
                    val ob = codec.getOutputBuffer(oi)!!.order(ByteOrder.nativeOrder())
                    val sb = ob.asShortBuffer()
                    while (sb.hasRemaining()) {
                        val l = sb.get() / 32768f
                        if (srcCh >= 2 && sb.hasRemaining()) {
                            val r = sb.get() / 32768f
                            left.add(l); right.add(r)
                            // skip any extra channels in this frame
                            var c = 2; while (c < srcCh && sb.hasRemaining()) { sb.get(); c++ }
                        } else { left.add(l); right.add(l) } // mono -> dup
                    }
                    codec.releaseOutputBuffer(oi, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outDone = true
                }
            }
            var l = left.toArray(); var r = right.toArray()
            if (srcRate != SR) { l = resampleLinear(l, srcRate, SR); r = resampleLinear(r, srcRate, SR) }
            return Pair(arrayOf(l, r), l.size)
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            try { extractor.release() } catch (_: Throwable) {}
        }
    }

    /** Simple linear resampler (adequate for a first pass; sinc later). */
    private fun resampleLinear(x: FloatArray, from: Int, to: Int): FloatArray {
        if (from == to || x.isEmpty()) return x
        val ratio = to.toDouble() / from
        val n = (x.size * ratio).toInt()
        val y = FloatArray(n)
        for (i in 0 until n) {
            val srcPos = i / ratio
            val i0 = srcPos.toInt(); val frac = (srcPos - i0).toFloat()
            val a = x[min(i0, x.size - 1)]; val b = x[min(i0 + 1, x.size - 1)]
            y[i] = a + (b - a) * frac
        }
        return y
    }

    // --- helpers ----------------------------------------------------------

    private fun bartlett(m: Int): FloatArray {
        val w = FloatArray(m)
        val half = (m - 1) / 2.0
        for (n in 0 until m) w[n] = (1.0 - abs((n - half) / half)).toFloat().coerceAtLeast(1e-3f)
        return w
    }

    private fun flatten(v: Any?): FloatArray {
        val list = ArrayList<Float>()
        fun walk(o: Any?) { when (o) {
            is FloatArray -> for (x in o) list.add(x)
            is Array<*> -> for (e in o) walk(e)
        } }
        walk(v)
        return list.toFloatArray()
    }

    /** Minimal growable float buffer to avoid boxing in decode loop. */
    private class FloatArrayList {
        private var a = FloatArray(1 shl 20); private var n = 0
        fun add(v: Float) { if (n == a.size) a = a.copyOf(a.size * 2); a[n++] = v }
        fun toArray(): FloatArray = a.copyOf(n)
    }
}
