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
    print("[Android Service Init] Initializing plugin...");
    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
    );
    print("[Android Service Init] Plugin initialized.");
    await setupNotificationChannels();
    await requestPermissions();
  }

  @override
  Future<void> setupNotificationChannels() async {
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) {
      print("[Android Service Setup] Android plugin implementation not found.");
      return;
    }
    print("[Android Service Setup] Creating notification channels...");

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
    final companionChannel = AndroidNotificationChannel(
      'companion_medication_alarms',
      'Companion Medication Alarms',
      description: 'Medication reminders for companions',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound('medication_alarm'),
      audioAttributesUsage: AudioAttributesUsage.notification, // Use notification for less critical companion alerts
    );

    try {
      await androidPlugin.createNotificationChannel(alarmChannel);
      await androidPlugin.createNotificationChannel(dailyChannel);
      await androidPlugin.createNotificationChannel(weeklyChannel);
      await androidPlugin.createNotificationChannel(companionChannel);
      print("[Android Service Setup] Channels created successfully.");
    } catch (e) {
      print("[Android Service Setup] Error creating channels: $e");
    }
  }

  @override
  Future<void> requestPermissions() async {
    print("[Android Service Perms] Requesting notification permissions...");
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    try {
      final bool? result = await androidPlugin?.requestNotificationsPermission();
      print("[Android Service Perms] Permission request result: $result");
    } catch (e) {
      print("[Android Service Perms] Error requesting permissions: $e");
    }
    // Note: SCHEDULE_EXACT_ALARM permission might need separate handling if targeting Android 12+
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
    RepeatInterval? repeatInterval,
  }) async {

    final String channelId;
    final String channelName;
    List<AndroidNotificationAction> actions = [];
    bool useFullScreen = false;

    if (isCompanionCheck) {
      channelId = 'companion_medication_alarms';
      channelName = 'Companion Medication Alarms';
      useFullScreen = false; // Companion alerts might not need full screen
    } else if (isSnoozed) {
      channelId = 'medication_alarms_v2';
      channelName = 'Medication Alarms';
      useFullScreen = true; // Snoozed alarms are still important
      actions = <AndroidNotificationAction>[
        AndroidNotificationAction('TAKE_ACTION', 'Take Now'),
        AndroidNotificationAction('SNOOZE_ACTION', 'Snooze (5 min)'),
      ];
    } else {
      useFullScreen = true; // Regular personal alarms are critical
      channelId = (repeatInterval == RepeatInterval.daily)
          ? 'daily_reminders_v2'
          : (repeatInterval == RepeatInterval.weekly)
          ? 'weekly_reminders_v2'
          : 'medication_alarms_v2';

      channelName = (repeatInterval == RepeatInterval.daily)
          ? 'Daily Reminders'
          : (repeatInterval == RepeatInterval.weekly)
          ? 'Weekly Reminders'
          : 'Medication Alarms';

      actions = <AndroidNotificationAction>[
        AndroidNotificationAction('TAKE_ACTION', 'Take Now'),
        AndroidNotificationAction('SNOOZE_ACTION', 'Snooze (5 min)'),
      ];
    }

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Medication reminder notifications',
      importance: Importance.max,
      priority: Priority.high,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: useFullScreen,
      ongoing: false,
      autoCancel: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('medication_alarm'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      actions: actions,
    );

    final details = NotificationDetails(android: androidDetails, iOS: null);

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime effectiveTime = scheduledTime;

    // --- CHANGES START ---
    if (effectiveTime.isBefore(now)) {
      if (repeatInterval == null) {
        // For non-repeating alarms, adjust time to the next day instead of skipping
        print("[Android Service Schedule] ID: $id Scheduled time ${effectiveTime.toIso8601String()} is past. Adjusting to next day.");
        effectiveTime = effectiveTime.add(const Duration(days: 1));
      } else {
        print("[Android Service Schedule] ID: $id Original time ${effectiveTime.toIso8601String()} is past. Adjusting for repeat interval $repeatInterval...");
        effectiveTime = _adjustTimeForRepeat(now, effectiveTime.toLocal(), repeatInterval);
        print("[Android Service Schedule] ID: $id Adjusted time: ${effectiveTime.toIso8601String()}");
      }
    }
    // --- CHANGES END ---

    DateTimeComponents? match;
    if (repeatInterval == RepeatInterval.daily) {
      match = DateTimeComponents.time;
    } else if (repeatInterval == RepeatInterval.weekly) {
      match = DateTimeComponents.dayOfWeekAndTime;
    }

    try {
      await _notificationsPlugin.cancel(id);
      print("[Android Service Schedule] Scheduling ID: $id, Title: $title, EffTime: ${effectiveTime.toIso8601String()} (${effectiveTime.timeZoneName}), Channel: $channelId, Payload: $medicationId, Repeat: $repeatInterval, Match: $match");
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        effectiveTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // Request exact timing
        payload: medicationId,
        matchDateTimeComponents: match,
      );
      print("[Android Service Schedule] Successfully scheduled ID: $id");
    } catch(e, stackTrace) {
      print("[Android Service Schedule] FAILED to schedule ID: $id - $e\n$stackTrace");
    }
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
    if (!sched.isAfter(base.subtract(const Duration(seconds: 1)))) {
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
    print("[Android Service Cancel] Canceling notification ID: $id");
    await _notificationsPlugin.cancel(id);
  }

  @override
  Future<void> cancelAllNotifications() async {
    print("[Android Service Cancel] Canceling ALL notifications.");
    await _notificationsPlugin.cancelAll();
  }

  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    print("[Android Service Pending] Getting pending notifications...");
    return await _notificationsPlugin.pendingNotificationRequests();
  }

  @override
  Future<bool?> checkNotificationPermissions() async {
    print("[Android Service Perms] Checking if notifications are enabled...");
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await androidPlugin?.areNotificationsEnabled();
  }
}
