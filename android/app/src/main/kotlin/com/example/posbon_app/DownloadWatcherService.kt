package com.example.posbon_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.FileObserver
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.io.File

/**
 * Foreground service that watches the public Downloads folder and posts a high-priority
 * alert whenever a new APK lands. Tapping the alert opens MainActivity with the apk path,
 * which triggers the existing local permission-only scan flow.
 */
class DownloadWatcherService : Service() {

    private val watchedFolders = mutableListOf<File>()
    private val observers = mutableListOf<FileObserver>()
    private var mediaStoreObserver: ContentObserver? = null
    private val seenApkPaths = mutableSetOf<String>()
    private val handler = Handler(Looper.getMainLooper())
    private val pendingFiles = mutableMapOf<String, Long>()
    private val debounceMs = 600L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            shutdown()
            return START_NOT_STICKY
        }

        startForegroundCompat()
        if (observers.isEmpty()) {
            seedKnownPaths()
            startObservers()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startMediaStoreObserver()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        observers.forEach { it.stopWatching() }
        observers.clear()
        watchedFolders.clear()
        mediaStoreObserver?.let { contentResolver.unregisterContentObserver(it) }
        mediaStoreObserver = null
        super.onDestroy()
    }

    private fun shutdown() {
        observers.forEach { it.stopWatching() }
        observers.clear()
        watchedFolders.clear()
        mediaStoreObserver?.let { contentResolver.unregisterContentObserver(it) }
        mediaStoreObserver = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun startForegroundCompat() {
        val notification = buildOngoingNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIF_ID_ONGOING,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIF_ID_ONGOING, notification)
        }
    }

    private fun buildOngoingNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_DESTINATION, "files")
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            REQ_OPEN_FILES,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val stopIntent = Intent(this, DownloadWatcherService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            REQ_STOP,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = readPref(KEY_ONGOING_TITLE) ?: "POSBON himoya rejimida"
        val body = readPref(KEY_ONGOING_BODY)
            ?: "Yangi APK fayllari yuklansa avtomatik tekshiriladi"
        val stopLabel = readPref(KEY_STOP_ACTION) ?: "To'xtatish"

        return NotificationCompat.Builder(this, CHANNEL_ID_ONGOING)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(pendingIntent)
            .addAction(0, stopLabel, stopPending)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun seedKnownPaths() {
        candidateFolders().forEach { folder ->
            try {
                folder.listFiles()?.forEach { file ->
                    if (file.isFile && isWatchedExtension(file.name)) {
                        seenApkPaths.add(file.absolutePath)
                    }
                }
            } catch (_: SecurityException) {
            } catch (_: Exception) {
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            seedFromMediaStore()
        }
    }

    private fun seedFromMediaStore() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val projection = arrayOf(MediaStore.Downloads.DATA)
        try {
            contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                null,
            )?.use { cursor ->
                val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DATA)
                while (cursor.moveToNext()) {
                    val path = cursor.getString(dataCol) ?: continue
                    if (isWatchedExtension(path)) seenApkPaths.add(path)
                }
            }
        } catch (_: Exception) {
        }
        Log.d(TAG, "seedFromMediaStore tugadi | jami ko'rilgan: ${seenApkPaths.size} ta fayl")
    }

    private fun startObservers() {
        candidateFolders().forEach { folder ->
            val path = folder.absolutePath
            val observer: FileObserver = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                object : FileObserver(folder, EVENTS) {
                    override fun onEvent(event: Int, name: String?) {
                        handleEvent(event, name, path)
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                object : FileObserver(path, EVENTS) {
                    override fun onEvent(event: Int, name: String?) {
                        handleEvent(event, name, path)
                    }
                }
            }
            try {
                observer.startWatching()
                observers.add(observer)
                watchedFolders.add(folder)
            } catch (e: Exception) {
                Log.w(TAG, "Observer start failed for $path: ${e.message}")
            }
        }
    }

    private fun startMediaStoreObserver() {
        val observer = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                Log.d(TAG, "MediaStore.Downloads o'zgardi | uri: $uri")
                checkMediaStoreForNewFiles()
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            contentResolver.registerContentObserver(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                true,
                observer,
            )
        }
        mediaStoreObserver = observer
        Log.i(TAG, "ContentObserver boshlandi (Android 10+)")
    }

    private fun checkMediaStoreForNewFiles() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val projection = arrayOf(
            MediaStore.Downloads.DISPLAY_NAME,
            MediaStore.Downloads.DATA,
            MediaStore.Downloads.SIZE,
        )
        try {
            contentResolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                projection,
                null,
                null,
                "${MediaStore.Downloads.DATE_ADDED} DESC",
            )?.use { cursor ->
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME)
                val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DATA)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Downloads.SIZE)
                while (cursor.moveToNext()) {
                    val name = cursor.getString(nameCol) ?: continue
                    val path = cursor.getString(dataCol) ?: continue
                    val size = cursor.getLong(sizeCol)
                    if (!isWatchedExtension(name)) continue
                    if (seenApkPaths.contains(path)) continue
                    if (size <= 0) continue
                    Log.d(TAG, "MediaStore: yangi fayl topildi | $name | $path | $size bayt")
                    val file = File(path)
                    if (!file.exists() || !file.canRead()) continue
                    val now = System.currentTimeMillis()
                    pendingFiles[path] = now
                    handler.postDelayed({ flushPending(path) }, debounceMs)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "MediaStore so'rovida xato: ${e.message}")
        }
    }

    private fun handleEvent(event: Int, name: String?, parentPath: String) {
        if (name.isNullOrBlank()) return
        if (!isWatchedExtension(name)) return
        val masked = event and FileObserver.ALL_EVENTS

        // We want to react only after the file is fully written/visible.
        val interesting = (masked and (
            FileObserver.CLOSE_WRITE or
                FileObserver.MOVED_TO or
                FileObserver.CREATE
            )) != 0
        if (!interesting) return

        val fullPath = File(parentPath, name).absolutePath
        Log.d(TAG, "FileObserver hodisa ushlandi | fayl: $name | papka: $parentPath | event: $masked")

        if (seenApkPaths.contains(fullPath)) {
            Log.d(TAG, "Fayl allaqachon ko'rilgan, o'tkazib yuborildi: $fullPath")
            return
        }

        val now = System.currentTimeMillis()
        pendingFiles[fullPath] = now
        handler.postDelayed({ flushPending(fullPath) }, debounceMs)
    }

    private fun flushPending(path: String) {
        val scheduledAt = pendingFiles[path] ?: return
        val elapsed = System.currentTimeMillis() - scheduledAt
        if (elapsed < debounceMs - 50) return
        pendingFiles.remove(path)

        val file = File(path)
        if (!file.exists() || !file.canRead() || file.length() <= 0) {
            Log.w(TAG, "Fayl mavjud emas yoki o'qib bo'lmaydi: $path")
            return
        }
        if (!seenApkPaths.add(path)) return

        Log.i(TAG, "Yangi fayl tasdiqlandi | yo'l: $path | hajm: ${file.length()} bayt | tur: ${file.extension}")
        notifyNewApk(file)
    }

    private fun notifyNewApk(file: File) {
        Log.i(TAG, "Notification yuborilmoqda | fayl: ${file.name} | to'liq yo'l: ${file.absolutePath}")
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_INCOMING_FILE_PATH, file.absolutePath)
            putExtra(EXTRA_DESTINATION, "incoming_scan")
        }
        val pending = PendingIntent.getActivity(
            this,
            (System.currentTimeMillis() and 0xFFFFFF).toInt(),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val isApkFile = file.name.lowercase().endsWith(".apk")
        val title = readPref(KEY_ALERT_TITLE)
            ?: if (isApkFile) "Yangi APK aniqlandi" else "Yangi fayl yuklandi"
        val template = readPref(KEY_ALERT_BODY)
            ?: "{name} yuklandi. Tekshirish uchun bosing."
        val body = template.replace("{name}", file.name)

        val notif = NotificationCompat.Builder(this, CHANNEL_ID_ALERTS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        try {
            NotificationManagerCompat.from(this)
                .notify((file.absolutePath.hashCode() and 0x7FFFFFFF), notif)
        } catch (_: SecurityException) {
        }
    }

    private fun candidateFolders(): List<File> {
        val seen = mutableSetOf<String>()
        val result = mutableListOf<File>()

        fun add(file: File?) {
            file ?: return
            if (!file.exists() || !file.isDirectory) return
            val abs = file.absolutePath
            if (seen.add(abs)) result.add(file)
        }

        add(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS))
        add(File("/storage/emulated/0/Download"))
        add(File("/storage/emulated/0/Downloads"))
        add(File("/sdcard/Download"))
        add(File("/sdcard/Downloads"))
        return result
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return

        val ongoing = NotificationChannel(
            CHANNEL_ID_ONGOING,
            "POSBON Watcher",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Background download monitoring"
            setShowBadge(false)
        }
        nm.createNotificationChannel(ongoing)

        val alerts = NotificationChannel(
            CHANNEL_ID_ALERTS,
            "POSBON APK Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "New APK download alerts"
        }
        nm.createNotificationChannel(alerts)
    }

    private fun isWatchedExtension(name: String): Boolean {
        val lower = name.lowercase()
        return WATCHED_EXTENSIONS.any { lower.endsWith(it) }
    }

    private fun isApk(file: File): Boolean =
        file.isFile && file.name.lowercase().endsWith(".apk")

    private fun prefs(): SharedPreferences =
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun readPref(key: String): String? {
        val value = prefs().getString(key, null)
        return if (value.isNullOrBlank()) null else value
    }

    companion object {
        private const val TAG = "PosbonWatcher"

        const val ACTION_STOP = "uz.posbon.action.STOP_WATCHER"
        const val EXTRA_INCOMING_FILE_PATH = "incomingFilePath"
        const val EXTRA_DESTINATION = "destination"

        const val CHANNEL_ID_ONGOING = "posbon_watcher_ongoing"
        const val CHANNEL_ID_ALERTS = "posbon_watcher_alerts"

        const val PREFS_NAME = "posbon_watcher_prefs"
        const val KEY_ONGOING_TITLE = "ongoing_title"
        const val KEY_ONGOING_BODY = "ongoing_body"
        const val KEY_ALERT_TITLE = "alert_title"
        const val KEY_ALERT_BODY = "alert_body"
        const val KEY_STOP_ACTION = "stop_action"

        private const val NOTIF_ID_ONGOING = 4711
        private const val REQ_OPEN_FILES = 1100
        private const val REQ_STOP = 1101

        private const val EVENTS =
            FileObserver.CLOSE_WRITE or FileObserver.MOVED_TO or FileObserver.CREATE

        val WATCHED_EXTENSIONS = setOf(".apk", ".zip", ".pdf", ".exe", ".dex", ".xapk")

        fun start(context: Context) {
            val intent = Intent(context, DownloadWatcherService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, DownloadWatcherService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.startService(intent)
            } catch (_: Exception) {
                context.stopService(Intent(context, DownloadWatcherService::class.java))
            }
        }
    }
}
