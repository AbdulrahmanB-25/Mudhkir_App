import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show Platform;

import 'android_notification_service.dart';
import 'ios_notification_service.dart';

/// Abstract class defining the interface for platform-specific notification services.
/// Handles scheduling, managing, and interacting with notifications.
abstract class NotificationService {
  /// Factory constructor that returns the appropriate platform-specific implementation
  factory NotificationService() {
    if (Platform.isAndroid) {
      return AndroidNotificationService();
    } else if (Platform.isIOS) {
      return IOSNotificationService();
    }
    throw UnsupportedError('Unsupported platform for notifications');
  }

  /// Access to the underlying notification plugin
  FlutterLocalNotificationsPlugin get notificationsPlugin;

  /// Initialize the notification service with callbacks for handling interactions
  Future<void> initialize(
      BuildContext context,
      void Function(NotificationResponse) onNotificationResponse,
      void Function(NotificationResponse)? onBackgroundNotificationResponse
      );

  /// Set up any platform-specific notification channels or categories
  Future<void> setupNotificationChannels();

  /// Request necessary permissions from the user to show notifications
  Future<void> requestPermissions();

  /// Schedule a medication alarm notification with specific parameters
  Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
    required String medicationId,
    bool isSnoozed = false,
    required bool isCompanionCheck,
    RepeatInterval? repeatInterval,
  });

  /// Cancel a specific notification by ID
  Future<void> cancelNotification(int id);

  /// Cancel all pending notifications
  Future<void> cancelAllNotifications();

  /// Get a list of all currently pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications();

  /// Check if notification permissions are granted
  Future<bool?> checkNotificationPermissions();
}
