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
    print("[AndroidNotificationService] Initializing...");
    final androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    print("[AndroidNotificationService] Created Android initialization settings");
    
    final initSettings = InitializationSettings(android: androidInit, iOS: null);
    
    try {
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
      );
      print("[AndroidNotificationService] Plugin initialized successfully");
    } catch (e) {
      print("[AndroidNotificationService] ERROR initializing plugin: $e");
    }
    
    await setupNotificationChannels();
    await requestPermissions();
    print("[AndroidNotificationService] Initialization complete");
  }

  @override
  Future<void> setupNotificationChannels() async {
    print("[AndroidNotificationService] Setting up notification channels...");
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin == null) {
      print("[AndroidNotificationService] Failed to get Android plugin implementation");
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
      );
      
      await androidPlugin.createNotificationChannel(alarmChannel);
      print("[AndroidNotificationService] Created main medication alarm channel");
      
      // Companion medication channel
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
      print("[AndroidNotificationService] Created companion medication channel");
      
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
      print("[AndroidNotificationService] Created test notification channel");
      
    } catch (e) {
      print("[AndroidNotificationService] ERROR creating notification channels: $e");
    }
  }

  @override
  Future<void> requestPermissions() async {
    print("[AndroidNotificationService] Checking notification permissions...");
    final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      try {
        final bool? areEnabled = await androidPlugin.areNotificationsEnabled();
        print("[AndroidNotificationService] Notifications enabled: $areEnabled");
      } catch (e) {
        print("[AndroidNotificationService] ERROR checking notification permissions: $e");
      }
    } else {
      print("[AndroidNotificationService] Android plugin implementation is null");
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
    print("[AndroidNotificationService] Scheduling notification ID $id for $scheduledTime");
    
    // Check if this is a special notification type
    final bool isTestNotification = title.contains("اختبار إشعار");
    final bool isCompanionNotification = title.contains("تذكير جرعة مرافق") || 
                                        medicationId.startsWith("companion_");
    
    // Choose the appropriate channel
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
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      ongoing: false,
      autoCancel: true,
      playSound: true,
      sound: isTestNotification ? null : RawResourceAndroidNotificationSound('medication_alarm'),
    );
    
    print("[AndroidNotificationService] Using channel: $channelId for notification ID $id");
    
    final details = NotificationDetails(android: androidDetails);
    
    try {
      // Ensure timezone database is initialized
      if (tz.local == null) {
         print("[AndroidNotificationService] Timezone database not initialized. Initializing now.");
         tz_init.initializeTimeZones();
      }

      // Convert the provided local DateTime to TZDateTime
      final tz.TZDateTime tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
      print("[AndroidNotificationService] Scheduling for: $tzTime");
      
      // Skip scheduling if time is in the past
      final now = tz.TZDateTime.now(tz.local);
      if (tzTime.isBefore(now)) {
        print("[AndroidNotificationService] Cannot schedule notification for past time: $tzTime");
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
      print("[AndroidNotificationService] Successfully scheduled notification ID $id for $tzTime");
    } catch (e, stackTrace) {
      print("[AndroidNotificationService] ERROR scheduling notification: $e");
      print("[AndroidNotificationService] Stack trace: $stackTrace");
      throw e;
    }
  }

  @override
  Future<void> cancelNotification(int id) async {
    print("[AndroidNotificationService] Cancelling notification ID: $id");
    await _notificationsPlugin.cancel(id);
  }

  @override
  Future<void> cancelAllNotifications() async {
    print("[AndroidNotificationService] Cancelling all notifications");
    await _notificationsPlugin.cancelAll();
  }

  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    final requests = await _notificationsPlugin.pendingNotificationRequests();
    print("[AndroidNotificationService] Found ${requests.length} pending notifications");
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
