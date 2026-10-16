package com.budget.planning

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.provider.Settings
import android.util.Log

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.budget.planning/notifications"
    private var methodChannel: MethodChannel? = null

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BankNotificationListenerService.ACTION_NOTIFICATION_RECEIVED) {
                val title = intent.getStringExtra(BankNotificationListenerService.EXTRA_TITLE) ?: ""
                val text = intent.getStringExtra(BankNotificationListenerService.EXTRA_TEXT) ?: ""
                val packageName = intent.getStringExtra(BankNotificationListenerService.EXTRA_PACKAGE) ?: ""
                val timestamp = intent.getLongExtra(BankNotificationListenerService.EXTRA_TIMESTAMP, System.currentTimeMillis())

                val data = mapOf(
                    "title" to title,
                    "text" to text,
                    "packageName" to packageName,
                    "timestamp" to timestamp
                )

                Log.d("MainActivity", "Forwarding notification to Flutter: $data")
                methodChannel?.invokeMethod("onNotificationReceived", data)
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("MainActivity", "configureFlutterEngine called")
        
        createNotificationChannel()
        rebindNotificationListenerService()

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            Log.d("MainActivity", "MethodCallHandler: method=${call.method}")
            when (call.method) {
                "showNotification" -> {
                    val title = call.argument<String>("title") ?: "Alert"
                    val body = call.argument<String>("body") ?: ""
                    showNotification(title, body)
                    result.success(true)
                }
                "checkNotificationListenerPermission" -> {
                    val isGranted = isNotificationListenerPermissionGranted()
                    result.success(isGranted)
                }
                "requestNotificationListenerPermission" -> {
                    openNotificationListenerSettings()
                    result.success(true)
                }
                "openAutostartSettings" -> {
                    openAutostartSettings()
                    result.success(true)
                }
                "rebindNotificationListener" -> {
                    rebindNotificationListenerService()
                    result.success(true)
                }
                "checkListenerStatus" -> {
                    val isGranted = isNotificationListenerPermissionGranted()
                    val isConnected = BankNotificationListenerService.isConnected
                    if (isGranted && !isConnected) {
                        rebindNotificationListenerService()
                    }
                    BankNotificationListenerService.instance?.scanActiveNotifications()
                    val status = mapOf(
                        "isGranted" to isGranted,
                        "isConnected" to isConnected
                    )
                    result.success(status)
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val success = installApk(filePath)
                        result.success(success)
                    } else {
                        result.error("INVALID_PATH", "File path is null", null)
                    }
                }
                "openPlayProtectSettings" -> {
                    openPlayProtectSettings()
                    result.success(true)
                }
                "canRequestPackageInstalls" -> {
                    val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        packageManager.canRequestPackageInstalls()
                    } else {
                        true
                    }
                    result.success(canInstall)
                }
                "openUnknownAppSourcesSettings" -> {
                    openUnknownAppSourcesSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        val filter = IntentFilter(BankNotificationListenerService.ACTION_NOTIFICATION_RECEIVED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(notificationReceiver, filter, RECEIVER_EXPORTED)
        } else {
            registerReceiver(notificationReceiver, filter)
        }
    }

    override fun onResume() {
        super.onResume()
        rebindNotificationListenerService()
        BankNotificationListenerService.instance?.scanActiveNotifications()
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(notificationReceiver)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error unregistering receiver", e)
        }
    }

    private fun rebindNotificationListenerService() {
        if (isNotificationListenerPermissionGranted()) {
            try {
                val componentName = android.content.ComponentName(this, BankNotificationListenerService::class.java)
                val pm = packageManager
                pm.setComponentEnabledSetting(
                    componentName,
                    android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    android.content.pm.PackageManager.DONT_KILL_APP
                )
                pm.setComponentEnabledSetting(
                    componentName,
                    android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    android.content.pm.PackageManager.DONT_KILL_APP
                )

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    android.service.notification.NotificationListenerService.requestRebind(componentName)
                }
                BankNotificationListenerService.instance?.scanActiveNotifications()
                Log.d("MainActivity", "Successfully toggled and requested rebind for BankNotificationListenerService")
            } catch (e: Exception) {
                Log.e("MainActivity", "Error requesting rebind for BankNotificationListenerService", e)
            }
        }
    }

    private fun isNotificationListenerPermissionGranted(): Boolean {
        val packageName = packageName
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat != null && flat.contains(packageName)
    }

    private fun openNotificationListenerSettings() {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            Log.e("MainActivity", "Could not open Notification Listener settings", e)
        }
    }

    private fun openAutostartSettings() {
        try {
            val intent = Intent()
            val manufacturer = Build.MANUFACTURER.lowercase()
            when {
                manufacturer.contains("xiaomi") || manufacturer.contains("redmi") || manufacturer.contains("poco") -> {
                    intent.component = android.content.ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")
                }
                manufacturer.contains("oppo") -> {
                    intent.component = android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")
                }
                manufacturer.contains("vivo") -> {
                    intent.component = android.content.ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")
                }
                manufacturer.contains("realme") -> {
                    intent.component = android.content.ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")
                }
                else -> {
                    intent.action = Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                }
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
            } catch (_: Exception) {}
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Boundary Alerts"
            val descriptionText = "Notifications for credit card boundary limits reached"
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel("boundary_alerts", name, importance).apply {
                description = descriptionText
            }
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d("MainActivity", "Notification Channel created")
        }
    }

    private fun showNotification(title: String, body: String) {
        Log.d("MainActivity", "showNotification: title=$title, body=$body")
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                Log.w("MainActivity", "POST_NOTIFICATIONS permission not granted. Requesting...")
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }

        createNotificationChannel()
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, "boundary_alerts")
        } else {
            Notification.Builder(this)
        }
        
        builder.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setPriority(Notification.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL)
            .setAutoCancel(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setCategory(Notification.CATEGORY_STATUS)
        }

        try {
            val notificationId = (System.currentTimeMillis() % 100000).toInt()
            notificationManager.notify(notificationId, builder.build())
            Log.d("MainActivity", "Notification posted successfully: id=$notificationId")
        } catch (e: Exception) {
            Log.e("MainActivity", "Error posting notification", e)
        }
    }

    private fun installApk(filePath: String): Boolean {
        Log.d("MainActivity", "installApk: filePath=$filePath")
        return try {
            val file = java.io.File(filePath)
            if (!file.exists()) {
                Log.e("MainActivity", "APK file does not exist at $filePath")
                return false
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (!packageManager.canRequestPackageInstalls()) {
                    Log.w("MainActivity", "Install unknown apps permission not granted. Opening settings.")
                    openUnknownAppSourcesSettings()
                    return false
                }
            }

            file.setReadable(true, false)

            val uri: android.net.Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                androidx.core.content.FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    file
                )
            } else {
                android.net.Uri.fromFile(file)
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addCategory(Intent.CATEGORY_DEFAULT)
            }

            val resolveInfoList = packageManager.queryIntentActivities(intent, android.content.pm.PackageManager.MATCH_DEFAULT_ONLY)
            for (resolveInfo in resolveInfoList) {
                val packageName = resolveInfo.activityInfo.packageName
                grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }

            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Error installing APK: ${e.message}", e)
            false
        }
    }

    private fun openPlayProtectSettings() {
        Log.d("MainActivity", "openPlayProtectSettings called")
        try {
            val intent = Intent().apply {
                setClassName("com.android.vending", "com.google.android.finsky.protect.PlayProtectSettingsActivity")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            try {
                val playStoreIntent = Intent(Intent.ACTION_VIEW).apply {
                    data = android.net.Uri.parse("https://play.google.com/store/apps")
                    setPackage("com.android.vending")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(playStoreIntent)
            } catch (e2: Exception) {
                try {
                    startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                } catch (e3: Exception) {
                    Log.e("MainActivity", "Unable to open security settings: ${e3.message}", e3)
                }
            }
        }
    }

    private fun openUnknownAppSourcesSettings() {
        Log.d("MainActivity", "openUnknownAppSourcesSettings called")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = android.net.Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } catch (e: Exception) {
                Log.e("MainActivity", "Error opening unknown app sources: ${e.message}", e)
                try {
                    startActivity(Intent(Settings.ACTION_MANAGE_ALL_APPLICATIONS_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                } catch (e2: Exception) {
                    Log.e("MainActivity", "Fallback settings error: ${e2.message}", e2)
                }
            }
        }
    }
}
