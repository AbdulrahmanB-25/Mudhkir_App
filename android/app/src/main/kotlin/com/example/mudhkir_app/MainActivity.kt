package com.example.mudhkir_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Bundle
import android.content.Context
import android.util.Log

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.mudhkir_app/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Create method channel
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Set up method call handler
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getNotificationData" -> {
                        // Get notification data from intent if exists
                        val intent = this.intent
                        val notificationId = intent.getIntExtra("notification_id", -1)
                        val notificationPayload = intent.getStringExtra("notification_payload")

                        if (notificationId != -1 && !notificationPayload.isNullOrEmpty()) {
                            val data = HashMap<String, Any>()
                            data["id"] = notificationId
                            data["payload"] = notificationPayload
                            result.success(data)

                            // Clear the intent data to prevent multiple triggers
                            intent.removeExtra("notification_id")
                            intent.removeExtra("notification_payload")
                        } else {
                            // Check shared preferences as fallback
                            val prefs = applicationContext.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
                            val payload = prefs.getString("pending_notification_docId", null)
                            val timestamp = prefs.getLong("notification_timestamp", 0)

                            if (payload != null && timestamp > 0) {
                                val data = HashMap<String, Any>()
                                data["payload"] = payload
                                result.success(data)
                            } else {
                                result.success(null)
                            }
                        }
                    }
                    "trackNotificationDisplay" -> {
                        val payload = call.argument<String>("payload")
                        if (!payload.isNullOrEmpty()) {
                            // Store notification payload in shared preferences
                            val prefs = applicationContext.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
                            val editor = prefs.edit()
                            editor.putString("pending_notification_docId", payload)
                            editor.putLong("notification_timestamp", System.currentTimeMillis())
                            editor.apply()

                            Log.d("MainActivity", "Tracking notification payload: $payload")
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "clearNotificationRedirect" -> {
                        val prefs = applicationContext.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
                        val editor = prefs.edit()
                        editor.remove("pending_notification_docId")
                        editor.remove("notification_timestamp")
                        editor.apply()
                        result.success(true)
                    }
                    "areExactAlarmsAllowed" -> {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                            val alarmManager = getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
                            result.success(alarmManager.canScheduleExactAlarms())
                        } else {
                            // On older Android versions, exact alarms are allowed by default
                            result.success(true)
                        }
                    }
                    "isBatteryOptimizationIgnored" -> {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                            val powerManager = getSystemService(Context.POWER_SERVICE) as android.os.PowerManager
                            result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            // On older Android versions
                            result.success(true)
                        }
                    }
                    "trackNotificationEvent" -> {
                        val eventType = call.argument<String>("eventType")
                        val payload = call.argument<String>("payload")
                        Log.d("NotificationTracking", "Event: $eventType, Payload: $payload")
                        result.success(true)
                    }
                    else -> {
                        result.notImplemented()
                    }
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "Error handling method call: ${e.message}")
                result.error("ERROR", e.message, null)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Check if launched by notification
        if (intent.hasExtra("notification_payload")) {
            val payload = intent.getStringExtra("notification_payload")
            Log.d("MainActivity", "App launched with notification payload: $payload")
            if (payload != null) {
                val prefs = applicationContext.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
                val editor = prefs.edit()
                editor.putString("pending_notification_docId", payload)
                editor.putLong("notification_timestamp", System.currentTimeMillis())
                editor.apply()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        // Handle notification payload when the app is resumed
        if (intent.hasExtra("notification_payload")) {
            val payload = intent.getStringExtra("notification_payload")
            Log.d("MainActivity", "onNewIntent with notification payload: $payload")
            if (payload != null) {
                val prefs = applicationContext.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
                val editor = prefs.edit()
                editor.putString("pending_notification_docId", payload)
                editor.putLong("notification_timestamp", System.currentTimeMillis())
                editor.apply()
            }
        }
    }
}
