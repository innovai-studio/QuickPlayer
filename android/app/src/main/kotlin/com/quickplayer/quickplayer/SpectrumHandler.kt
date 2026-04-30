package com.quickplayer.quickplayer

import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges com.quickplayer/spectrum (control + EventChannel) to
 * android.media.audiofx.Visualizer.
 *
 * Two channels:
 *   - MethodChannel for start(sessionId) / stop
 *   - EventChannel for streaming FFT byte[] frames at ~60 Hz
 *
 * Visualizer requires RECORD_AUDIO at runtime on Android 9+. Construction
 * failures are surfaced as channel errors so Dart can prompt the user.
 */
class SpectrumHandler :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var visualizer: Visualizer? = null
    private var currentSessionId: Int = 0
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // ---- MethodChannel ---------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> handleStart(call, result)
            "stop" -> {
                releaseVisualizer()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleStart(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<Int>("sessionId")
        if (sessionId == null || sessionId == 0) {
            result.error("INVALID_ARGUMENT", "sessionId is required and non-zero", null)
            return
        }

        // Same session already running -- nothing to do.
        if (sessionId == currentSessionId && visualizer != null) {
            result.success(buildCapabilities())
            return
        }

        try {
            releaseVisualizer()

            val v = Visualizer(sessionId)
            // 1024 samples is the Visualizer default and gives 256 freq bins.
            v.captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(1024)
            v.scalingMode = Visualizer.SCALING_MODE_NORMALIZED
            v.measurementMode = Visualizer.MEASUREMENT_MODE_NONE

            val rate = Visualizer.getMaxCaptureRate().coerceAtMost(20000)
            v.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        v0: Visualizer?,
                        waveform: ByteArray?,
                        samplingRate: Int
                    ) {
                        // We only enabled FFT below; ignore waveform calls.
                    }

                    override fun onFftDataCapture(
                        v0: Visualizer?,
                        fft: ByteArray?,
                        samplingRate: Int
                    ) {
                        if (fft == null) return
                        val sink = eventSink ?: return
                        // sink methods must be called on the platform thread,
                        // and Visualizer fires on its own thread.
                        mainHandler.post {
                            try {
                                sink.success(
                                    mapOf(
                                        "fft" to fft,
                                        "samplingRate" to samplingRate,
                                        "captureSize" to (v0?.captureSize ?: 0)
                                    )
                                )
                            } catch (_: Throwable) {
                                // sink may have been closed mid-flight
                            }
                        }
                    }
                },
                rate,
                /* waveform = */ false,
                /* fft = */ true
            )
            v.enabled = true

            visualizer = v
            currentSessionId = sessionId
            result.success(buildCapabilities())
        } catch (e: RuntimeException) {
            // Visualizer ctor throws RuntimeException on permission denied.
            releaseVisualizer()
            result.error(
                "VISUALIZER_UNAVAILABLE",
                e.message ?: "Visualizer construction failed",
                null
            )
        } catch (e: Throwable) {
            releaseVisualizer()
            result.error("VISUALIZER_ERROR", e.message, null)
        }
    }

    // ---- EventChannel ----------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ---- Cleanup ---------------------------------------------------------

    private fun releaseVisualizer() {
        try {
            visualizer?.enabled = false
        } catch (_: Throwable) {}
        try {
            visualizer?.release()
        } catch (_: Throwable) {}
        visualizer = null
        currentSessionId = 0
    }

    fun release() {
        releaseVisualizer()
        eventSink = null
    }

    private fun buildCapabilities(): Map<String, Any?> {
        val v = visualizer ?: return mapOf("supported" to false)
        return mapOf(
            "supported" to true,
            "captureSize" to v.captureSize,
            "samplingRate" to v.samplingRate,
            "maxCaptureRate" to Visualizer.getMaxCaptureRate()
        )
    }
}
