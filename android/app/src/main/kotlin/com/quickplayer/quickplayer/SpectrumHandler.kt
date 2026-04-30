package com.quickplayer.quickplayer

import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import android.util.Log
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

    companion object {
        private const val TAG = "QPSpectrum"
    }

    private var visualizer: Visualizer? = null
    private var currentSessionId: Int = 0
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var frameCount: Int = 0

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
            Log.i(TAG, "Visualizer.start sessionId=$sessionId")

            val v = Visualizer(sessionId)
            // 1024 samples is the Visualizer default and gives 256 freq bins.
            v.captureSize = Visualizer.getCaptureSizeRange()[1].coerceAtMost(1024)
            v.scalingMode = Visualizer.SCALING_MODE_NORMALIZED
            v.measurementMode = Visualizer.MEASUREMENT_MODE_NONE

            val rate = Visualizer.getMaxCaptureRate().coerceAtMost(20000)
            Log.i(TAG, "captureSize=${v.captureSize} rate=$rate samplingRate=${v.samplingRate}")
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
                        val sink = eventSink ?: run {
                            if (frameCount < 3) Log.w(TAG, "fft frame received but no eventSink")
                            return
                        }
                        if (frameCount < 3 || frameCount % 60 == 0) {
                            // Sample-log first few frames + every ~1 sec at 60Hz
                            var maxAbs = 0
                            for (b in fft) {
                                val a = if (b < 0) -b.toInt() else b.toInt()
                                if (a > maxAbs) maxAbs = a
                            }
                            Log.i(TAG, "fft #$frameCount len=${fft.size} maxAbs=$maxAbs samplingRate=$samplingRate")
                        }
                        frameCount++
                        // sink methods must be called on the platform thread,
                        // and Visualizer fires on its own thread.
                        mainHandler.post {
                            try {
                                sink.success(
                                    mapOf(
                                        "fft" to fft,
                                        // Visualizer reports sampling rate in milliHz; convert to Hz for Dart.
"samplingRate" to samplingRate / 1000,
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
            frameCount = 0
            Log.i(TAG, "Visualizer enabled. capabilities=${buildCapabilities()}")
            result.success(buildCapabilities())
        } catch (e: RuntimeException) {
            Log.e(TAG, "Visualizer construction failed", e)
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
        Log.i(TAG, "EventChannel onListen")
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        Log.i(TAG, "EventChannel onCancel")
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
            "samplingRate" to v.samplingRate / 1000,
            "maxCaptureRate" to Visualizer.getMaxCaptureRate()
        )
    }
}
