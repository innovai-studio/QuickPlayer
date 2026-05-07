package com.quickplayer.quickplayer

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Lightweight SFX playback over Android's SoundPool.
 *
 * The metronome's click was first written on top of just_audio, but
 * once just_audio_background hooked the platform plugin every player
 * went through MediaSession + foreground service -- the wrong path
 * for short low-latency clicks. audioplayers also fought the audio
 * focus model on this ROM and either paused the song or silently
 * dropped clicks.
 *
 * SoundPool side-steps all of that: the OS treats it as a UI/SFX
 * stream that mixes into STREAM_MUSIC alongside the song without
 * requesting focus. Multiple simultaneous plays layer naturally with
 * sample-accurate timing, which is exactly what we need.
 */
class SoundPoolHandler(private val context: Context) :
    MethodChannel.MethodCallHandler {

    private var soundPool: SoundPool? = null
    private val loadedIds = mutableMapOf<String, Int>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> handleLoad(call, result)
            "play" -> handlePlay(call, result)
            "release" -> { release(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun ensurePool(): SoundPool {
        soundPool?.let { return it }
        // CONTENT_TYPE_SONIFICATION + USAGE_MEDIA puts the click on the
        // music stream so it follows the user's media volume, but we
        // never call requestAudioFocus -- which means the song keeps
        // playing untouched.
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val pool = SoundPool.Builder()
            .setMaxStreams(6)
            .setAudioAttributes(attrs)
            .build()
        soundPool = pool
        return pool
    }

    private fun handleLoad(call: MethodCall, result: MethodChannel.Result) {
        val asset = call.argument<String>("asset")
        if (asset == null) {
            result.error("INVALID_ARGUMENT", "asset path required", null)
            return
        }
        loadedIds[asset]?.let { existing ->
            // Already loaded; return the cached id.
            result.success(existing)
            return
        }
        try {
            // Flutter packs all bundled assets under "flutter_assets/<path>"
            // inside the APK. The Dart side passes the original pubspec
            // path (e.g. "assets/sounds/click_high.wav"); we just prefix
            // it. This avoids needing FlutterInjector / FlutterLoader,
            // which aren't always on the classpath of plain
            // FlutterActivity descendants.
            val key = "flutter_assets/$asset"
            val afd = context.assets.openFd(key)
            val pool = ensurePool()
            val soundId = pool.load(afd, 1)
            afd.close()
            loadedIds[asset] = soundId
            result.success(soundId)
        } catch (e: Throwable) {
            result.error("LOAD_FAILED", e.message ?: "SoundPool.load failed", null)
        }
    }

    private fun handlePlay(call: MethodCall, result: MethodChannel.Result) {
        val soundId = call.argument<Int>("soundId")
        val volume = (call.argument<Double>("volume") ?: 1.0).toFloat()
        if (soundId == null) {
            result.error("INVALID_ARGUMENT", "soundId required", null)
            return
        }
        val pool = soundPool
        if (pool == null) {
            result.error("NOT_LOADED", "SoundPool not initialised", null)
            return
        }
        val streamId = pool.play(
            soundId,
            volume.coerceIn(0f, 1f),
            volume.coerceIn(0f, 1f),
            /* priority = */ 1,
            /* loop = */ 0,
            /* rate = */ 1.0f
        )
        result.success(streamId)
    }

    fun release() {
        try { soundPool?.release() } catch (_: Throwable) {}
        soundPool = null
        loadedIds.clear()
    }
}
