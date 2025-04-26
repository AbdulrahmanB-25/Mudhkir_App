import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
    );
    await setupNotificationChannels();
    await requestPermissions();
  }

  @override
  Future<void> setupNotificationChannels() async {
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
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
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    final dailyChannel = AndroidNotificationChannel(
      'daily_reminders_v2',
      'Daily Reminders',
      description: 'Daily medication reminders',
      importance: Importance.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('medication_alarm'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    final weeklyChannel = AndroidNotificationChannel(
      'weekly_reminders_v2',
      'Weekly Reminders',
      description: 'Weekly medication reminders',
      importance: Importance.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('medication_alarm'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    await androidPlugin.createNotificationChannel(alarmChannel);
    await androidPlugin.createNotificationChannel(dailyChannel);
    await androidPlugin.createNotificationChannel(weeklyChannel);
  }

  @override
  Future<void> requestPermissions() async {
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
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
    final androidDetails = AndroidNotificationDetails(
      'medication_alarms_v2',
      'Medication Alarms',
      channelDescription: 'Critical medication reminders',
      importance: Importance.max,
      priority: Priority.high,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ongoing: false,
      autoCancel: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('medication_alarm'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('TAKE_ACTION', 'Take Now'),
        AndroidNotificationAction('SNOOZE_ACTION', 'Snooze (5 min)'),
      ],
    );
    final details = NotificationDetails(android: androidDetails, iOS: null);
    final tz.TZDateTime tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime effectiveTime = tzTime;
    if (repeatInterval != null && tzTime.isBefore(now)) {
      effectiveTime = _adjustTimeForRepeat(now, scheduledTime, repeatInterval);
    } else if (repeatInterval == null && tzTime.isBefore(now)) {
      return;
    }
    DateTimeComponents? match;
    if (repeatInterval == RepeatInterval.daily) {
      match = DateTimeComponents.time;
    } else if (repeatInterval == RepeatInterval.weekly) {
      match = DateTimeComponents.dayOfWeekAndTime;
    }
    await _notificationsPlugin.cancel(id);
    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      effectiveTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: medicationId,
      matchDateTimeComponents: match,
    );
  }

  tz.TZDateTime _adjustTimeForRepeat(
      tz.TZDateTime now,
      DateTime scheduledTime,
      RepeatInterval repeatInterval
      ) {
    final tod = TimeOfDay.fromDateTime(scheduledTime);
    if (repeatInterval == RepeatInterval.daily) {
      return _nextInstanceOfTime(now.toLocal(), tod);
    } else {
      return _nextInstanceOfWeekday(now.toLocal(), scheduledTime.weekday, tod);
    }
  }

  tz.TZDateTime _nextInstanceOfTime(DateTime from, TimeOfDay tod) {
    final tz.TZDateTime base = tz.TZDateTime.from(from, tz.local);
    tz.TZDateTime sched = tz.TZDateTime(tz.local, base.year, base.month, base.day, tod.hour, tod.minute);
    if (!sched.isAfter(base)) {
      sched = sched.add(const Duration(days: 1));
    }
    return sched;
  }

  tz.TZDateTime _nextInstanceOfWeekday(DateTime from, int weekday, TimeOfDay tod) {
    tz.TZDateTime sched = _nextInstanceOfTime(from, tod);
    while (sched.weekday != weekday) {
      sched = sched.add(const Duration(days: 1));
    }
    return sched;
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
    return await _notificationsPlugin.pendingNotificationRequests();
  }

  @override
  Future<bool?> checkNotificationPermissions() async {
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await androidPlugin?.areNotificationsEnabled();
  }
}
