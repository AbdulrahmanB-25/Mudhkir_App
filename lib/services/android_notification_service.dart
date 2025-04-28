import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:timezone/timezone.dart' as tz;
import 'notification_service.dart';

class AndroidNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  FlutterLocalNotificationsPlugin get notificationsPlugin => _notificationsPlugin;

  @override
  Future<void> initialize(
      BuildContext context,
      void Function(NotificationResponse) onNotificationResponse,
      void Function(NotificationResponse)? onBackgroundNotificationResponse
      ) async {
    final androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings = InitializationSettings(android: androidInit, iOS: null);

    try {
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
      );
    } catch (e) {
      print("[AndroidNotificationService] ERROR initializing plugin: $e");
    }

    await setupNotificationChannels();
    await requestPermissions();
  }

  @override
  Future<void> setupNotificationChannels() async {
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) {
      return;
    }

    try {
      final alarmChannel = AndroidNotificationChannel(
        'medication_alarms_v2',
        'Medication Alarms',
        description: 'Critical medication reminders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      );

      await androidPlugin.createNotificationChannel(alarmChannel);

      final companionChannel = AndroidNotificationChannel(
        'companion_medication_alarms',
        'Companion Medication Alarms',
        description: 'Medication reminders for companions',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );

      await androidPlugin.createNotificationChannel(companionChannel);

      final testChannel = AndroidNotificationChannel(
        'test_notifications',
        'Test Notifications',
        description: 'For testing notification delivery',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await androidPlugin.createNotificationChannel(testChannel);

    } catch (e) {
      print("[AndroidNotificationService] ERROR creating notification channels: $e");
    }
  }

  @override
  Future<void> requestPermissions() async {
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      try {
        await androidPlugin.areNotificationsEnabled();
      } catch (e) {
        print("[AndroidNotificationService] ERROR checking notification permissions: $e");
      }
    }
  }

  @override
  Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String medicationId,
    bool isSnoozed = false,
    RepeatInterval? repeatInterval,
  }) async {
    final bool isTestNotification = title.contains("اختبار إشعار");
    final bool isCompanionNotification = title.contains("تذكير جرعة مرافق") ||
        medicationId.startsWith("companion_");

    final String channelId = isTestNotification
        ? 'test_notifications'
        : (isCompanionNotification ? 'companion_medication_alarms' : 'medication_alarms_v2');

    final String channelName = isTestNotification
        ? 'Test Notifications'
        : (isCompanionNotification ? 'Companion Medication Alarms' : 'Medication Alarms');

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Medication reminder notifications',
      importance: Importance.max,
      priority: Priority.high,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      // category: AndroidNotificationCategory.alarm, // Removed for potentially better audio handling
      // fullScreenIntent: true, // Removed for potentially better audio handling
      ongoing: false,
      autoCancel: true,
      playSound: true,
      sound: isTestNotification ? null : RawResourceAndroidNotificationSound('medication_alarm'),
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      if (tz.local == null) {
        tz_init.initializeTimeZones();
      }

      final tz.TZDateTime tzTime = tz.TZDateTime.from(scheduledTime, tz.local);

      final now = tz.TZDateTime.now(tz.local);
      if (tzTime.isBefore(now)) {
        return;
      }

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: medicationId,
        matchDateTimeComponents: repeatInterval == RepeatInterval.daily
            ? DateTimeComponents.time
            : (repeatInterval == RepeatInterval.weekly ? DateTimeComponents.dayOfWeekAndTime : null),
      );
    } catch (e, stackTrace) {
      print("[AndroidNotificationService] ERROR scheduling notification: $e");
      print("[AndroidNotificationService] Stack trace: $stackTrace");
      throw e;
    }
  }

  @override
  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  @override
  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    final requests = await _notificationsPlugin.pendingNotificationRequests();
    return requests;
  }

  @override
  Future<bool?> checkNotificationPermissions() async {
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      try {
        return await androidPlugin.areNotificationsEnabled();
      } catch (e) {
        print("[AndroidNotificationService] ERROR checking permissions: $e");
      }
    }
    return null;
  }
}