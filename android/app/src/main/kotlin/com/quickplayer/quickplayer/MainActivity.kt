package com.quickplayer.quickplayer

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import java.nio.ByteOrder
import kotlin.math.ln
import kotlin.math.roundToInt
import kotlin.math.sqrt
import kotlin.math.cos
import kotlin.math.PI

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.quickplayer/audio_analyzer"
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "analyzeBpmAndKey" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARGUMENT", "File path is required", null)
                        return@setMethodCallHandler
                    }

                    scope.launch {
                        try {
                            val analysisResult = analyzeAudio(filePath)
                            withContext(Dispatchers.Main) {
                                result.success(analysisResult)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("ANALYSIS_ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun analyzeAudio(filePath: String): Map<String, Any?> {
        val file = File(filePath)
        if (!file.exists()) {
            throw Exception("File not found: $filePath")
        }

        var bpm: Int? = null
        var key: String? = null
        var sampleRate = 44100

        try {
            val decodeResult = decodeAudioToSamples(filePath)
            if (decodeResult != null) {
                val (samples, rate) = decodeResult
                sampleRate = rate
                if (samples.isNotEmpty()) {
                    bpm = detectBpmAutocorrelation(samples, sampleRate)
                    key = detectKeyChroma(samples, sampleRate)
                }
            }
        } catch (e: Exception) {
            // Analysis failed silently
        }

        return mapOf(
            "bpm" to bpm,
            "key" to key
        )
    }

    private fun decodeAudioToSamples(filePath: String): Pair<FloatArray, Int>? {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(filePath)

            var audioTrackIndex = -1
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    break
                }
            }

            if (audioTrackIndex < 0) return null

            extractor.selectTrack(audioTrackIndex)
            val format = extractor.getTrackFormat(audioTrackIndex)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            val codec = MediaCodec.createDecoderByType(mime)
            codec.configure(format, null, null, 0)
            codec.start()

            val samples = mutableListOf<Float>()
            val bufferInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            // Analyze first 30 seconds for faster results
            val maxSamples = sampleRate * 30

            while (!outputDone && samples.size < maxSamples) {
                if (!inputDone) {
                    val inputBufferIndex = codec.dequeueInputBuffer(10000)
                    if (inputBufferIndex >= 0) {
                        val inputBuffer = codec.getInputBuffer(inputBufferIndex)!!
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(inputBufferIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(inputBufferIndex, 0, sampleSize, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outputBufferIndex = codec.dequeueOutputBuffer(bufferInfo, 10000)
                if (outputBufferIndex >= 0) {
                    val outputBuffer = codec.getOutputBuffer(outputBufferIndex)!!
                    outputBuffer.order(ByteOrder.nativeOrder())

                    val shortBuffer = outputBuffer.asShortBuffer()
                    while (shortBuffer.hasRemaining() && samples.size < maxSamples) {
                        var sum = 0f
                        for (c in 0 until channels) {
                            if (shortBuffer.hasRemaining()) {
                                sum += shortBuffer.get() / 32768f
                            }
                        }
                        samples.add(sum / channels)
                    }

                    codec.releaseOutputBuffer(outputBufferIndex, false)

                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        outputDone = true
                    }
                }
            }

            codec.stop()
            codec.release()
            extractor.release()

            return Pair(samples.toFloatArray(), sampleRate)
        } catch (e: Exception) {
            extractor.release()
            return null
        }
    }

    /**
     * BPM detection using autocorrelation of the energy envelope
     */
    private fun detectBpmAutocorrelation(samples: FloatArray, sampleRate: Int): Int? {
        if (samples.size < sampleRate * 4) return null

        // Calculate energy envelope with 10ms windows
        val windowSize = sampleRate / 100  // 10ms
        val energyEnvelope = mutableListOf<Float>()

        for (i in 0 until samples.size - windowSize step windowSize) {
            var energy = 0f
            for (j in 0 until windowSize) {
                energy += samples[i + j] * samples[i + j]
            }
            energyEnvelope.add(sqrt(energy / windowSize))
        }

        if (energyEnvelope.size < 100) return null

        // Apply low-pass filter to smooth envelope
        val smoothed = lowPassFilter(energyEnvelope.toFloatArray(), 0.1f)

        // Calculate onset strength (derivative)
        val onsetStrength = FloatArray(smoothed.size - 1)
        for (i in 0 until smoothed.size - 1) {
            val diff = smoothed[i + 1] - smoothed[i]
            onsetStrength[i] = if (diff > 0) diff else 0f
        }

        // Autocorrelation for BPM range 60-200
        val envelopeRate = 100f // 100 samples per second (10ms windows)
        val minLag = (envelopeRate * 60 / 200).toInt() // 200 BPM
        val maxLag = (envelopeRate * 60 / 60).toInt()  // 60 BPM

        var bestLag = minLag
        var bestCorr = 0f

        for (lag in minLag until minOf(maxLag, onsetStrength.size / 2)) {
            var corr = 0f
            var count = 0
            for (i in 0 until onsetStrength.size - lag) {
                corr += onsetStrength[i] * onsetStrength[i + lag]
                count++
            }
            if (count > 0) {
                corr /= count
                if (corr > bestCorr) {
                    bestCorr = corr
                    bestLag = lag
                }
            }
        }

        val bpm = (envelopeRate * 60 / bestLag).roundToInt()

        // Validate BPM is in reasonable range
        return if (bpm in 50..220) bpm else null
    }

    /**
     * Key detection using chroma features
     */
    private fun detectKeyChroma(samples: FloatArray, sampleRate: Int): String? {
        if (samples.size < sampleRate * 2) return null

        val noteNames = arrayOf("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")

        // Krumhansl-Schmuckler key profiles
        val majorProfile = doubleArrayOf(6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88)
        val minorProfile = doubleArrayOf(6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17)

        // Calculate chroma features using simple DFT at note frequencies
        val chromagram = DoubleArray(12) { 0.0 }
        val frameSize = 4096
        val hopSize = 2048
        var frameCount = 0

        // Reference frequencies for each pitch class (C4 to B4)
        val referenceFreqs = doubleArrayOf(
            261.63, 277.18, 293.66, 311.13, 329.63, 349.23,
            369.99, 392.00, 415.30, 440.00, 466.16, 493.88
        )

        for (start in 0 until (samples.size - frameSize) step hopSize) {
            // Apply Hann window
            val frame = FloatArray(frameSize)
            for (i in 0 until frameSize) {
                val window = 0.5f * (1 - cos(2 * PI * i / (frameSize - 1))).toFloat()
                frame[i] = samples[start + i] * window
            }

            // Calculate energy at each pitch class frequency (and octaves)
            for (pitchClass in 0 until 12) {
                var totalEnergy = 0.0
                // Check multiple octaves (2-6)
                for (octave in 2..6) {
                    val freq = referenceFreqs[pitchClass] * (1 shl (octave - 4))
                    if (freq < sampleRate / 2) {
                        val energy = goertzel(frame, freq, sampleRate)
                        totalEnergy += energy
                    }
                }
                chromagram[pitchClass] += totalEnergy
            }
            frameCount++
        }

        if (frameCount == 0) return null

        // Normalize
        val maxChroma = chromagram.maxOrNull() ?: return null
        if (maxChroma <= 0) return null

        for (i in chromagram.indices) {
            chromagram[i] /= maxChroma
        }

        // Find best matching key using correlation
        var bestKey = ""
        var bestCorr = Double.MIN_VALUE

        for (root in 0 until 12) {
            val majorCorr = pearsonCorrelation(chromagram, rotateProfile(majorProfile, root))
            if (majorCorr > bestCorr) {
                bestCorr = majorCorr
                bestKey = "${noteNames[root]} Major"
            }

            val minorCorr = pearsonCorrelation(chromagram, rotateProfile(minorProfile, root))
            if (minorCorr > bestCorr) {
                bestCorr = minorCorr
                bestKey = "${noteNames[root]} Minor"
            }
        }

        return if (bestCorr > 0.4) bestKey else null
    }

    /**
     * Goertzel algorithm - efficient single frequency DFT
     */
    private fun goertzel(samples: FloatArray, targetFreq: Double, sampleRate: Int): Double {
        val k = (0.5 + samples.size * targetFreq / sampleRate).toInt()
        val omega = 2 * PI * k / samples.size
        val coeff = 2 * cos(omega)

        var s0 = 0.0
        var s1 = 0.0
        var s2 = 0.0

        for (sample in samples) {
            s0 = sample + coeff * s1 - s2
            s2 = s1
            s1 = s0
        }

        return sqrt(s1 * s1 + s2 * s2 - coeff * s1 * s2)
    }

    private fun rotateProfile(profile: DoubleArray, offset: Int): DoubleArray {
        val rotated = DoubleArray(12)
        for (i in 0 until 12) {
            rotated[i] = profile[(i + 12 - offset) % 12]
        }
        return rotated
    }

    private fun pearsonCorrelation(x: DoubleArray, y: DoubleArray): Double {
        val n = x.size
        var sumX = 0.0
        var sumY = 0.0
        var sumXY = 0.0
        var sumX2 = 0.0
        var sumY2 = 0.0

        for (i in 0 until n) {
            sumX += x[i]
            sumY += y[i]
            sumXY += x[i] * y[i]
            sumX2 += x[i] * x[i]
            sumY2 += y[i] * y[i]
        }

        val numerator = n * sumXY - sumX * sumY
        val denominator = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY))

        return if (denominator > 0) numerator / denominator else 0.0
    }

    private fun lowPassFilter(input: FloatArray, alpha: Float): FloatArray {
        val output = FloatArray(input.size)
        output[0] = input[0]
        for (i in 1 until input.size) {
            output[i] = alpha * input[i] + (1 - alpha) * output[i - 1]
        }
        return output
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}
