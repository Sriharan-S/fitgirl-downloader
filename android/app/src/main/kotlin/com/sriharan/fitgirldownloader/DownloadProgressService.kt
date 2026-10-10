package com.sriharan.fitgirldownloader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the app alive while downloads run and shows one standard progress
 * notification per active game. Dart pushes the current state through
 * [update]; an empty list stops the service.
 */
class DownloadProgressService : Service() {

    data class Item(val id: Int, val title: String, val text: String, val progress: Int)

    companion object {
        private const val CHANNEL_ID = "download_progress"
        private const val BASE_ID = 7000
        private var items: List<Item> = emptyList()
        private var posted: Set<Int> = emptySet()
        private var running = false
        private var instance: DownloadProgressService? = null
        private var foregroundId = 0

        fun update(context: Context, newItems: List<Item>) {
            items = newItems
            if (newItems.isEmpty()) {
                if (running) context.stopService(Intent(context, DownloadProgressService::class.java))
                cancelStale(context, emptySet())
                return
            }
            if (!running) {
                ContextCompat.startForegroundService(
                    context, Intent(context, DownloadProgressService::class.java)
                )
            } else {
                post(context)
            }
        }

        private fun channel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val manager = context.getSystemService(NotificationManager::class.java)
                if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                    manager.createNotificationChannel(
                        NotificationChannel(
                            CHANNEL_ID, "Download progress", NotificationManager.IMPORTANCE_LOW
                        ).apply {
                            description = "Live progress of running downloads"
                            setShowBadge(false)
                        }
                    )
                }
            }
        }

        fun build(context: Context, item: Item): Notification {
            channel(context)
            val open = PendingIntent.getActivity(
                context, 0,
                context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(item.title)
                .setContentText(item.text)
                .setProgress(100, item.progress.coerceIn(0, 100), item.progress < 0)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setContentIntent(open)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .build()
        }

        private fun post(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            // The service's own notification must belong to a game that is
            // still running; move it when that game finishes.
            val first = items.firstOrNull()
            val service = instance
            if (first != null && service != null && foregroundId != BASE_ID + first.id) {
                service.goForeground(first)
            }
            val ids = mutableSetOf<Int>()
            for (item in items) {
                manager.notify(BASE_ID + item.id, build(context, item))
                ids += BASE_ID + item.id
            }
            cancelStale(context, ids)
        }

        private fun cancelStale(context: Context, keep: Set<Int>) {
            val manager = context.getSystemService(NotificationManager::class.java)
            for (id in posted - keep) manager.cancel(id)
            posted = keep
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val first = items.firstOrNull()
        if (first == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        instance = this
        goForeground(first)
        running = true
        post(this)
        return START_NOT_STICKY
    }

    private fun goForeground(item: Item) {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0
        ServiceCompat.startForeground(this, BASE_ID + item.id, build(this, item), type)
        foregroundId = BASE_ID + item.id
    }

    override fun onDestroy() {
        running = false
        instance = null
        foregroundId = 0
        cancelStale(this, emptySet())
        super.onDestroy()
    }
}
