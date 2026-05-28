package com.quickplayer.quickplayer

import ai.onnxruntime.OrtEnvironment
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Foreground service that runs the (multi-minute) stem-separation
 * pipeline so it survives backgrounding and shows a progress
 * notification. Progress / completion are pushed to Flutter through
 * [Listener] (set by StemSeparatorHandler, which owns the EventChannel
 * sink); the notification is the fallback UI when the app isn't
 * foreground.
 */
class StemSeparationService : Service() {

    interface Listener {
        fun onProgress(progress: Double)
        fun onDone(stems: List<String>)
        fun onError(message: String)
    }

    companion object {
        @Volatile var listener: Listener? = null
        @Volatile var isRunning = false

        const val EXTRA_MODEL = "modelPath"
        const val EXTRA_AUDIO = "audioPath"
        const val EXTRA_OUT = "outDir"
        const val EXTRA_THREADS = "threads"
        const val EXTRA_PROVIDER = "provider"
        private const val CHANNEL_ID = "stem_separation"
        private const val NOTIF_ID = 7011
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var job: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val model = intent?.getStringExtra(EXTRA_MODEL)
        val audio = intent?.getStringExtra(EXTRA_AUDIO)
        val outDir = intent?.getStringExtra(EXTRA_OUT)
        val threads = intent?.getIntExtra(EXTRA_THREADS, 4) ?: 4
        val provider = intent?.getStringExtra(EXTRA_PROVIDER) ?: "cpu"
        if (model == null || audio == null || outDir == null) {
            stopSelf(); return START_NOT_STICKY
        }

        startForegroundCompat(notify("Separating stems…", 0))
        isRunning = true
        job = scope.launch {
            try {
                val files = StemPipeline(OrtEnvironment.getEnvironment())
                    .separate(model, audio, outDir, threads, provider) { p ->
                        updateNotification("Separating stems…", (p * 100).toInt())
                        listener?.onProgress(p)
                    }
                listener?.onDone(files)
            } catch (e: Throwable) {
                listener?.onError(e.message ?: e.toString())
            } finally {
                isRunning = false
                stopForegroundCompat()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        isRunning = false
        super.onDestroy()
    }

    // --- notification ----------------------------------------------------

    private fun startForegroundCompat(n: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
    }

    private fun updateNotification(text: String, percent: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, notify(text, percent))
    }

    private fun notify(text: String, percent: Int): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            nm.getNotificationChannel(CHANNEL_ID) == null
        ) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID, "Stem separation",
                    NotificationManager.IMPORTANCE_LOW
                ).apply { setShowBadge(false) }
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("QuickPlayer")
            .setContentText("$text $percent%")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, percent, false)
            .build()
    }
}
