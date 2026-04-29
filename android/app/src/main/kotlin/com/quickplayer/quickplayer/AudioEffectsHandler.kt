package com.quickplayer.quickplayer

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges com.quickplayer/audio_effects to android.media.audiofx.
 *
 * The Equalizer / BassBoost are bound to the AudioTrack's audio session id,
 * which just_audio (ExoPlayer) exposes via androidAudioSessionIdStream.
 * Effects survive across track loads as long as the session id is stable.
 */
class AudioEffectsHandler : MethodChannel.MethodCallHandler {

    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var currentSessionId: Int = 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> handleInit(call, result)
            "applyPreset" -> handleApplyPreset(call, result)
            "setEnabled" -> handleSetEnabled(call, result)
            "release" -> handleRelease(result)
            else -> result.notImplemented()
        }
    }

    private fun handleInit(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<Int>("sessionId")
        if (sessionId == null || sessionId == 0) {
            result.error("INVALID_ARGUMENT", "sessionId is required and non-zero", null)
            return
        }

        if (sessionId == currentSessionId && equalizer != null) {
            // Already bound to this session.
            result.success(buildCapabilities())
            return
        }

        try {
            release()
            // priority 0 == default; insert effect on the audio track
            equalizer = Equalizer(0, sessionId).apply { enabled = true }
            bassBoost = try {
                BassBoost(0, sessionId).apply { enabled = false }
            } catch (e: Throwable) {
                null // BassBoost is optional; some devices lack it
            }
            currentSessionId = sessionId
            result.success(buildCapabilities())
        } catch (e: Throwable) {
            release()
            result.error("EFFECTS_UNSUPPORTED", e.message ?: "AudioEffect not available", null)
        }
    }

    private fun handleApplyPreset(call: MethodCall, result: MethodChannel.Result) {
        val eq = equalizer
        if (eq == null) {
            result.error("NOT_INITIALIZED", "Effects not initialised yet", null)
            return
        }

        @Suppress("UNCHECKED_CAST")
        val bandLevels = call.argument<List<Int>>("bandLevels")
        val bassStrength = call.argument<Int>("bassStrength") ?: 0
        if (bandLevels == null) {
            result.error("INVALID_ARGUMENT", "bandLevels required", null)
            return
        }

        try {
            val numBands = eq.numberOfBands.toInt()
            val (minLevel, maxLevel) = eq.bandLevelRange.let { it[0].toInt() to it[1].toInt() }

            // Map our 5-band preset onto whatever the device exposes by linear interpolation.
            val mapped = mapBandsTo(bandLevels, numBands)
            for (i in 0 until numBands) {
                val clamped = mapped[i].coerceIn(minLevel, maxLevel).toShort()
                eq.setBandLevel(i.toShort(), clamped)
            }

            bassBoost?.let { bb ->
                if (bb.strengthSupported) {
                    val strength = bassStrength.coerceIn(0, 1000).toShort()
                    bb.setStrength(strength)
                    bb.enabled = strength > 0
                }
            }

            result.success(null)
        } catch (e: Throwable) {
            result.error("APPLY_FAILED", e.message ?: "Failed to apply preset", null)
        }
    }

    private fun handleSetEnabled(call: MethodCall, result: MethodChannel.Result) {
        val enabled = call.argument<Boolean>("enabled") ?: true
        try {
            equalizer?.enabled = enabled
            // BassBoost mirrors enable state but only when there's positive strength.
            bassBoost?.let { bb ->
                bb.enabled = enabled && bb.roundedStrength > 0
            }
            result.success(null)
        } catch (e: Throwable) {
            result.error("ENABLE_FAILED", e.message ?: "Failed to toggle effects", null)
        }
    }

    private fun handleRelease(result: MethodChannel.Result) {
        release()
        result.success(null)
    }

    fun release() {
        try { equalizer?.release() } catch (_: Throwable) {}
        try { bassBoost?.release() } catch (_: Throwable) {}
        equalizer = null
        bassBoost = null
        currentSessionId = 0
    }

    private fun buildCapabilities(): Map<String, Any?> {
        val eq = equalizer ?: return mapOf("supported" to false)
        val numBands = eq.numberOfBands.toInt()
        val centerFreqs = (0 until numBands).map { i -> eq.getCenterFreq(i.toShort()) }
        val range = eq.bandLevelRange
        return mapOf(
            "supported" to true,
            "numberOfBands" to numBands,
            "centerFrequenciesMilliHz" to centerFreqs,
            "minBandLevelMillibel" to range[0].toInt(),
            "maxBandLevelMillibel" to range[1].toInt(),
            "hasBassBoost" to (bassBoost != null)
        )
    }

    /**
     * Linearly interpolate our 5-band preset onto the device's actual band count.
     * Most devices expose 5 bands so this collapses to identity.
     */
    private fun mapBandsTo(source: List<Int>, target: Int): IntArray {
        if (target <= 0) return IntArray(0)
        if (source.isEmpty()) return IntArray(target)
        if (target == source.size) return source.toIntArray()

        val out = IntArray(target)
        val srcLast = source.size - 1
        val tgtLast = target - 1
        for (i in 0 until target) {
            val pos = if (tgtLast == 0) 0.0 else i.toDouble() * srcLast / tgtLast
            val lo = pos.toInt().coerceAtMost(srcLast)
            val hi = (lo + 1).coerceAtMost(srcLast)
            val frac = pos - lo
            out[i] = (source[lo] * (1 - frac) + source[hi] * frac).toInt()
        }
        return out
    }
}
