package com.quickplayer.quickplayer

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream

/**
 * Encodes an interleaved-s16 stereo PCM file to an AAC .m4a, streaming
 * the input so a full-song stem never sits fully in memory. ~192 kbps →
 * a few MB per stem (vs ~130 MB raw), so a 4-stem cache is ~10-15 MB.
 */
object AacEncoder {

    private const val MIME = "audio/mp4a-latm"
    private const val BITRATE = 192_000

    fun encodePcmFile(pcm: File, out: File, sampleRate: Int) {
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
        val input = BufferedInputStream(FileInputStream(pcm), 1 shl 16)
        val usPerFrame = 1_000_000.0 / sampleRate
        var framePos = 0L
        var inputDone = false
        var outputDone = false

        try {
            while (!outputDone) {
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val buf = codec.getInputBuffer(inIdx)!!
                        buf.clear()
                        val tmp = ByteArray(buf.capacity())
                        val read = input.read(tmp)
                        val ptsUs = (framePos * usPerFrame).toLong()
                        if (read <= 0) {
                            codec.queueInputBuffer(inIdx, 0, 0, ptsUs,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            buf.put(tmp, 0, read)
                            codec.queueInputBuffer(inIdx, 0, read, ptsUs, 0)
                            framePos += read / 4   // 2 ch * 2 bytes
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
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && muxerStarted) {
                            encoded.position(info.offset)
                            encoded.limit(info.offset + info.size)
                            muxer.writeSampleData(trackIndex, encoded, info)
                        }
                        codec.releaseOutputBuffer(outIdx, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                    }
                }
            }
        } finally {
            try { input.close() } catch (_: Throwable) {}
            try { codec.stop() } catch (_: Throwable) {}
            try { codec.release() } catch (_: Throwable) {}
            try { if (muxerStarted) muxer.stop() } catch (_: Throwable) {}
            try { muxer.release() } catch (_: Throwable) {}
        }
    }
}
