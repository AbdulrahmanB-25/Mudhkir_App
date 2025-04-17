import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static const MethodChannel _channel = MethodChannel('com.example.mudhkir_app/notifications');
  static final NotificationService _instance = NotificationService._internal();
  
  factory NotificationService() => _instance;
  
  NotificationService._internal();
  
  // Method to get notification data from platform code if app was opened by a notification
  Future<Map<String, dynamic>?> getInitialNotificationData() async {
    try {
      if (!kIsWeb) {
        final result = await _channel.invokeMethod<Map<Object?, Object?>>('getNotificationData');
        if (result != null) {
          return {
            'id': result['id'] as int,
            'payload': result['payload'] as String,
          };
        }
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('[NotificationService] Error getting notification data: ${e.message}');
      return null;
    }
  }
  
  // Helper method to store notification redirection data
  static Future<void> storeRedirectData(String medicationId) async {
    if (medicationId.isEmpty) {
      debugPrint('[NotificationService] Empty medicationId, not storing redirect data');
      return;
    }
    
    try {
      // Platform channel for Android
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('trackNotificationDisplay', {
          'payload': medicationId,
        });
      }
      
      // Also store in SharedPreferences as a backup and for iOS
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_notification_docId', medicationId);
      await prefs.setInt('notification_timestamp', DateTime.now().millisecondsSinceEpoch);
      
      debugPrint('[NotificationService] Stored redirect data for medicationId: $medicationId');
    } catch (e) {
      debugPrint('[NotificationService] Error storing redirect data: $e');
    }
  }
  
  // Helper method to check if redirection is needed
  static Future<Map<String, dynamic>?> checkRedirect() async {
    final prefs = await SharedPreferences.getInstance();
    final medicationId = prefs.getString('pending_notification_docId');
    final timestamp = prefs.getInt('notification_timestamp');
    
    // No redirect data found
    if (medicationId == null || medicationId.isEmpty || timestamp == null) {
      debugPrint('[NotificationService] No redirect data found');
      return null;
    }
    
    // Check if timestamp is within valid window (45 minutes)
    final notificationTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(notificationTime);
    
    if (difference.inMinutes > 45) {
      // Expired - clear the data
      await clearRedirectData();
      debugPrint('[NotificationService] Redirect data expired (${difference.inMinutes} minutes old)');
      return null;
    }
    
    // Valid redirection data
    debugPrint('[NotificationService] Found valid redirect data: $medicationId');
    return {
      'docId': medicationId,
      'timestamp': notificationTime,
    };
  }
  
  // Helper method to clear notification redirection data
  static Future<void> clearRedirectData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_notification_docId');
      await prefs.remove('notification_timestamp');
      
      // Also clear via platform channel on Android
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('clearNotificationRedirect');
      }
      
      debugPrint('[NotificationService] Cleared redirect data');
    } catch (e) {
      debugPrint('[NotificationService] Error clearing redirect data: $e');
    }
  }

  Future<void> trackNotificationEvent(String eventType, String payload) async {
    try {
      if (!kIsWeb) {
        await _channel.invokeMethod('trackNotificationEvent', {
          'eventType': eventType,
          'payload': payload,
        });
        debugPrint('[NotificationService] Tracked event: $eventType, Payload: $payload');
      }
    } catch (e) {
      debugPrint('[NotificationService] Error tracking notification event: $e');
    }
  }
}

