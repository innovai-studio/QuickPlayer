package com.quickplayer.quickplayer

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

/**
 * 4-track stem mixer backed by four native media3 ExoPlayers.
 *
 * just_audio_background is global in this app and refuses a second
 * just_audio instance, so the mixer can't use just_audio at all. Four
 * ExoPlayers started together stay closely aligned; a periodic resync
 * nudges followers back to the leader (player 0) if they drift. Per-stem
 * mute/solo/volume map to each player's volume. Position + ready state
 * stream to Flutter on an EventChannel.
 *
 * All ExoPlayer access is on the main thread (required by media3).
 */
class StemMixerHandler(
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val main = Handler(Looper.getMainLooper())
    private var players: MutableList<ExoPlayer> = mutableListOf()
    private var sink: EventChannel.EventSink? = null
    private var ticking = false
    // Seeking to fix small drift costs more (flush + rebuffer) than the
    // drift itself, so only correct meaningful drift, and not during the
    // cold-buffer window right after play starts (that caused first-play
    // stutter).
    private val driftToleranceMs = 150L
    private val resyncGraceMs = 1500L
    private var playStartedAtMs = 0L

    // First-play stutter mitigation: AudioTrack hardware cold-start
    // causes the user's first play() to glitch; the workaround the user
    // discovered ("pause + replay from start") just means the tracks are
    // already warm by the second attempt. We do that warm-up cycle
    // silently (volumes 0 -> play -> pause -> seek 0 -> restore) right
    // after all 4 players reach STATE_READY, before reporting ready=true
    // to Flutter. Users tap play once and get smooth first playback.
    private enum class Warmup { PENDING, RUNNING, DONE }
    private var warmup = Warmup.PENDING
    private val warmupDurationMs = 400L

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "prepare" -> {
                val paths = call.argument<List<String>>("paths") ?: emptyList()
                runOnMain { prepare(paths); result.success(true) }
            }
            "play" -> runOnMain {
                playStartedAtMs = System.currentTimeMillis()
                players.forEach { it.play() }
                result.success(null)
            }
            "pause" -> runOnMain { players.forEach { it.pause() }; result.success(null) }
            "seek" -> {
                val ms = (call.argument<Number>("ms") ?: 0).toLong()
                runOnMain { players.forEach { it.seekTo(ms) }; result.success(null) }
            }
            "setVolume" -> {
                val i = call.argument<Int>("index") ?: 0
                val v = (call.argument<Number>("volume") ?: 1.0).toFloat()
                runOnMain { players.getOrNull(i)?.volume = v; result.success(null) }
            }
            "release" -> runOnMain { releasePlayers(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun prepare(paths: List<String>) {
        releasePlayers()
        warmup = Warmup.PENDING
        players = paths.map { path ->
            ExoPlayer.Builder(context).build().apply {
                setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(java.io.File(path))))
                prepare()
            }
        }.toMutableList()
        // Emit on every player's readiness change so the UI only unlocks
        // (and the first play happens) once ALL four are buffered.
        players.forEach { p ->
            p.addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(state: Int) = emit()
            })
        }
        startTicker()
    }

    private fun startTicker() {
        if (ticking) return
        ticking = true
        main.post(object : Runnable {
            override fun run() {
                if (!ticking) return
                resyncAndEmit()
                main.postDelayed(this, 200)
            }
        })
    }

    private fun resyncAndEmit() {
        if (players.isEmpty()) return
        val leader = players[0]
        val pastGrace =
            System.currentTimeMillis() - playStartedAtMs > resyncGraceMs
        if (leader.isPlaying && pastGrace) {
            val lead = leader.currentPosition
            for (i in 1 until players.size) {
                if (abs(players[i].currentPosition - lead) > driftToleranceMs) {
                    players[i].seekTo(lead)
                }
            }
        }
        emit()
    }

    private fun emit() {
        val p = players.getOrNull(0) ?: return
        val dur = if (p.duration == androidx.media3.common.C.TIME_UNSET) 0L else p.duration
        val allReady = players.isNotEmpty() &&
            players.all { it.playbackState == Player.STATE_READY }
        // Buffered position = the slowest stem (the bottleneck for smooth
        // synced playback), so the UI bar reflects when all 4 are safe.
        val buffered = players.minOf { it.bufferedPosition }
        // Hold ready=false until the silent AudioTrack warm-up cycle has
        // finished, so the user's first play() never hits a cold start.
        val readyForUi = allReady && warmup == Warmup.DONE
        sink?.success(
            mapOf(
                "pos" to p.currentPosition,
                "dur" to dur,
                "playing" to (p.isPlaying && warmup == Warmup.DONE),
                "ready" to readyForUi,
                "buffered" to buffered,
            )
        )
        if (allReady && warmup == Warmup.PENDING) startWarmup()
    }

    private fun startWarmup() {
        if (warmup != Warmup.PENDING || players.isEmpty()) return
        warmup = Warmup.RUNNING
        val savedVolumes = players.map { it.volume }
        players.forEach { it.volume = 0f }
        players.forEach { it.play() }
        main.postDelayed({
            players.forEach { it.pause() }
            players.forEach { it.seekTo(0) }
            for (i in players.indices) players[i].volume = savedVolumes[i]
            warmup = Warmup.DONE
            emit()
        }, warmupDurationMs)
    }

    private fun releasePlayers() {
        ticking = false
        players.forEach { it.release() }
        players.clear()
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block)
    }

    // EventChannel (position/state)
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
    override fun onCancel(arguments: Any?) { sink = null }

    fun release() = runOnMain { releasePlayers() }
}
