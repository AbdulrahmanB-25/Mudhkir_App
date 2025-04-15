package com.example.mudhkir_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Bundle
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import java.util.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.mudhkir_app/notifications"
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                        result.success(null)
                    }
                }
                "trackNotificationDisplay" -> {
                    try {
                        val payload = call.argument<String>("payload")
                        if (!payload.isNullOrEmpty()) {
                            trackNotificationDisplayed(payload)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("TRACKING_ERROR", "Error tracking notification: ${e.message}", null)
                    }
                }
                "clearNotificationRedirect" -> {
                    try {
                        val prefs = applicationContext.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
                        val editor = prefs.edit()
                        editor.remove("pending_notification_docId")
                        editor.remove("notification_timestamp")
                        editor.apply()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLEAR_ERROR", "Error clearing notification data: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    // Track when a notification is displayed
    private fun trackNotificationDisplayed(payload: String) {
        Log.d("MainActivity", "Tracking notification payload: $payload")
        val prefs = applicationContext.getSharedPreferences("notification_prefs", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        editor.putString("pending_notification_docId", payload)
        editor.putLong("notification_timestamp", System.currentTimeMillis())
        editor.apply()
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Check if launched by notification
        if (intent.hasExtra("notification_payload")) {
            val payload = intent.getStringExtra("notification_payload")
            Log.d("MainActivity", "App launched with notification payload: $payload")
            payload?.let { trackNotificationDisplayed(it) }
        }
    }
    
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        
        // Check if activity was started from notification
        if (intent.hasExtra("notification_payload")) {
            val payload = intent.getStringExtra("notification_payload")
            Log.d("MainActivity", "onNewIntent with notification payload: $payload")
            payload?.let { trackNotificationDisplayed(it) }
        }
    }
}
