import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:io' show Platform;

import 'android_notification_service.dart';
import 'ios_notification_service.dart';

abstract class NotificationService {
  factory NotificationService() {
    if (Platform.isAndroid) {
      return AndroidNotificationService();
    } else if (Platform.isIOS) {
      return IOSNotificationService();
    }
    throw UnsupportedError('Unsupported platform for notifications');
  }

  FlutterLocalNotificationsPlugin get notificationsPlugin;

  Future<void> initialize(BuildContext context,
      void Function(NotificationResponse) onNotificationResponse,
      void Function(NotificationResponse)? onBackgroundNotificationResponse);
  Future<void> setupNotificationChannels();
  Future<void> requestPermissions();

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

  Future<void> cancelNotification(int id);
  Future<void> cancelAllNotifications();
  Future<List<PendingNotificationRequest>> getPendingNotifications();
  Future<bool?> checkNotificationPermissions();
}