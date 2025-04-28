import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';

// Import platform-specific service implementations
import 'notification_service.dart';
import 'companion_medication_tracker.dart';

class AlarmNotificationHelper {
  static final NotificationService _service = NotificationService();
  static FlutterLocalNotificationsPlugin get notificationsPlugin => _service.notificationsPlugin;
  static bool _isInitialized = false;

  static Future<void> initialize(BuildContext context) async {
    print("[AlarmNotificationHelper] Starting initialization...");
    tz_init.initializeTimeZones();
    print("[AlarmNotificationHelper] Time zones initialized");
    
    await _service.initialize(
        context,
        _onNotificationResponse,
        notificationTapBackground
    );
    print("[AlarmNotificationHelper] Service initialized");
    
    // Ensure channels are set up during initial initialization as well
    await ensureChannelsSetup();
    _isInitialized = true;
    print("[AlarmNotificationHelper] Initialization complete");
  }

  static Future<void> ensureChannelsSetup() async {
    print("[AlarmNotificationHelper] Setting up notification channels");
    // Call the platform-specific channel setup
    await _service.setupNotificationChannels();
    print("[AlarmNotificationHelper] Notification channels setup complete");
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    final id = response.id ?? 0;

    print("[AlarmNotificationHelper] Notification response received: payload=$payload, id=$id, actionId=${response.actionId}");

    if (payload.isEmpty) {
      print("[AlarmNotificationHelper] No payload found in notification response.");
      return;
    }

    if (payload.startsWith('companion_check_')) {
      print("[AlarmNotificationHelper] Processing companion check notification with payload: $payload");
      CompanionMedicationTracker.processCompanionDoseCheck(payload);
      return;
    } else if (payload.startsWith('companion_missed_')) {
      print("[AlarmNotificationHelper] Navigating to companions page due to missed dose notification.");
      _navigateToCompanionsPage(); // Ensure this navigates to the companion page
      return;
    }

    // Handle medication notifications
    if (response.actionId == 'TAKE_ACTION') {
      print("[AlarmNotificationHelper] Take action triggered for notification with payload: $payload");
      _navigateToMedicationDetail(payload, markAsTaken: true);
    } else if (response.actionId == 'SNOOZE_ACTION') {
      print("[AlarmNotificationHelper] Snooze action triggered for notification with payload: $payload");
      _handleSnooze(id, payload);
    } else {
      print("[AlarmNotificationHelper] Default action triggered for notification with payload: $payload");
      _navigateToMedicationDetail(payload);
    }
  }

  static Future<void> _navigateToCompanionsPage() async {
    if (navigatorKey.currentState == null) {
      print("[AlarmNotificationHelper] Navigator key is null, can't navigate to companions page");
      return;
    }

    print("[AlarmNotificationHelper] Navigating to companions page");
    navigatorKey.currentState?.pushNamed('/companions');
  }

  static Future<void> _navigateToMedicationDetail(String medicationId, {bool markAsTaken = false}) async {
    if (medicationId.isEmpty) {
      return;
    }

    try {
      if (navigatorKey.currentState?.canPop() ?? false) {
        final currentRoute = ModalRoute.of(navigatorKey.currentContext!)?.settings.name;
        if (currentRoute == '/medication_detail') {
          final args = ModalRoute.of(navigatorKey.currentContext!)?.settings.arguments as Map?;
          if (args?['docId'] == medicationId) {
            return;
          }
        }
      }

      await navigatorKey.currentState?.pushNamed(
        '/medication_detail',
        arguments: {
          'docId': medicationId,
          'fromNotification': true,
          'needsConfirmation': !markAsTaken,
          'autoMarkAsTaken': markAsTaken,
        },
      );

    } catch (e, stackTrace) {
      print("[AlarmNotificationHelper] Error navigating to medication detail: $e\n$stackTrace");
    }
  }

  static Future<void> _handleSnooze(int originalId, String medicationId) async {
    const Duration snoozeDuration = Duration(minutes: 5);
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    final tz.TZDateTime snoozeTime = now.add(snoozeDuration);

    final int newId = generateNotificationId(medicationId, snoozeTime.toUtc()) ^ 0x1A2B3C4D;

    try {
      await scheduleAlarmNotification(
        id: newId,
        title: '⏰ Snoozed: Take Medication',
        body: 'Reminder to take your $medicationId (snoozed).',
        scheduledTime: snoozeTime.toLocal(),
        medicationId: medicationId,
        isSnoozed: true,
        repeatInterval: null,
      );
    } catch (e) {
      print("[AlarmNotificationHelper] Error scheduling snoozed notification $newId: $e");
    }
  }

  static Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String medicationId,
    bool isSnoozed = false,
    bool isCompanionCheck = false,
    RepeatInterval? repeatInterval,
  }) async {
    if (!_isInitialized) {
      print("[AlarmNotificationHelper] WARNING: Trying to schedule notification before initialization!");
    }
    
    print("[AlarmNotificationHelper] Scheduling notification:");
    print("[AlarmNotificationHelper] - ID: $id");
    print("[AlarmNotificationHelper] - Title: $title");
    print("[AlarmNotificationHelper] - Body: $body");
    print("[AlarmNotificationHelper] - Time: $scheduledTime");
    print("[AlarmNotificationHelper] - Payload: $medicationId");
    print("[AlarmNotificationHelper] - Current time: ${DateTime.now()}");
    
    // --- For close time notifications, show immediately ---
    final now = DateTime.now();
    final int secondsDifference = scheduledTime.difference(now).inSeconds;
    
    // Show immediately if within 20 seconds
    if (secondsDifference < 20) {
      print("[AlarmNotificationHelper] Notification time within $secondsDifference seconds, showing immediately");
      
      final String channelId = 'medication_alarms_v2';
      final String channelName = 'Medication Alarms';

      try {
        await _service.notificationsPlugin.show(
          id,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: 'Critical medication reminders',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              enableLights: true,
              vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
              category: AndroidNotificationCategory.alarm,
              fullScreenIntent: true,
              autoCancel: true,
            ),
          ),
          payload: medicationId,
        );
        print("[AlarmNotificationHelper] Immediate notification sent successfully with ID: $id");
      } catch (e) {
        print("[AlarmNotificationHelper] ERROR showing immediate notification: $e");
      }
      return;
    }

    try {
      // Ensure the time is in the future
      if (scheduledTime.isBefore(DateTime.now())) {
        print("[AlarmNotificationHelper] WARNING: Cannot schedule notification for past time ($scheduledTime)");
        return;
      }
      
      await _service.scheduleAlarmNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        medicationId: medicationId,
        isSnoozed: isSnoozed,
        repeatInterval: repeatInterval,
      );
      print("[AlarmNotificationHelper] Future notification scheduled with ID: $id");
    } catch (e) {
      print("[AlarmNotificationHelper] ERROR scheduling notification: $e");
    }
  }

  static Future<void> scheduleDailyRepeatingNotification({
    required BuildContext context,
    required int id,
    required String title,
    required String body,
    required TimeOfDay timeOfDay,
    required String payload,
    required DateTime startDate,
  }) async {
    final firstOccurrence = _nextInstanceOfTime(startDate, timeOfDay);

    return scheduleAlarmNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: firstOccurrence.toLocal(),
      medicationId: payload,
      repeatInterval: RepeatInterval.daily,
    );
  }

  static Future<void> scheduleWeeklyRepeatingNotification({
    required BuildContext context,
    required int id,
    required String title,
    required String body,
    required int weekday,
    required TimeOfDay timeOfDay,
    required String payload,
    required DateTime startDate,
  }) async {
    final firstOccurrence = _nextInstanceOfWeekday(startDate, weekday, timeOfDay);

    return scheduleAlarmNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: firstOccurrence.toLocal(),
      medicationId: payload,
      repeatInterval: RepeatInterval.weekly,
    );
  }

  static tz.TZDateTime _nextInstanceOfTime(DateTime from, TimeOfDay tod) {
    final tz.TZDateTime tzFrom = tz.TZDateTime.from(from, tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, tzFrom.year, tzFrom.month, tzFrom.day, tod.hour, tod.minute);
    if (!scheduledDate.isAfter(tzFrom.subtract(const Duration(seconds: 1)))) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  static tz.TZDateTime _nextInstanceOfWeekday(DateTime from, int weekday, TimeOfDay tod) {
    final tz.TZDateTime tzFrom = tz.TZDateTime.from(from, tz.local);
    tz.TZDateTime scheduledDate = _nextInstanceOfTime(from, tod);
    while (scheduledDate.weekday != weekday) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  static int generateNotificationId(String docId, DateTime scheduledUtcTime) {
    final int docHash = docId.hashCode;
    final int timeHash = scheduledUtcTime.millisecondsSinceEpoch ~/ 1000;
    final int combinedHash = (docHash ^ timeHash) & 0x7FFFFFFF;
    return combinedHash;
  }

  static Future<void> cancelNotification(int id) async {
    print("[AlarmNotificationHelper] Cancelling notification with ID: $id");
    await _service.cancelNotification(id);
  }

  static Future<void> cancelAllNotifications() async {
    print("[AlarmNotificationHelper] Cancelling all notifications");
    await _service.cancelAllNotifications();
  }

  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    final list = await _service.getPendingNotifications();
    print("[AlarmNotificationHelper] Retrieved ${list.length} pending notifications");
    for (var req in list) {
      print("[AlarmNotificationHelper] Pending: ID=${req.id}, Title='${req.title}', Payload=${req.payload}");
    }
    return list;
  }

  static Future<bool?> checkForNotificationPermissions() async {
    final result = await _service.checkNotificationPermissions();
    print("[AlarmNotificationHelper] Notification permission status: $result");
    return result;
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final String? payload = response.payload;
  final String? actionId = response.actionId;
  final int? id = response.id;
  print("[BackgroundHandler] Notification tapped: id=$id, action=$actionId, payload=$payload");
}

