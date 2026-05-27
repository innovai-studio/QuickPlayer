package com.quickplayer.quickplayer

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Encodes a stereo f32 stem to an AAC .m4a. The pipeline produces ~130 MB
 * of raw PCM per full-song stem; AAC at 192 kbps brings each stem to a
 * few MB so a 4-stem cache is ~10-15 MB/song instead of ~500 MB.
 */
object AacEncoder {

    private const val MIME = "audio/mp4a-latm"
    private const val BITRATE = 192_000

    /** @param ch planar [L, R], each [frames] f32 samples in [-1, 1]. */
    fun encode(out: File, ch: Array<FloatArray>, frames: Int, sampleRate: Int) {
        out.parentFile?.mkdirs()
        if (out.exists()) out.delete()

        val format = MediaFormat.createAudioFormat(MIME, sampleRate, 2).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, BITRATE)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 32 * 1024)
        }
        val codec = MediaCodec.createEncoderByType(MIME).apply {
            configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            start()
        }
        val muxer = MediaMuxer(out.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var trackIndex = -1
        var muxerStarted = false
        val info = MediaCodec.BufferInfo()

        var framePos = 0
        var inputDone = false
        var outputDone = false
        val usPerFrame = 1_000_000.0 / sampleRate

        try {
            while (!outputDone) {
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val buf = codec.getInputBuffer(inIdx)!!
                        buf.clear()
                        // Fill with interleaved s16 until the buffer is full or
                        // we run out of frames.
                        val capFrames = buf.capacity() / 4   // 2 ch * 2 bytes
                        val n = min(capFrames, frames - framePos)
                        val sb = buf.order(ByteOrder.LITTLE_ENDIAN)
                        for (i in 0 until n) {
                            sb.putShort(toS16(ch[0][framePos + i]))
                            sb.putShort(toS16(ch[1][framePos + i]))
                        }
                        val ptsUs = (framePos * usPerFrame).toLong()
                        if (n <= 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, ptsUs,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inIdx, 0, n * 4, ptsUs, 0)
                            framePos += n
                            if (framePos >= frames) { /* next call emits EOS */ }
                        }
                    }
                }

                val outIdx = codec.dequeueOutputBuffer(info, 10_000)
                when {
                    outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        trackIndex = muxer.addTrack(codec.outputFormat)
                        muxer.start(); muxerStarted = true
                    }
                    outIdx >= 0 -> {
                        val encoded = codec.getOutputBuffer(outIdx)!!
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                            info.size = 0
                        }
                        if (info.size > 0 && muxerStarted) {
                            encoded.position(info.offset)
                            encoded.limit(info.offset + info.size)
                            muxer.writeSampleData(trackIndex, encoded, info)
                        }
                        codec.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    }
                }
            }
        } finally {
            try { codec.stop() } catch (_: Throwable) {}
            try { codec.release() } catch (_: Throwable) {}
            try { if (muxerStarted) muxer.stop() } catch (_: Throwable) {}
            try { muxer.release() } catch (_: Throwable) {}
        }
    }

    private fun toS16(f: Float): Short =
        (max(-1f, min(1f, f)) * 32767f).roundToInt().toShort()
}
