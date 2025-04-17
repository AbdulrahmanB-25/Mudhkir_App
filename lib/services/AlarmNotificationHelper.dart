import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_service.dart';

class AlarmNotificationHelper {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    debugPrint("[AlarmHelper] Initializing...");

    // Setup notification channels
    await _setupNotificationChannels();

    // Initialize plugin
    final InitializationSettings initializationSettings = InitializationSettings(
      android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: const DarwinInitializationSettings(
        requestSoundPermission: true,
        requestBadgePermission: true,
        requestAlertPermission: true,
      ),
    );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );
    debugPrint("[AlarmHelper] Initialization complete");
  }

  static Future<void> _setupNotificationChannels() async {
    if (Platform.isAndroid) {
      // Create a dedicated high-priority alarm channel
      const AndroidNotificationChannelGroup channelGroup =
      AndroidNotificationChannelGroup(
        'medication_reminders',
        'Medication Reminders',
        description: 'All notifications related to medication reminders',
      );

      // Primary alarm channel for medication reminders
      AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
        'medication_alarm_channel',
        'Medication Alarms',
        description: 'Critical reminders for medication doses',
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('alarm_sound'),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]),
        enableLights: true,
        ledColor: const Color.fromARGB(255, 255, 0, 0),
      );

      // Create the channel groups and channels
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannelGroup(channelGroup);

      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(alarmChannel);

      debugPrint("[AlarmHelper] Android notification channels created");
    }
  }

  static void _onNotificationResponse(NotificationResponse response) async {
    final String? payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      debugPrint("[AlarmHelper] Notification response: ${response.actionId}, payload: $payload");

      // Track notification interaction
      await NotificationService().trackNotificationEvent("interaction", payload);

      // Store medication ID for navigation using SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_notification_docId', payload);
      await prefs.setInt('notification_timestamp', DateTime.now().millisecondsSinceEpoch);

      // Handle different actions
      switch (response.actionId) {
        case 'mark_taken':
          debugPrint("[AlarmHelper] User marked medication as taken");
          // Cancel the notification
          if (response.id != null) {
            await _notificationsPlugin.cancel(response.id!);
          }
          break;

        case 'snooze':
          debugPrint("[AlarmHelper] User snoozed medication reminder");
          // Reschedule for 5 minutes later
          final now = tz.TZDateTime.now(tz.local);
          final snoozeTime = now.add(const Duration(minutes: 5));

          // Generate new ID for snoozed notification (original ID + 100000)
          final int snoozeId = response.id != null ?
          response.id! + 100000 :
          DateTime.now().millisecondsSinceEpoch.remainder(100000);

          await scheduleAlarmNotification(
            id: snoozeId,
            title: 'تذكير مؤجل للدواء',
            body: 'تم تأجيل تذكير الدواء، الرجاء تناوله الآن',
            scheduledTime: snoozeTime,
            medicationId: payload,
            isSnoozed: true,
          );
          break;

        default:
        // Regular notification tap - handled by the main app
          break;
      }
    }
  }

  /// Schedule a medication alarm notification
  static Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String medicationId,
    bool isSnoozed = false,
  }) async {
    if (medicationId.isEmpty) {
      debugPrint("[AlarmHelper] Error: Empty medicationId provided");
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final bool vibrationEnabled = prefs.getBool('vibrationEnabled') ?? true;
      final bool soundEnabled = prefs.getBool('soundEnabled') ?? true;

      debugPrint("[AlarmHelper] Scheduling notification ID: $id with medicationId: $medicationId");
      debugPrint("[AlarmHelper] Settings - Sound: $soundEnabled, Vibration: $vibrationEnabled");

      // Add check to ensure scheduledTime is in the future
      final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
      tz.TZDateTime scheduledTZ = tz.TZDateTime.from(scheduledTime, tz.local);
      if (scheduledTZ.isBefore(now)) {
         scheduledTZ = scheduledTZ.add(const Duration(days: 1));
         debugPrint("[AlarmHelper] Adjusted scheduled time to: $scheduledTZ");
      }

      // Configure Android Notification Details
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'medication_alarm_channel',
        'Medication Alarms',
        channelDescription: 'Critical reminders for medication doses',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: vibrationEnabled,
        vibrationPattern: vibrationEnabled ?
        Int64List.fromList([0, 1000, 500, 1000, 500, 1000]) : null,
        playSound: soundEnabled,
        sound: soundEnabled ? const RawResourceAndroidNotificationSound('alarm_sound') : null,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableLights: true,
        color: Colors.red,
        ledColor: Colors.red,
        ledOnMs: 1000,
        ledOffMs: 500,
        ongoing: true,  // Makes notification persistent
        fullScreenIntent: true,  // Can launch full screen on lock screen
        category: AndroidNotificationCategory.alarm,
        actions: [
          const AndroidNotificationAction(
            'mark_taken',
            'تناولت الدواء',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            'snooze',
            'تذكير لاحقا',
            showsUserInterface: true,
          ),
        ],
      );

      // Configure iOS/macOS Notification Details
      final DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'alarm_sound.wav', // Make sure this file exists in iOS project
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      // Combine Platform Details
      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      // Schedule the notification using the adjusted scheduledTZ
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTZ,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: medicationId,
      );

      // Track notification scheduling
      await NotificationService().trackNotificationEvent("scheduled", medicationId);

      debugPrint("[AlarmHelper] Successfully scheduled notification $id for $scheduledTZ");
    } catch (e, stacktrace) {
      debugPrint("[AlarmHelper] Error scheduling notification $id: $e");
      debugPrint("[AlarmHelper] Stacktrace: $stacktrace");
    }
  }

  /// Schedule a daily repeating notification
  static Future<void> scheduleDailyRepeatingNotification({
    required int id,
    required String title,
    required String body,
    required TimeOfDay timeOfDay,
    required String payload,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool vibrationEnabled = prefs.getBool('vibrationEnabled') ?? true;
      final bool soundEnabled = prefs.getBool('soundEnabled') ?? true;

      debugPrint("[AlarmHelper] Scheduling daily repeating notification ID: $id with payload: $payload");
      debugPrint("[AlarmHelper] Settings - Sound: $soundEnabled, Vibration: $vibrationEnabled");

      // Configure Android Notification Details
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'medication_alarm_channel',
        'Medication Alarms',
        channelDescription: 'Critical reminders for medication doses',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: vibrationEnabled,
        vibrationPattern: vibrationEnabled ?
        Int64List.fromList([0, 1000, 500, 1000, 500, 1000]) : null,
        playSound: soundEnabled,
        sound: soundEnabled ? const RawResourceAndroidNotificationSound('alarm_sound') : null,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableLights: true,
        color: Colors.red,
        ledColor: Colors.red,
        ledOnMs: 1000,
        ledOffMs: 500,
        ongoing: true,  // Makes notification persistent
        fullScreenIntent: true,  // Can launch full screen on lock screen
        category: AndroidNotificationCategory.alarm,
        actions: [
          const AndroidNotificationAction(
            'mark_taken',
            'تناولت الدواء',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            'snooze',
            'تذكير لاحقا',
            showsUserInterface: true,
          ),
        ],
      );

      // Configure iOS/macOS Notification Details
      final DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'alarm_sound.wav', // Make sure this file exists in iOS project
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      // Combine Platform Details
      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      // Schedule the notification using Timezone-aware DateTime
      tz.TZDateTime scheduledTime = tz.TZDateTime(
        tz.local,
        startDate.year,
        startDate.month,
        startDate.day,
        timeOfDay.hour,
        timeOfDay.minute,
      );

      if (scheduledTime.isBefore(tz.TZDateTime.now(tz.local))) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTime,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );

      debugPrint("[AlarmHelper] Successfully scheduled daily repeating notification $id for $scheduledTime");
    } catch (e, stacktrace) {
      debugPrint("[AlarmHelper] Error scheduling daily repeating notification $id: $e");
      debugPrint("[AlarmHelper] Stacktrace: $stacktrace");
    }
  }

  /// Schedule a weekly repeating notification
  static Future<void> scheduleWeeklyRepeatingNotification({
    required int id,
    required String title,
    required String body,
    required int weekday,
    required TimeOfDay timeOfDay,
    required String payload,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool vibrationEnabled = prefs.getBool('vibrationEnabled') ?? true;
      final bool soundEnabled = prefs.getBool('soundEnabled') ?? true;

      debugPrint("[AlarmHelper] Scheduling weekly repeating notification ID: $id with payload: $payload");
      debugPrint("[AlarmHelper] Settings - Sound: $soundEnabled, Vibration: $vibrationEnabled");

      // Configure Android Notification Details
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'medication_alarm_channel',
        'Medication Alarms',
        channelDescription: 'Critical reminders for medication doses',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        enableVibration: vibrationEnabled,
        vibrationPattern: vibrationEnabled ?
        Int64List.fromList([0, 1000, 500, 1000, 500, 1000]) : null,
        playSound: soundEnabled,
        sound: soundEnabled ? const RawResourceAndroidNotificationSound('alarm_sound') : null,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableLights: true,
        color: Colors.red,
        ledColor: Colors.red,
        ledOnMs: 1000,
        ledOffMs: 500,
        ongoing: true,  // Makes notification persistent
        fullScreenIntent: true,  // Can launch full screen on lock screen
        category: AndroidNotificationCategory.alarm,
        actions: [
          const AndroidNotificationAction(
            'mark_taken',
            'تناولت الدواء',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            'snooze',
            'تذكير لاحقا',
            showsUserInterface: true,
          ),
        ],
      );

      // Configure iOS/macOS Notification Details
      final DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'alarm_sound.wav', // Make sure this file exists in iOS project
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      // Combine Platform Details
      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      );

      // Schedule the notification using Timezone-aware DateTime
      tz.TZDateTime scheduledTime = tz.TZDateTime(
        tz.local,
        startDate.year,
        startDate.month,
        startDate.day,
        timeOfDay.hour,
        timeOfDay.minute,
      );

      // Find the next occurrence of the specified weekday
      while (scheduledTime.weekday != weekday) {
        scheduledTime = scheduledTime.add(const Duration(days: 1));
      }

      if (scheduledTime.isBefore(tz.TZDateTime.now(tz.local))) {
        scheduledTime = scheduledTime.add(const Duration(days: 7));
      }

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTime,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: payload,
      );

      debugPrint("[AlarmHelper] Successfully scheduled weekly repeating notification $id for $scheduledTime");
    } catch (e, stacktrace) {
      debugPrint("[AlarmHelper] Error scheduling weekly repeating notification $id: $e");
      debugPrint("[AlarmHelper] Stacktrace: $stacktrace");
    }
  }

  /// Cancel all scheduled notifications
  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    debugPrint("[AlarmHelper] All notifications cancelled");
  }

  /// Cancel a specific notification by ID
  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
    debugPrint("[AlarmHelper] Notification $id cancelled");
  }
}

