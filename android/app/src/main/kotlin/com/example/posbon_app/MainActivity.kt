package com.example.posbon_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "uz.posbon/native_packages"
    private val notificationChannelId = "posbon_scan_results"
    private var pendingOpenFilePath: String? = null
    private var pendingDestination: String? = null
    private var methodChannel: MethodChannel? = null
    private var authResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingOpenFilePath = resolveIncomingFile(intent) ?: pendingOpenFilePath
        pendingDestination = resolveDestination(intent) ?: pendingDestination
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingOpenFilePath = resolveIncomingFile(intent) ?: pendingOpenFilePath
        pendingDestination = resolveDestination(intent) ?: pendingDestination
        dispatchIncomingFileIfPossible()
        dispatchDestinationIfPossible()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPackageInfo" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.error("invalid_args", "packageName is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val appInfo = packageManager.getApplicationInfo(packageName, 0)
                        result.success(
                            mapOf(
                                "packageName" to packageName,
                                "apkPath" to appInfo.sourceDir,
                            ),
                        )
                    } catch (e: PackageManager.NameNotFoundException) {
                        result.success(
                            mapOf(
                                "packageName" to packageName,
                                "apkPath" to null,
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("package_lookup_failed", e.message, null)
                    }
                }

                "getRequestedPermissions" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.success(emptyList<String>())
                        return@setMethodCallHandler
                    }

                    try {
                        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(
                                packageName,
                                PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()),
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
                        }
                        result.success(packageInfo.requestedPermissions?.toList() ?: emptyList<String>())
                    } catch (_: PackageManager.NameNotFoundException) {
                        result.success(emptyList<String>())
                    } catch (e: Exception) {
                        result.error("permissions_lookup_failed", e.message, null)
                    }
                }

                "getDeviceInfo" -> {
                    val downloadDir = Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_DOWNLOADS,
                    )
                    result.success(
                        mapOf(
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "downloadsPath" to downloadDir?.absolutePath,
                        ),
                    )
                }

                "consumePendingOpenFile" -> {
                    val path = pendingOpenFilePath
                    pendingOpenFilePath = null
                    result.success(path)
                }

                "consumePendingDestination" -> {
                    val destination = pendingDestination
                    pendingDestination = null
                    result.success(destination)
                }

                "openUninstallScreen" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    try {
                        val uninstallIntent = Intent(
                            Intent.ACTION_UNINSTALL_PACKAGE,
                            Uri.parse("package:$packageName"),
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            putExtra(Intent.EXTRA_RETURN_RESULT, true)
                        }
                        if (uninstallIntent.resolveActivity(packageManager) == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        startActivity(uninstallIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("uninstall_failed", e.message, null)
                    }
                }

                "openAppSettings" -> {
                    val packageName = call.argument<String>("packageName")
                    if (packageName.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    try {
                        val settingsIntent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        if (settingsIntent.resolveActivity(packageManager) == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        startActivity(settingsIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("app_settings_failed", e.message, null)
                    }
                }

                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "POSBON"
                    val body = call.argument<String>("body") ?: ""
                    result.success(showNotification(title, body))
                }

                "canAuthenticateDevice" -> {
                    result.success(canAuthenticateDevice())
                }

                "authenticateDevice" -> {
                    val reason = call.argument<String>("reason") ?: "Qurilma himoyasi bilan tasdiqlang"
                    authenticateDevice(reason, result)
                }

                else -> result.notImplemented()
            }
        }

        dispatchIncomingFileIfPossible()
        dispatchDestinationIfPossible()
    }

    private fun dispatchIncomingFileIfPossible() {
        val path = pendingOpenFilePath ?: return
        methodChannel?.invokeMethod(
            "incomingFileReady",
            mapOf("path" to path),
        )
    }

    private fun dispatchDestinationIfPossible() {
        val destination = pendingDestination ?: return
        methodChannel?.invokeMethod(
            "destinationReady",
            mapOf("destination" to destination),
        )
    }

    private fun resolveIncomingFile(intent: Intent?): String? {
        if (intent == null) return null

        val directUri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
                }
            }

            else -> null
        }

        return directUri?.let(::cacheIncomingUri)
    }

    private fun resolveDestination(intent: Intent?): String? {
        return intent?.getStringExtra("destination")
    }

    private fun cacheIncomingUri(uri: Uri): String? {
        if (uri.scheme == "file") {
            return uri.path
        }

        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val incomingDir = File(cacheDir, "incoming").apply { mkdirs() }
            val fileName = queryDisplayName(uri) ?: "shared_${System.currentTimeMillis()}"
            val safeName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val targetFile = File(incomingDir, safeName)

            inputStream.use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }

            targetFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME)
        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                return cursor.getString(nameIndex)
            }
        }

        return uri.lastPathSegment?.substringAfterLast('/')
    }

    private fun canAuthenticateDevice(): Boolean {
        val authenticators =
            BiometricManager.Authenticators.BIOMETRIC_WEAK or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        return BiometricManager.from(this).canAuthenticate(authenticators) ==
            BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun authenticateDevice(reason: String, result: MethodChannel.Result) {
        if (!canAuthenticateDevice()) {
            result.success(false)
            return
        }

        if (authResult != null) {
            result.error("auth_in_progress", "Authentication is already in progress", null)
            return
        }

        authResult = result
        val executor = ContextCompat.getMainExecutor(this)
        val prompt = BiometricPrompt(
            this,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    authResultValue: BiometricPrompt.AuthenticationResult,
                ) {
                    authResult?.success(true)
                    authResult = null
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    authResult?.success(false)
                    authResult = null
                }

                override fun onAuthenticationFailed() {
                    // User can retry without closing the prompt.
                }
            },
        )

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Posbon Safe")
            .setSubtitle(reason)
            .setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
            .build()

        try {
            prompt.authenticate(promptInfo)
        } catch (error: Exception) {
            authResult?.error("auth_failed", error.message, null)
            authResult = null
        }
    }

    private fun showNotification(title: String, body: String): Boolean {
        return try {
            createNotificationChannel()

            val launchIntent = (
                packageManager.getLaunchIntentForPackage(packageName)
                    ?: Intent(this, MainActivity::class.java)
                ).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("destination", "results")
            }

            val pendingIntent = PendingIntent.getActivity(
                this,
                1001,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val builder = NotificationCompat.Builder(this, notificationChannelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)

            NotificationManagerCompat.from(this)
                .notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), builder.build())
            true
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            notificationChannelId,
            "POSBON Scan Results",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Skan yakunlari haqida xabar beradi"
        }
        manager.createNotificationChannel(channel)
    }
}
