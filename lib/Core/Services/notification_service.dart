import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show Platform;

import 'android_notification_service.dart';
import 'ios_notification_service.dart';

abstract class NotificationService {
  // Factory constructor to get the appropriate platform implementation
  factory NotificationService() {
    if (Platform.isAndroid) {
      return AndroidNotificationService();
    } else if (Platform.isIOS) {
      return IOSNotificationService();
    }
    throw UnsupportedError('Unsupported platform for notifications');
  }
  
  // Get notifications plugin
  FlutterLocalNotificationsPlugin get notificationsPlugin;
  
  // Setup methods
  Future<void> initialize(BuildContext context, 
    void Function(NotificationResponse) onNotificationResponse,
    void Function(NotificationResponse)? onBackgroundNotificationResponse);
  Future<void> setupNotificationChannels();
  Future<void> requestPermissions();
  
  // Notification scheduling
  Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String medicationId,
    bool isSnoozed,
    RepeatInterval? repeatInterval,
  });
  
  // Other notification operations
  Future<void> cancelNotification(int id);
  Future<void> cancelAllNotifications();
  Future<List<PendingNotificationRequest>> getPendingNotifications();
  Future<bool?> checkNotificationPermissions();
}
