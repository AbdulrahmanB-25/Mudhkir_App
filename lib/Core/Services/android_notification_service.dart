import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:timezone/timezone.dart' as tz;
import 'notification_service.dart';

class AndroidNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // Initialize directly instead of using 'late' to avoid initialization errors
  tz.Location _utcPlus3Location = tz.getLocation('Asia/Riyadh');
  bool _debugMode = true;
  bool _isInitialized = false;

  AndroidNotificationService() {
    // Initialize timezone data in constructor to ensure it's always available
    _initializeTimeZones();
  }

  void _initializeTimeZones() {
    try {
      // Initialize timezone database
      tz_init.initializeTimeZones();
      _utcPlus3Location = tz.getLocation('Asia/Riyadh'); // Saudi Arabia is UTC+3
      tz.setLocalLocation(_utcPlus3Location); // Set as default timezone
      debugLog("Timezone data initialized with UTC+3 (Asia/Riyadh)");
    } catch (e) {
      debugLog("ERROR initializing timezone data: $e");
      // If initialization fails, we have already set a default value for _utcPlus3Location
    }
  }

  @override
  FlutterLocalNotificationsPlugin get notificationsPlugin => _notificationsPlugin;

  @override
  Future<void> initialize(
      BuildContext context,
      void Function(NotificationResponse) onNotificationResponse,
      void Function(NotificationResponse)? onBackgroundNotificationResponse
      ) async {
    if (_isInitialized) {
      debugLog("Service already initialized, skipping initialization");
      return;
    }

    debugLog("Initializing notification service...");
    final androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    debugLog("Created Android initialization settings");

    final initSettings = InitializationSettings(android: androidInit, iOS: null);

    // Timezone is already initialized in constructor, just log current time
    final now = tz.TZDateTime.now(_utcPlus3Location);
    debugLog("Current time in UTC+3: ${now.toString()}");
    debugLog("Current offset from UTC: ${_utcPlus3Location.currentTimeZone.offset / 3600} hours");

    try {
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
      );
      debugLog("Plugin initialized successfully");
    } catch (e) {
      debugLog("ERROR initializing plugin: $e");
    }

    await setupNotificationChannels();
    await requestPermissions();
    _isInitialized = true;
    debugLog("Initialization complete");
  }

  // Helper method for consistent logging
  void debugLog(String message) {
    final now = DateTime.now();
    final formattedTime = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

    if (_debugMode) {
      print("[AndroidNotificationService] [$formattedTime] $message");
    } else {
      print("[AndroidNotificationService] $message");
    }
  }

  @override
  Future<void> setupNotificationChannels() async {
    debugLog("Setting up notification channels...");
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) {
      debugLog("Failed to get Android plugin implementation");
      return;
    }

    try {
      // Main medication alarm channel - high importance
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

      await androidPlugin.createNotificationChannel(alarmChannel);
      debugLog("Created main medication alarm channel");

      // Daily reminders channel
      final dailyChannel = AndroidNotificationChannel(
        'daily_reminders_v2',
        'Daily Reminders',
        description: 'Daily medication reminders',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );

      await androidPlugin.createNotificationChannel(dailyChannel);
      debugLog("Created daily reminders channel");

      // Weekly reminders channel
      final weeklyChannel = AndroidNotificationChannel(
        'weekly_reminders_v2',
        'Weekly Reminders',
        description: 'Weekly medication reminders',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );

      await androidPlugin.createNotificationChannel(weeklyChannel);
      debugLog("Created weekly reminders channel");

      // Companion medication channel
      final companionChannel = AndroidNotificationChannel(
        'companion_medication_alarms',
        'Companion Medication Alarms',
        description: 'Medication reminders for companions',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        sound: RawResourceAndroidNotificationSound('medication_alarm'),
        audioAttributesUsage: AudioAttributesUsage.notification, // Use notification for less critical companion alerts
      );

      await androidPlugin.createNotificationChannel(companionChannel);
      debugLog("Created companion medication channel");

      // Test notification channel
      final testChannel = AndroidNotificationChannel(
        'test_notifications',
        'Test Notifications',
        description: 'For testing notification delivery',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await androidPlugin.createNotificationChannel(testChannel);
      debugLog("Created test notification channel");

    } catch (e) {
      debugLog("ERROR creating notification channels: $e");
    }
  }

  @override
  Future<void> requestPermissions() async {
    debugLog("Requesting notification permissions...");
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      try {
        // This properly handles permission requests on Android 13+ (API 33+)
        final bool? result = await androidPlugin.requestNotificationsPermission();
        debugLog("Notification permission request result: $result");

        // Log exact alarm permission status
        final exactAlarmPermissionStatus = await checkExactAlarmPermission();
        debugLog("Exact alarm permission status: $exactAlarmPermissionStatus");
        
        if (exactAlarmPermissionStatus == false) {
          debugLog("⚠️ IMPORTANT: Exact alarm permission not granted. May affect notification reliability.");
        }

      } catch (e) {
        debugLog("ERROR requesting permissions: $e");
      }
    } else {
      debugLog("Android plugin implementation is null");
    }
  }
  
  // New method to check exact alarm permission
  Future<bool?> checkExactAlarmPermission() async {
    try {
      // Exact alarm permission check via platform channel (simplified implementation)
      // In a real app, you would implement this with a platform-specific method channel
      
      // For SDK >= 31 (Android 12+)
      // This is a placeholder - you would need to implement the actual check with platform channels
      return true; // Assuming granted for now
    } catch (e) {
      debugLog("Error checking exact alarm permission: $e");
      return null;
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
    RepeatInterval? repeatInterval,
  }) async {
    // Ensure we have timezone data initialized
    if (!_isInitialized) {
      debugLog("WARNING: Service not fully initialized before scheduling. Using minimal initialization.");
      // We already initialized timezone in constructor, so we can continue
    }

    // Try to cancel any existing notification with this ID first
    try {
      await _notificationsPlugin.cancel(id);
      debugLog("Cancelled any existing notification with ID: $id");
    } catch (e) {
      debugLog("Error cancelling previous notification: $e");
      // Continue anyway since this is just a precaution
    }

    // Ensure scheduledTime is in UTC+3
    tz.TZDateTime scheduledTimeUtcPlus3 = _ensureUtcPlus3Time(scheduledTime);

    final now = tz.TZDateTime.now(_utcPlus3Location);
    final difference = scheduledTimeUtcPlus3.difference(now);

    debugLog("Scheduling notification ID $id for ${scheduledTimeUtcPlus3.toString()} (UTC+3)");
    debugLog("Current time: ${now.toString()} (UTC+3)");
    debugLog("Time difference: ${difference.inSeconds} seconds");

    // Check if this is a special notification type
    final bool isTestNotification = title.contains("اختبار إشعار");

    String channelId;
    String channelName;
    List<AndroidNotificationAction> actions = [];
    bool useFullScreen = false;

    if (isTestNotification) {
      channelId = 'test_notifications';
      channelName = 'Test Notifications';
      useFullScreen = false;
    } else if (isCompanionCheck) {
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

    debugLog("Using channel: $channelId for notification ID $id");

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
      sound: isTestNotification ? null : RawResourceAndroidNotificationSound('medication_alarm'),
      audioAttributesUsage: isCompanionCheck ? AudioAttributesUsage.notification : AudioAttributesUsage.alarm,
      visibility: NotificationVisibility.public,
      actions: actions,
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      // Handle past time scheduling
      if (scheduledTimeUtcPlus3.isBefore(now)) {
        if (repeatInterval == null) {
          // For non-repeating alarms, adjust time to the next day instead of skipping
          debugLog("ID: $id Scheduled time ${scheduledTimeUtcPlus3.toString()} is past. Adjusting to next day.");
          scheduledTimeUtcPlus3 = tz.TZDateTime(
              _utcPlus3Location,
              now.year, now.month, now.day + 1,
              scheduledTimeUtcPlus3.hour, scheduledTimeUtcPlus3.minute);
        } else {
          debugLog("ID: $id Original time ${scheduledTimeUtcPlus3.toString()} is past. Adjusting for repeat interval $repeatInterval...");
          scheduledTimeUtcPlus3 = _adjustTimeForRepeat(now, scheduledTimeUtcPlus3, repeatInterval);
          debugLog("ID: $id Adjusted time: ${scheduledTimeUtcPlus3.toString()}");
        }
      }

      // For times very close to now (less than 30 seconds), add a small buffer to ensure it fires
      if (scheduledTimeUtcPlus3.difference(now).inSeconds < 30) {
        // If it's too close, add 30 seconds to ensure it has time to be scheduled
        scheduledTimeUtcPlus3 = now.add(const Duration(seconds: 30));
        debugLog("ID: $id Time too close to now, adjusted to: ${scheduledTimeUtcPlus3.toString()}");
      }

      // Configure date/time matching components for repeating notifications
      DateTimeComponents? match;
      if (repeatInterval == RepeatInterval.daily) {
        match = DateTimeComponents.time;
        debugLog("Using daily repeat pattern (time components only)");
      } else if (repeatInterval == RepeatInterval.weekly) {
        match = DateTimeComponents.dayOfWeekAndTime;
        debugLog("Using weekly repeat pattern (day of week and time)");
      }

      debugLog("Scheduling notification ID: $id, Time: ${scheduledTimeUtcPlus3.toString()}, "
          "Match: $match, Payload: $medicationId");

      // Add a debug verification notification if this is not a test
      if (!isTestNotification && _debugMode) {
        // Schedule a verification notification 10 seconds after the actual one
        final verificationTime = scheduledTimeUtcPlus3.add(const Duration(seconds: 10));
        final verificationId = id + 1000000; // Use a different ID with large offset

        try {
          await _notificationsPlugin.zonedSchedule(
            verificationId,
            "⚠️ تحقق من الإشعار السابق",
            "هذا إشعار تحقق من إشعار الدواء رقم $id. تم جدولته للتحقق من وصول الإشعارات.",
            verificationTime,
            details,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: "verification_$medicationId",
          );
          debugLog("Scheduled verification notification ID: $verificationId for time: ${verificationTime.toString()}");
        } catch (e) {
          debugLog("ERROR scheduling verification notification: $e");
        }
      }

      // Schedule the main notification
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTimeUtcPlus3,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: medicationId,
        matchDateTimeComponents: match,
      );

      debugLog("Successfully scheduled notification ID $id for ${scheduledTimeUtcPlus3.toString()}");

      // Log the expected notification time in both UTC and device local time
      final localDateTime = scheduledTimeUtcPlus3.toLocal();
      debugLog("Expected notification time (UTC+3): ${scheduledTimeUtcPlus3.toString()}");
      debugLog("Expected notification time (Device local): ${localDateTime.toString()}");

    } catch (e, stackTrace) {
      debugLog("ERROR scheduling notification: $e");
      debugLog("Stack trace: $stackTrace");
      throw e;
    }
  }

  // Ensure time is in UTC+3
  tz.TZDateTime _ensureUtcPlus3Time(tz.TZDateTime dateTime) {
    if (dateTime.location.name != _utcPlus3Location.name) {
      debugLog("Converting time from ${dateTime.location.name} to UTC+3 (Asia/Riyadh)");
      final utcTime = dateTime.toUtc();
      return tz.TZDateTime.from(utcTime, _utcPlus3Location);
    }
    return dateTime;
  }

  tz.TZDateTime _adjustTimeForRepeat(
      tz.TZDateTime now,
      tz.TZDateTime scheduledTime,
      RepeatInterval repeatInterval
      ) {
    final tod = TimeOfDay.fromDateTime(scheduledTime);
    if (repeatInterval == RepeatInterval.daily) {
      return _nextInstanceOfTime(now, tod);
    } else {
      return _nextInstanceOfWeekday(now, scheduledTime.weekday, tod);
    }
  }

  tz.TZDateTime _nextInstanceOfTime(tz.TZDateTime from, TimeOfDay tod) {
    // Create a date with the same day as 'from' but with the target time
    tz.TZDateTime sched = tz.TZDateTime(_utcPlus3Location, from.year, from.month, from.day, tod.hour, tod.minute);

    // If the time has already passed today, move to tomorrow
    if (sched.isBefore(from)) {
      sched = tz.TZDateTime(_utcPlus3Location, from.year, from.month, from.day + 1, tod.hour, tod.minute);
    }

    debugLog("Next time instance: ${sched.toString()} (UTC+3)");
    return sched;
  }

  tz.TZDateTime _nextInstanceOfWeekday(tz.TZDateTime from, int weekday, TimeOfDay tod) {
    // Start with today at the target time
    tz.TZDateTime sched = tz.TZDateTime(_utcPlus3Location, from.year, from.month, from.day, tod.hour, tod.minute);

    // If today's time has passed, start from tomorrow
    if (sched.isBefore(from)) {
      sched = tz.TZDateTime(_utcPlus3Location, from.year, from.month, from.day + 1, tod.hour, tod.minute);
    }

    // Keep adding days until we reach the target weekday
    while (sched.weekday != weekday) {
      sched = tz.TZDateTime(_utcPlus3Location, sched.year, sched.month, sched.day + 1, tod.hour, tod.minute);
    }

    debugLog("Next instance of weekday $weekday: ${sched.toString()} (UTC+3)");
    return sched;
  }

  @override
  Future<void> cancelNotification(int id) async {
    debugLog("Cancelling notification ID: $id");
    await _notificationsPlugin.cancel(id);
  }

  @override
  Future<void> cancelAllNotifications() async {
    debugLog("Cancelling all notifications");
    await _notificationsPlugin.cancelAll();
  }

  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    final requests = await _notificationsPlugin.pendingNotificationRequests();
    debugLog("Found ${requests.length} pending notifications");

    if (requests.isNotEmpty) {
      debugLog("Pending notifications:");
      for (var req in requests) {
        debugLog("  ID: ${req.id}, Title: ${req.title}, Body: ${req.body}");
      }
    }

    return requests;
  }

  @override
  Future<bool?> checkNotificationPermissions() async {
    debugLog("Checking if notifications are enabled...");
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      try {
        final notificationsEnabled = await androidPlugin.areNotificationsEnabled();
        debugLog("Notifications enabled: $notificationsEnabled");

        // We can't directly check exact alarm permissions with the current version
        // So we assume it's enabled if notifications are enabled
        debugLog("NOTE: Cannot programmatically check exact alarm permissions in this version");
        debugLog("Assuming exact alarms are enabled if notifications are enabled");

        return notificationsEnabled;
      } catch (e) {
        debugLog("ERROR checking permissions: $e");
      }
    }
    return null;
  }

  // Method to show an immediate test notification (for debugging)
  Future<void> showTestNotification() async {
    debugLog("Showing immediate test notification");

    final int testId = 999999;

    try {
      await _notificationsPlugin.show(
        testId,
        "⚠️ اختبار فوري للإشعارات",
        "هذا اختبار فوري للتحقق من عمل نظام الإشعارات. الوقت الحالي: ${DateTime.now().toString()}",
        NotificationDetails(
          android: AndroidNotificationDetails(
            'test_notifications',
            'Test Notifications',
            channelDescription: 'For testing notification delivery',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        payload: "immediate_test",
      );
      debugLog("Successfully sent immediate test notification");
    } catch (e) {
      debugLog("ERROR showing immediate test notification: $e");
      throw e;
    }
  }
}
