package com.quickplayer.quickplayer

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.nio.ByteOrder
import kotlin.math.sqrt

/**
 * Native waveform-peaks extractor.
 *
 * The audio_waveforms Flutter package has a real bug -- its WaveformExtractor
 * never sets `started = true`, so its `stop()` is a no-op and the MediaCodec
 * decoder leaks. The second extractWaveformData call in a process hangs
 * forever waiting for the leaked codec. Rather than fork the package, we
 * decode the file ourselves through the same MediaExtractor + MediaCodec
 * pipeline as the BPM analyzer and aggregate RMS peaks bucket-by-bucket.
 *
 * Decoders are stopped + released in `finally`, so subsequent extractions
 * always start with a fresh codec.
 */
class WaveformPeaksHandler : MethodChannel.MethodCallHandler {

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "extract" -> handleExtract(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleExtract(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        val numSamples = call.argument<Int>("numSamples") ?: 100
        if (filePath == null) {
            result.error("INVALID_ARGUMENT", "filePath required", null)
            return
        }
        scope.launch {
            val peaks = try {
                extractPeaks(filePath, numSamples)
            } catch (e: Throwable) {
                null
            }
            withContext(Dispatchers.Main) {
                if (peaks == null) {
                    result.error("EXTRACT_FAILED", "Could not decode audio", null)
                } else {
                    result.success(peaks)
                }
            }
        }
    }

    private fun extractPeaks(filePath: String, numSamples: Int): List<Double>? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(filePath)

            var audioTrackIndex = -1
            var trackFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    trackFormat = format
                    break
                }
            }
            if (audioTrackIndex < 0 || trackFormat == null) return null

            extractor.selectTrack(audioTrackIndex)
            val format = trackFormat
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val durationUs =
                if (format.containsKey(MediaFormat.KEY_DURATION))
                    format.getLong(MediaFormat.KEY_DURATION)
                else 0L

            // Estimate total mono samples so we can size the buckets up
            // front. If duration is unknown (rare), fall back to a heuristic.
            val totalMonoSamples = if (durationUs > 0)
                (durationUs * sampleRate / 1_000_000L)
            else
                (sampleRate.toLong() * 180) // 3 min default ceiling
            val perBucket = (totalMonoSamples / numSamples).coerceAtLeast(1)

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val buckets = DoubleArray(numSamples)
            val bucketCounts = LongArray(numSamples)
            var bucketIndex = 0
            var bucketRemaining = perBucket
            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false

            while (!outputDone) {
                if (!inputDone) {
                    val inIdx = codec.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) {
                        val inBuf = codec.getInputBuffer(inIdx)!!
                        val sampleSize = extractor.readSampleData(inBuf, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(
                                inIdx, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(
                                inIdx, 0, sampleSize, extractor.sampleTime, 0
                            )
                            extractor.advance()
                        }
                    }
                }

                val outIdx = codec.dequeueOutputBuffer(bufferInfo, 10_000)
                if (outIdx >= 0) {
                    val outBuf = codec.getOutputBuffer(outIdx)!!
                    outBuf.order(ByteOrder.nativeOrder())
                    val shortBuf = outBuf.asShortBuffer()

                    // Read frame-by-frame: one frame = `channels` shorts.
                    // We average channels into a single mono sample, accumulate
                    // its square, and roll over to the next bucket when full.
                    while (shortBuf.hasRemaining()) {
                        var sum = 0f
                        var c = 0
                        while (c < channels && shortBuf.hasRemaining()) {
                            sum += shortBuf.get() / 32768f
                            c++
                        }
                        val mono = sum / channels
                        if (bucketIndex < numSamples) {
                            buckets[bucketIndex] =
                                buckets[bucketIndex] + (mono * mono).toDouble()
                            bucketCounts[bucketIndex] =
                                bucketCounts[bucketIndex] + 1L
                        }
                        bucketRemaining -= 1
                        if (bucketRemaining <= 0 && bucketIndex < numSamples - 1) {
                            bucketIndex += 1
                            bucketRemaining = perBucket
                        }
                    }

                    codec.releaseOutputBuffer(outIdx, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }

            // Compute RMS per bucket and normalise to 0..1 against the loudest
            // bucket. RMS keeps quiet sections visible without being dwarfed
            // by transients (a peak-only normalisation tends to make ballads
            // look flat next to rock songs).
            val rms = DoubleArray(numSamples)
            var maxRms = 0.0
            for (i in 0 until numSamples) {
                if (bucketCounts[i] > 0) {
                    rms[i] = sqrt(buckets[i] / bucketCounts[i])
                    if (rms[i] > maxRms) maxRms = rms[i]
                }
            }
            if (maxRms <= 0) return null
            return rms.map { (it / maxRms).coerceIn(0.0, 1.0) }
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            try { extractor.release() } catch (_: Throwable) {}
        }
    }

    fun release() {
        scope.cancel()
    }
}
