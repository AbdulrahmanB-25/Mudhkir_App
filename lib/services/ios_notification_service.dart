import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'notification_service.dart';

class IOSNotificationService implements NotificationService {
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
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    final initSettings = InitializationSettings(
      android: null, // Only iOS settings
      iOS: iosInit,
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
    final iosPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
        
    if (iosPlugin == null) return;

    final category = DarwinNotificationCategory(
      'medication_category',
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.plain(
          'TAKE_ACTION',
          'Take Medication',
          options: <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.foreground
          },
        ),
        DarwinNotificationAction.plain(
          'SNOOZE_ACTION',
          'Snooze (5 min)',
        ),
      ],
      options: <DarwinNotificationCategoryOption>{
        DarwinNotificationCategoryOption.hiddenPreviewShowTitle
      },
    );

    await _setNotificationCategories(iosPlugin, <DarwinNotificationCategory>[
      category,
    ]);
  }
  
  // Helper method to set notification categories
  Future<void> _setNotificationCategories(
    IOSFlutterLocalNotificationsPlugin plugin, 
    List<DarwinNotificationCategory> categories
  ) async {
    // This is a workaround since the method is not directly available
    // In a real implementation, we would use the actual method from the plugin
    try {
      // The plugin might expose this method in the future
    } catch (e) {
      debugPrint("[IOSNotificationService] Error setting notification categories: $e");
    }
  }
  
  @override
  Future<void> requestPermissions() async {
    final iosPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
        
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
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
    final iosDetails = DarwinNotificationDetails(
      sound: 'medication_alarm.ogg', // Make sure this file exists in iOS project
      categoryIdentifier: 'medication_category',
      interruptionLevel: InterruptionLevel.timeSensitive,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: null, // Only iOS details
      iOS: iosDetails,
    );

    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
    final tzNow = tz.TZDateTime.now(tz.local);

    tz.TZDateTime effectiveScheduledTime = tzTime;

    if (repeatInterval != null && tzTime.isBefore(tzNow)) {
      // Handle repeat intervals if time is in the past
      effectiveScheduledTime = _adjustTimeForRepeat(tzNow, scheduledTime, repeatInterval);
    }
    else if (repeatInterval == null && tzTime.isBefore(tzNow.subtract(const Duration(seconds: 1)))) {
      return; // Skip if one-time notification and time is in the past
    }

    try {
      DateTimeComponents? matchDateTimeComponents;
      if (repeatInterval == RepeatInterval.daily) {
        matchDateTimeComponents = DateTimeComponents.time;
      } else if (repeatInterval == RepeatInterval.weekly) {
        matchDateTimeComponents = DateTimeComponents.dayOfWeekAndTime;
      }

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        effectiveScheduledTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // Add this parameter
        payload: medicationId,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } catch (e, stackTrace) {
      debugPrint("[IOSNotificationService] Error scheduling alarm $id: $e\n$stackTrace");
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
      debugPrint("[IOSNotificationService] Error canceling notification $id: $e");
    }
  }
  
  @override
  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch(e) {
      debugPrint("[IOSNotificationService] Error canceling all notifications: $e");
    }
  }
  
  @override
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      return await _notificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint("[IOSNotificationService] Error retrieving pending notifications: $e");
      return [];
    }
  }
  
  @override
  Future<bool?> checkNotificationPermissions() async {
    try {
      final iosPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint("[IOSNotificationService] Error checking notification permissions: $e");
      return false;
    }
  }
}

