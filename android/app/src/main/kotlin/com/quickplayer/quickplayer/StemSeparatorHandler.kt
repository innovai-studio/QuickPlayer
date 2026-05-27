package com.quickplayer.quickplayer

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.nio.FloatBuffer
import java.util.EnumSet

/**
 * On-device htdemucs stem separation via ONNX Runtime.
 *
 * Phase 1 (this file): a `benchmark` method that loads the exported
 * .onnx and runs a single 7.8 s segment under a chosen execution
 * provider (CPU / XNNPACK / NNAPI), returning real device timings. The
 * exported model takes a fixed (1, 2, 343980) f32 input and returns
 * (1, 4, 2, 343980) -- see docs/STEM_ONNX_EXPORT_SPIKE.md and
 * tools/stem_onnx/. The desktop projection was 5-11 min/song CPU,
 * 3-3.8 min with XNNPACK; this measures the truth on the actual device.
 */
class StemSeparatorHandler(
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    StemSeparationService.Listener {

    companion object {
        private const val CHANNELS = 2
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val env: OrtEnvironment by lazy { OrtEnvironment.getEnvironment() }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressSink: EventChannel.EventSink? = null

    // --- progress EventChannel (com.quickplayer/stem_separator/progress) ---

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        progressSink = events
        StemSeparationService.listener = this
    }

    override fun onCancel(arguments: Any?) {
        progressSink = null
    }

    // Service callbacks -> Flutter sink (always on the main thread).
    override fun onProgress(progress: Double) {
        mainHandler.post { progressSink?.success(mapOf("event" to "progress", "progress" to progress)) }
    }

    override fun onDone(stems: List<String>) {
        mainHandler.post { progressSink?.success(mapOf("event" to "done", "stems" to stems)) }
    }

    override fun onError(message: String) {
        mainHandler.post { progressSink?.success(mapOf("event" to "error", "error" to message)) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "benchmark" -> benchmark(call, result)
            "separate" -> separate(call, result)
            "totalRamMb" -> result.success(totalRamMb())
            "isRunning" -> result.success(StemSeparationService.isRunning)
            else -> result.notImplemented()
        }
    }

    /** P2b: start the foreground service that runs the separation.
     *  Returns immediately; progress/done/error arrive on the progress
     *  EventChannel. */
    private fun separate(call: MethodCall, result: MethodChannel.Result) {
        val modelPath = call.argument<String>("modelPath")
        val audioPath = call.argument<String>("audioPath")
        val outDir = call.argument<String>("outDir")
        val threads = call.argument<Int>("threads") ?: 4
        if (modelPath == null || audioPath == null || outDir == null) {
            result.error("ARGS", "modelPath, audioPath, outDir required", null); return
        }
        if (StemSeparationService.isRunning) {
            result.error("BUSY", "a separation is already running", null); return
        }
        val intent = Intent(context, StemSeparationService::class.java).apply {
            putExtra(StemSeparationService.EXTRA_MODEL, modelPath)
            putExtra(StemSeparationService.EXTRA_AUDIO, audioPath)
            putExtra(StemSeparationService.EXTRA_OUT, outDir)
            putExtra(StemSeparationService.EXTRA_THREADS, threads)
        }
        ContextCompat.startForegroundService(context, intent)
        result.success(mapOf("started" to true))
    }

    private fun benchmark(call: MethodCall, result: MethodChannel.Result) {
        val modelPath = call.argument<String>("modelPath")
        val provider = call.argument<String>("provider") ?: "cpu"
        val threads = call.argument<Int>("threads") ?: 4
        val rawPath = call.argument<String>("inputRawPath")   // optional real audio
        if (modelPath == null || !File(modelPath).exists()) {
            result.error("NO_MODEL", "model not found at $modelPath", null)
            return
        }
        scope.launch {
            val out = try {
                runBenchmark(modelPath, provider, threads, rawPath)
            } catch (e: Throwable) {
                mapOf("ok" to false, "error" to (e.message ?: e.toString()))
            }
            withContext(Dispatchers.Main) { result.success(out) }
        }
    }

    private fun runBenchmark(
        modelPath: String,
        provider: String,
        threads: Int,
        rawPath: String?,
    ): Map<String, Any> {
        val opts = OrtSession.SessionOptions().apply {
            // BASIC (not ALL): ALL_OPT runs heavy in-memory graph transforms
            // that transiently need 2-3x the model size and OOM-killed us on
            // the 4 GB Pixel 3 XL. BASIC is low-memory + hardware-neutral; the
            // execution providers below do the real acceleration anyway.
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT)
            setIntraOpNumThreads(threads)
            // Keep mmap'd external-data weights file-backed (evictable) rather
            // than copied onto the heap, to cut the killable RSS.
            try { addConfigEntry("session.use_device_allocator_for_initializers", "1") } catch (_: Throwable) {}
            when (provider.lowercase()) {
                "nnapi" -> addNnapi(EnumSet.noneOf(NnapiFlag::class.java))
                "xnnpack" -> addXnnpack(mapOf("intra_op_num_threads" to threads.toString()))
                else -> { /* default CPU (MLAS) */ }
            }
        }

        val tLoad0 = System.nanoTime()
        val session = env.createSession(modelPath, opts)
        val loadMs = (System.nanoTime() - tLoad0) / 1_000_000

        val inputName = session.inputNames.iterator().next()
        // Segment length is whatever the exported model fixes its input to
        // (we test 2 s / 3.9 s / 7.8 s variants), so read it off the model
        // rather than hardcoding.
        val inShape = session.inputInfo[inputName]!!.info
            .let { (it as ai.onnxruntime.TensorInfo).shape }
        val seg = inShape[2].toInt()
        val data = FloatArray(CHANNELS * seg)
        if (rawPath != null && File(rawPath).exists()) {
            // raw is interleaved stereo f32; de-interleave into [L..., R...]
            val raw = File(rawPath).readBytes()
            val fb = java.nio.ByteBuffer.wrap(raw)
                .order(java.nio.ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
            val frames = minOf(seg, fb.limit() / CHANNELS)
            for (i in 0 until frames) {
                data[i] = fb.get(i * 2)            // L channel, planar
                data[seg + i] = fb.get(i * 2 + 1)  // R channel, planar
            }
        }
        val shape = longArrayOf(1, CHANNELS.toLong(), seg.toLong())

        // One warm-up run (kernel/arena init) then a timed run.
        var outShape: LongArray
        var absMean: Double
        OnnxTensor.createTensor(env, FloatBuffer.wrap(data), shape).use { input ->
            val feeds = mapOf(inputName to input)
            session.run(feeds).use { /* warm-up */ }

            val tInfer0 = System.nanoTime()
            session.run(feeds).use { res ->
                val inferMs = (System.nanoTime() - tInfer0) / 1_000_000
                @Suppress("UNCHECKED_CAST")
                val arr = res[0].value
                outShape = (res[0] as OnnxTensor).info.shape
                absMean = flatAbsMean(arr)
                return mapOf(
                    "ok" to true,
                    "provider" to provider,
                    "threads" to threads,
                    "loadMs" to loadMs,
                    "inferMs" to inferMs,
                    // segments to cover a ~370 s song at this segment length
                    "fullSongEstSec" to (inferMs * (370.0 / (seg / 44100.0)) / 1000.0),
                    "outShape" to outShape.toList(),
                    "outAbsMean" to absMean,
                ).also { session.close() }
            }
        }
        session.close()
        return mapOf("ok" to false, "error" to "unreachable")
    }

    /** Mean absolute value over the nested float output, to confirm the
     *  result is finite and non-trivial (not all-zero / NaN). */
    private fun flatAbsMean(v: Any?): Double {
        var sum = 0.0; var n = 0L
        fun walk(o: Any?) {
            when (o) {
                is FloatArray -> for (x in o) { sum += kotlin.math.abs(x); n++ }
                is Array<*> -> for (e in o) walk(e)
            }
        }
        walk(v)
        return if (n == 0L) 0.0 else sum / n
    }

    /** Total device RAM in MB, used to pick the segment length / model. */
    private fun totalRamMb(): Int {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        val mi = android.app.ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        return (mi.totalMem / (1024 * 1024)).toInt()
    }

    fun release() {
        scope.cancel()
        progressSink = null
        // Don't null the service listener if a job is still running in the
        // background -- only detach if it points back at us.
        if (StemSeparationService.listener === this && !StemSeparationService.isRunning) {
            StemSeparationService.listener = null
        }
    }
}

// NNAPI flags enum lives in ai.onnxruntime.providers; alias kept local so
// the import line stays tidy across ORT versions.
private typealias NnapiFlag = ai.onnxruntime.providers.NNAPIFlags
