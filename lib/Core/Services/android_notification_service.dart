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
        vibrationPattern: Int64List.fromList([0,500,200,500]),
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
    if (!_isInitialized) {}
    
    // Cancel any existing notification with this ID first to prevent duplicates
    await _notificationsPlugin.cancel(id);
    
    // Get current time with full precision for comparison
    final nowExact = tz.TZDateTime.now(_riyadhTimezone);
    
    // Clean current time (zero seconds for comparison)
    final now = tz.TZDateTime(
      _riyadhTimezone,
      nowExact.year,
      nowExact.month,
      nowExact.day,
      nowExact.hour,
      nowExact.minute,
      0,
      0
    );
    
    // Create a clean time with seconds and milliseconds zeroed out
    // Change from final to var so it can be reassigned
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
    print("- Current time rounded: ${now.toString()}");
    print("- Scheduled time: ${scheduled.toString()}");
    print("- Difference in minutes: ${scheduled.difference(now).inMinutes}");
    print("- Difference in seconds: ${scheduled.difference(nowExact).inSeconds}");
    
    // Check if time is exactly now (same minute)
    final isExactlyNow = scheduled.year == now.year &&
                        scheduled.month == now.month &&
                        scheduled.day == now.day &&
                        scheduled.hour == now.hour &&
                        scheduled.minute == now.minute;
                        
    if (isExactlyNow) {
      print("Time is exactly now, scheduling immediate notification");
      _notificationsPlugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'medication_alarms_v2',
            'Medication Alarms',
            channelDescription: 'Critical medication reminders',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            sound: RawResourceAndroidNotificationSound('medication_alarm'),
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        ),
        payload: medicationId,
      );
      return;
    }
    
    // Check if the time is in the past
    if (scheduled.isBefore(now)) {
      print("Scheduled time is in the past");
      
      if (repeatInterval == null) {
        // For non-repeating notifications, move to tomorrow at the same time
        scheduled = tz.TZDateTime(
            _riyadhTimezone,
            now.year,
            now.month,
            now.day + 1,
            scheduled.hour,
            scheduled.minute,
            0, // Keep seconds at zero
            0  // Keep milliseconds at zero
        );
        print("Adjusted to tomorrow: ${scheduled.toString()}");
      } else {
        // For repeating notifications, find the next occurrence
        scheduled = repeatInterval == RepeatInterval.daily
            ? _nextInstanceOfTime(now, TimeOfDay(hour: scheduled.hour, minute: scheduled.minute))
            : _nextInstanceOfWeekday(now, scheduled.weekday, TimeOfDay(hour: scheduled.hour, minute: scheduled.minute));
        print("Adjusted to next occurrence: ${scheduled.toString()}");
      }
    }
    
    // Final safety check - if by some calculation error we still have a past time
    if (scheduled.isBefore(nowExact)) {
      print("SAFETY CHECK: Time is still in the past after adjustment");
      scheduled = tz.TZDateTime(
        _riyadhTimezone,
        nowExact.year,
        nowExact.month,
        nowExact.day,
        nowExact.hour,
        nowExact.minute + 1, // Schedule for next minute
        0,
        0
      );
      print("Safety adjusted to one minute from now: ${scheduled.toString()}");
    }
    
    // Configure match components for repeating notifications
    DateTimeComponents? match;
    if (repeatInterval == RepeatInterval.daily) {
      match = DateTimeComponents.time;
    } else if (repeatInterval == RepeatInterval.weekly) {
      match = DateTimeComponents.dayOfWeekAndTime;
    }
    
    // Determine the appropriate channel
    var channelId = isCompanionCheck
        ? 'companion_medication_alarms'
        : isSnoozed
        ? 'medication_alarms_v2'
        : repeatInterval == RepeatInterval.daily
        ? 'daily_reminders_v2'
        : repeatInterval == RepeatInterval.weekly
        ? 'weekly_reminders_v2'
        : 'medication_alarms_v2';
        
    // Configure notification details
    var useFullScreen = !isCompanionCheck;
    var actions = <AndroidNotificationAction>[
      AndroidNotificationAction('TAKE_ACTION', 'Take Now'),
      AndroidNotificationAction('SNOOZE_ACTION', 'Snooze (5 min)')
    ];
    var androidDetails = AndroidNotificationDetails(
        channelId,
        channelId == 'daily_reminders_v2' ? 'Daily Reminders' :
        channelId == 'weekly_reminders_v2' ? 'Weekly Reminders' :
        channelId == 'companion_medication_alarms' ? 'Companion Medication Alarms' :
        channelId == 'test_notifications' ? 'Test Notifications' :
        'Medication Alarms',
        channelDescription: 'Medication reminder notifications',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: useFullScreen,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        audioAttributesUsage: isCompanionCheck ? AudioAttributesUsage.notification : AudioAttributesUsage.alarm,
        visibility: NotificationVisibility.public,
        actions: isCompanionCheck ? [] : actions
    );
    var details = NotificationDetails(android: androidDetails);
    
    // Schedule the notification with exact timing even in doze mode
    print("Final scheduled time: ${scheduled.toString()}");
    await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // Use exact timing even when device is in doze mode
        payload: medicationId,
        matchDateTimeComponents: match
    );
  }

  tz.TZDateTime _nextInstanceOfTime(tz.TZDateTime from, TimeOfDay tod) {
    var sched = tz.TZDateTime(_riyadhTimezone, from.year, from.month, from.day, tod.hour, tod.minute, 0, 0); // Zero seconds
    if (sched.isBefore(from)) {
      sched = tz.TZDateTime(_riyadhTimezone, from.year, from.month, from.day + 1, tod.hour, tod.minute, 0, 0); // Zero seconds
    }
    return sched;
  }

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

