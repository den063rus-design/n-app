package com.napp.app

import android.app.NotificationManager
import android.os.Build
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

                "cancelNotificationsByGroupKey" -> {
                    val groupKey = call.argument<String>("groupKey")
                    val summaryId = call.argument<Int>("summaryId")
                    if (groupKey == null) {
                        result.error("INVALID_ARGS", "groupKey is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val notificationManager =
                            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            for (statusBarNotification in notificationManager.activeNotifications) {
                                val sameGroup = statusBarNotification.notification.group == groupKey
                                val sameSummaryId = summaryId != null && statusBarNotification.id == summaryId
                                if (sameGroup || sameSummaryId) {
                                    notificationManager.cancel(
                                        statusBarNotification.tag,
                                        statusBarNotification.id
                                    )
                                }
                            }
                        } else if (summaryId != null) {
                            notificationManager.cancel(summaryId)
                        }

                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CANCEL_GROUP_FAILED", e.message, null)
                    }
                }

                "getNotificationGroupCount" -> {
                    val groupKey = call.argument<String>("groupKey")
                    if (groupKey == null) {
                        result.error("INVALID_ARGS", "groupKey is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val notificationManager =
                            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            var count = 0
                            for (statusBarNotification in notificationManager.activeNotifications) {
                                val sameGroup = statusBarNotification.notification.group == groupKey
                                val isSummary = statusBarNotification.notification.flags and android.app.Notification.FLAG_GROUP_SUMMARY != 0
                                if (sameGroup && !isSummary) {
                                    count += 1
                                }
                            }
                            result.success(count)
                        } else {
                            result.success(0)
                        }
                    } catch (e: Exception) {
                        result.error("GROUP_COUNT_FAILED", e.message, null)
                    }
                }

                "cancelNotificationsByTagPrefix" -> {
                    val tagPrefix = call.argument<String>("tagPrefix")
                    val summaryId = call.argument<Int>("summaryId")
                    val summaryTag = call.argument<String>("summaryTag")
                    if (tagPrefix == null) {
                        result.error("INVALID_ARGS", "tagPrefix is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val notificationManager =
                            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            for (statusBarNotification in notificationManager.activeNotifications) {
                                val tag = statusBarNotification.tag ?: ""
                                val matchesPrefix = tag.startsWith(tagPrefix)
                                val matchesSummary = (summaryId != null && statusBarNotification.id == summaryId) ||
                                    (summaryTag != null && tag == summaryTag)
                                if (matchesPrefix || matchesSummary) {
                                    notificationManager.cancel(
                                        statusBarNotification.tag,
                                        statusBarNotification.id
                                    )
                                }
                            }
                        } else if (summaryId != null) {
                            notificationManager.cancel(summaryId)
                        }

                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CANCEL_BY_TAG_PREFIX_FAILED", e.message, null)
                    }
                }

                "getNotificationCountByTagPrefix" -> {
                    val tagPrefix = call.argument<String>("tagPrefix")
                    if (tagPrefix == null) {
                        result.error("INVALID_ARGS", "tagPrefix is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val notificationManager =
                            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            var count = 0
                            for (statusBarNotification in notificationManager.activeNotifications) {
                                val tag = statusBarNotification.tag ?: ""
                                if (tag.startsWith(tagPrefix)) {
                                    count += 1
                                }
                            }
                            result.success(count)
                        } else {
                            result.success(0)
                        }
                    } catch (e: Exception) {
                        result.error("COUNT_BY_TAG_PREFIX_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
