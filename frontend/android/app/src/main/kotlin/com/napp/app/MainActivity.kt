package com.napp.app

import android.app.NotificationManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.napp.app/notifications"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "cancelNotificationById" -> {
                    val id = call.argument<Int>("id")
                    if (id == null) {
                        result.error("INVALID_ARGS", "Notification id is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val notificationManager =
                            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.cancel(id)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CANCEL_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
