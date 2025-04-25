import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'notification_service.dart';

class AndroidNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  @override
  FlutterLocalNotificationsPlugin get notificationsPlugin => _notificationsPlugin;
  
  @override
  Future<void> initialize(
    BuildContext context, 
    void Function(NotificationResponse) onNotificationResponse,
    void Function(NotificationResponse)? onBackgroundNotificationResponse
  ) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: null, // Only Android settings
    );
    
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
    debugPrint("[AndroidNotificationService] Setting up notification channels");
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
        
    if (androidPlugin == null) {
      debugPrint("[AndroidNotificationService] ERROR: Could not resolve Android plugin");
      return;
    }

    // Use a new channel ID to force recreation with updated settings
    AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
      'medication_alarms_new3', // Updated channel id again
      'Medication Alarms',
      description: 'Critical medication reminders',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      sound: const RawResourceAndroidNotificationSound('medication_alarm'),
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
    );

    try {
      await androidPlugin.createNotificationChannel(alarmChannel);
      debugPrint("[AndroidNotificationService] Successfully created alarm channel");

      // Verify the channel was created and has sound
      final channels = await androidPlugin.getNotificationChannels();
      for (var channel in channels ?? []) {
        debugPrint("[AndroidNotificationService] Channel: ${channel.id}, Sound: ${channel.sound?.sound}, PlaySound: ${channel.playSound}");
      }
    } catch (e) {
      debugPrint("[AndroidNotificationService] Error creating notification channel: $e");
    }
  }
  
  @override
  Future<void> requestPermissions() async {
    final androidPlugin = _notificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
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
    debugPrint("[AndroidNotificationService] Scheduling notification with ID: $id");
    debugPrint("[AndroidNotificationService] Title: $title");
    debugPrint("[AndroidNotificationService] Body: $body");
    debugPrint("[AndroidNotificationService] Time: $scheduledTime");

    // Enhanced notification details with more explicit sound settings
    final androidDetails = AndroidNotificationDetails(
      'medication_alarms_new3', // Updated channel id
      'Medication Alarms',
      channelDescription: 'Critical medication reminders',
      importance: Importance.max,
      priority: Priority.high,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true, // Make this true for better attention grabbing
      ongoing: false,
      autoCancel: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('medication_alarm'),
      setAsGroupSummary: false,
      groupKey: 'medication_alarms',
      channelShowBadge: true,
      visibility: NotificationVisibility.public,
      ticker: 'Medication Alarm',
      audioAttributesUsage: AudioAttributesUsage.alarm, // Important! Use alarm audio attributes
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('TAKE_ACTION', 'Take Now'),
        AndroidNotificationAction('SNOOZE_ACTION', 'Snooze (5 min)'),
      ],
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: null, // Only Android details
    );

    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
    final tzNow = tz.TZDateTime.now(tz.local);

    tz.TZDateTime effectiveScheduledTime = tzTime;

    if (repeatInterval != null && tzTime.isBefore(tzNow)) {
      effectiveScheduledTime = _adjustTimeForRepeat(tzNow, scheduledTime, repeatInterval);
      debugPrint("[AndroidNotificationService] Adjusted time for repeat: $effectiveScheduledTime");
    }
    else if (repeatInterval == null && tzTime.isBefore(tzNow.subtract(const Duration(seconds: 1)))) {
      debugPrint("[AndroidNotificationService] Skipping past notification");
      return;
    }

    try {
      DateTimeComponents? matchDateTimeComponents;
      if (repeatInterval == RepeatInterval.daily) {
        matchDateTimeComponents = DateTimeComponents.time;
      } else if (repeatInterval == RepeatInterval.weekly) {
        matchDateTimeComponents = DateTimeComponents.dayOfWeekAndTime;
      }

      debugPrint("[AndroidNotificationService] Final scheduled time: $effectiveScheduledTime");
      debugPrint("[AndroidNotificationService] Now sending zonedSchedule request...");

      // First, check if a previous notification with same ID exists and cancel it
      await _notificationsPlugin.cancel(id);

      // Schedule the new notification
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        effectiveScheduledTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: medicationId,
        matchDateTimeComponents: matchDateTimeComponents,
      );
      
      debugPrint("[AndroidNotificationService] Notification scheduled successfully");
      
      // For test notifications (like from the test button), also create an immediate notification
      if (title.contains("اختبار") && effectiveScheduledTime.isAfter(tzNow) && 
          effectiveScheduledTime.difference(tzNow).inSeconds < 10) {
        debugPrint("[AndroidNotificationService] This appears to be a test notification");
        
        // Create a new instance instead of using copyWith
        final androidTestDetails = AndroidNotificationDetails(
          'medication_alarms_new3',
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
          sound: const RawResourceAndroidNotificationSound('medication_alarm'),
          setAsGroupSummary: false,
          groupKey: 'medication_alarms',
          channelShowBadge: true,
          visibility: NotificationVisibility.public,
          ticker: 'Medication Alarm - Immediate Test',
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableLights: true,  // These properties are different from the original
          ledColor: Colors.red, // These properties are different from the original
          ledOnMs: 1000,       // These properties are different from the original
          ledOffMs: 500,       // These properties are different from the original
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction('TAKE_ACTION', 'Take Now'),
            AndroidNotificationAction('SNOOZE_ACTION', 'Snooze (5 min)'),
          ],
        );
        
        final testDetails = NotificationDetails(
          android: androidTestDetails,
          iOS: null,
        );
        
        // Create an immediate notification with a different ID
        await _notificationsPlugin.show(
          id + 1, // Different ID to avoid conflict
          "🔊 اختبار الصوت الفوري",
          "هذا اختبار للتحقق من تشغيل الصوت. يجب أن تسمع صوتًا الآن.",
          testDetails,
          payload: medicationId,
        );
        
        debugPrint("[AndroidNotificationService] Immediate test notification sent");
      }

      // Verify pending notifications
      final pendingNotifications = await _notificationsPlugin.pendingNotificationRequests();
      debugPrint("[AndroidNotificationService] Pending notifications count: ${pendingNotifications.length}");
      
    } catch (e, stackTrace) {
      debugPrint("[AndroidNotificationService] Error scheduling alarm $id: $e");
      debugPrint(stackTrace.toString());
    }
  }

  // Helper method to adjust time for repeat intervals
  tz.TZDateTime _adjustTimeForRepeat(
    tz.TZDateTime now, 
    DateTime scheduledTime, 
    RepeatInterval repeatInterval
  ) {
    final TimeOfDay timeOfDay = TimeOfDay.fromDateTime(scheduledTime);
    
    if (repeatInterval == RepeatInterval.daily) {
      return _nextInstanceOfTime(now.toLocal(), timeOfDay);
    } else if (repeatInterval == RepeatInterval.weekly) {
      return _nextInstanceOfWeekday(now.toLocal(), scheduledTime.weekday, timeOfDay);
    }
    
    return now.add(const Duration(minutes: 1)); // Fallback
  }

  tz.TZDateTime _nextInstanceOfTime(DateTime from, TimeOfDay tod) {
    final tz.TZDateTime tzFrom = tz.TZDateTime.from(from, tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local, tzFrom.year, tzFrom.month, tzFrom.day, tod.hour, tod.minute);
    if (!scheduledDate.isAfter(tzFrom.subtract(const Duration(seconds: 1)))) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  tz.TZDateTime _nextInstanceOfWeekday(DateTime from, int weekday, TimeOfDay tod) {
    final tz.TZDateTime tzFrom = tz.TZDateTime.from(from, tz.local);
    tz.TZDateTime scheduledDate = _nextInstanceOfTime(from, tod);
    while (scheduledDate.weekday != weekday) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
  
  @override
  Future<void> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
    } catch(e) {
      debugPrint("[AndroidNotificationService] Error canceling notification $id: $e");
    }
  }
  
  @override
  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch(e) {
      debugPrint("[AndroidNotificationService] Error canceling all notifications: $e");
    }
  }
  
  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      return await _notificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint("[AndroidNotificationService] Error retrieving pending notifications: $e");
      return [];
    }
  }
  
  @override
  Future<bool?> checkNotificationPermissions() async {
    try {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await androidPlugin?.areNotificationsEnabled();
    } catch (e) {
      debugPrint("[AndroidNotificationService] Error checking notification permissions: $e");
      return false;
    }
  }
}

