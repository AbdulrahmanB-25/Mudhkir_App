import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:timezone/timezone.dart' as tz;
import 'notification_service.dart';

class AndroidNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  tz.Location _riyadhTimezone = tz.getLocation('Asia/Riyadh');
  bool _debugMode = true;
  bool _isInitialized = false;

  AndroidNotificationService() {
    tz_init.initializeTimeZones();
    _riyadhTimezone = tz.getLocation('Asia/Riyadh');
    tz.setLocalLocation(_riyadhTimezone);
  }

  @override
  FlutterLocalNotificationsPlugin get notificationsPlugin => _notificationsPlugin;

  @override
  Future<void> initialize(
      BuildContext context,
      void Function(NotificationResponse) onNotificationResponse,
      void Function(NotificationResponse)? onBackgroundNotificationResponse
      ) async {
    // Initializes the notification service and sets up channels
    if (_isInitialized) return;
    var androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    var initSettings = InitializationSettings(android: androidInit);
    await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse
    );
    await setupNotificationChannels();
    await requestPermissions();
    _isInitialized = true;
  }

  @override
  Future<void> setupNotificationChannels() async {
    // Creates notification channels for different types of reminders
    var androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    await androidPlugin.createNotificationChannel(AndroidNotificationChannel(
        'medication_alarms_v2',
        'Medication Alarms',
        description: 'Critical medication reminders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
        audioAttributesUsage: AudioAttributesUsage.alarm
    ));
    await androidPlugin.createNotificationChannel(AndroidNotificationChannel(
        'daily_reminders_v2',
        'Daily Reminders',
        description: 'Daily medication reminders',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        audioAttributesUsage: AudioAttributesUsage.alarm
    ));
    await androidPlugin.createNotificationChannel(AndroidNotificationChannel(
        'weekly_reminders_v2',
        'Weekly Reminders',
        description: 'Weekly medication reminders',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        audioAttributesUsage: AudioAttributesUsage.alarm
    ));
    await androidPlugin.createNotificationChannel(AndroidNotificationChannel(
        'companion_medication_alarms',
        'Companion Medication Alarms',
        description: 'Medication reminders for companions',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        vibrationPattern: Int64List.fromList([0,400,200,400]),
        audioAttributesUsage: AudioAttributesUsage.notification
    ));
    await androidPlugin.createNotificationChannel(AndroidNotificationChannel(
        'test_notifications',
        'Test Notifications',
        description: 'For testing notification delivery',
        importance: Importance.high,
        playSound: true,
        enableVibration: true
    ));
  }

  @override
  Future<void> requestPermissions() async {
    var androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
      await _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
    }
  }

  @override
  Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
    required String medicationId,
    bool isSnoozed = false,
    required bool isCompanionCheck,
    RepeatInterval? repeatInterval
  }) async {
    // Schedules a notification with exact timing and handles edge cases
    if (!_isInitialized) return;

    // Cancel any existing notification with this ID to prevent duplicates
    await _notificationsPlugin.cancel(id);

    // Adjusts scheduled time if it's in the past or exactly now
    final nowExact = tz.TZDateTime.now(_riyadhTimezone);
    var scheduled = tz.TZDateTime(
        _riyadhTimezone,
        scheduledTime.year,
        scheduledTime.month,
        scheduledTime.day,
        scheduledTime.hour,
        scheduledTime.minute,
         0, // Explicitly zero out seconds
         0  // Explicitly zero out milliseconds
    );

    print("Android Service - Scheduling notification:");
    print("- ID: $id");
    print("- Current time exact: ${nowExact.toString()}");
    print("- Scheduled time: ${scheduled.toString()}");

    if (scheduled.isBefore(nowExact)) {
      // Adjust time for repeating notifications or move to the next day
      if (repeatInterval == null) {
        scheduled = tz.TZDateTime(
            _riyadhTimezone,
            nowExact.year,
            nowExact.month,
            nowExact.day + 1,
            scheduled.hour,
            scheduled.minute,
            0,
            0
        );
        print("Adjusted to tomorrow: ${scheduled.toString()}");
      } else {
        scheduled = repeatInterval == RepeatInterval.daily
            ? _nextInstanceOfTime(nowExact, TimeOfDay(hour: scheduled.hour, minute: scheduled.minute))
            : _nextInstanceOfWeekday(nowExact, scheduled.weekday, TimeOfDay(hour: scheduled.hour, minute: scheduled.minute));
        print("Adjusted to next occurrence: ${scheduled.toString()}");
      }
    }

    // Configures notification details and schedules it
    var androidDetails = AndroidNotificationDetails(
        'medication_alarms_v2',
        'Medication Alarms',
        channelDescription: 'Critical medication reminders',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    var details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: medicationId,
        matchDateTimeComponents: repeatInterval == RepeatInterval.daily
            ? DateTimeComponents.time
            : repeatInterval == RepeatInterval.weekly
                ? DateTimeComponents.dayOfWeekAndTime
                : null
    );
  }

  // Helper to calculate the next instance of a time for repeating notifications
  tz.TZDateTime _nextInstanceOfTime(tz.TZDateTime from, TimeOfDay tod) {
    var sched = tz.TZDateTime(_riyadhTimezone, from.year, from.month, from.day, tod.hour, tod.minute, 0, 0); // Zero seconds
    if (sched.isBefore(from)) {
      sched = tz.TZDateTime(_riyadhTimezone, from.year, from.month, from.day + 1, tod.hour, tod.minute, 0, 0); // Zero seconds
    }
    return sched;
  }

  // Helper to calculate the next instance of a weekday for weekly notifications
  tz.TZDateTime _nextInstanceOfWeekday(tz.TZDateTime from, int weekday, TimeOfDay tod) {
    var sched = tz.TZDateTime(_riyadhTimezone, from.year, from.month, from.day, tod.hour, tod.minute, 0, 0); // Zero seconds
    if (sched.isBefore(from)) {
      sched = tz.TZDateTime(_riyadhTimezone, from.year, from.month, from.day + 1, tod.hour, tod.minute, 0, 0); // Zero seconds
    }
    while (sched.weekday != weekday) {
      sched = tz.TZDateTime(_riyadhTimezone, sched.year, sched.month, sched.day + 1, tod.hour, tod.minute, 0, 0); // Zero seconds
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
    return await _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
  }
}
