import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';

import 'notification_service.dart';

class AlarmNotificationHelper {
  static final NotificationService _service = NotificationService();
  static FlutterLocalNotificationsPlugin get notificationsPlugin => _service.notificationsPlugin;
  static bool _isInitialized = false;
  static final DateFormat _logDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS ZZZZ');


  static Future<void> initialize(BuildContext? context) async {
    if (context != null) {
      await _initializeWithContext(context);
    } else {
      print("[AlarmHelper Init] Timezone data should be ready. Waiting for context...");
    }
    await ensureChannelsSetup();
  }

  static Future<void> completeInitialization(BuildContext context) async {
    if (!_isInitialized) {
      print("[AlarmHelper Init] Completing initialization with context.");
      await _initializeWithContext(context);
      await checkAndLogPermissions();
    }
  }

  static Future<void> _initializeWithContext(BuildContext context) async {
    print("[AlarmHelper Init] Initializing notification service with context.");
    await _service.initialize(
        context,
        _onNotificationResponse,
        notificationTapBackground
    );
    _isInitialized = true;
    print("[AlarmHelper Init] Notification service initialized.");
  }

  static Future<void> ensureChannelsSetup() async {
    print("[AlarmHelper Setup] Ensuring notification channels are set up...");
    await _service.setupNotificationChannels();
    print("[AlarmHelper Setup] Channel setup called.");
  }

  static Future<void> checkAndLogPermissions() async {
    try {
      bool? granted = await _service.checkNotificationPermissions();
      print("[AlarmHelper Perms] Notification permission status: $granted");
      if (granted == false) {
        print("[AlarmHelper Perms] WARNING: Notifications permission not granted!");
      }
    } catch (e) {
      print("[AlarmHelper Perms] Error checking notification permissions: $e");
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    final id = response.id ?? 0;
    final actionId = response.actionId ?? 'TAP';
    final timestamp = _logDateFormat.format(DateTime.now());

    print("--------------------------------------------------");
    print("[AlarmHelper FOREGROUND Callback] Timestamp: $timestamp");
    print("[AlarmHelper FOREGROUND Callback] Notification Interaction Received:");
    print("[AlarmHelper FOREGROUND Callback]   ID: $id");
    print("[AlarmHelper FOREGROUND Callback]   Action ID: $actionId");
    print("[AlarmHelper FOREGROUND Callback]   Payload: $payload");
    print("--------------------------------------------------");


    if (payload.isEmpty) {
      print("[AlarmHelper FOREGROUND Callback] Payload is empty, ignoring.");
      return;
    }

    if (payload.startsWith('companion_check_')) {
      print("[AlarmHelper FOREGROUND Callback] Handling companion check payload: $payload");
      _navigateToCompanionsPage();
      return;
    } else if (payload.startsWith('companion_missed_')) {
      print("[AlarmHelper FOREGROUND Callback] Handling companion missed payload: $payload");
      _navigateToCompanionsPage();
      return;
    }

    if (response.actionId == 'TAKE_ACTION') {
      print("[AlarmHelper FOREGROUND Callback] Handling TAKE_ACTION for payload: $payload");
      _navigateToMedicationDetail(payload, markAsTaken: true);
    } else if (response.actionId == 'SNOOZE_ACTION') {
      print("[AlarmHelper FOREGROUND Callback] Handling SNOOZE_ACTION for payload: $payload, id: $id");
      _handleSnooze(id, payload);
    } else {
      print("[AlarmHelper FOREGROUND Callback] Handling default tap for payload: $payload");
      _navigateToMedicationDetail(payload);
    }
  }

  static Future<void> _navigateToCompanionsPage() async {
    print("[AlarmHelper Nav] Attempting to navigate to companions page.");
    if (navigatorKey.currentState == null) {
      print("[AlarmHelper Nav] Navigator key is null, cannot navigate.");
      return;
    }
    try {
      await navigatorKey.currentState?.pushNamed('/companions');
      print("[AlarmHelper Nav] Navigation to /companions successful.");
    } catch (e) {
      print("[AlarmHelper Nav] Error navigating to /companions: $e");
    }
  }


  static Future<void> _navigateToMedicationDetail(String medicationId, {bool markAsTaken = false}) async {
    print("[AlarmHelper Nav] Attempting to navigate to /medication_detail for ID: $medicationId, markAsTaken: $markAsTaken");
    if (medicationId.isEmpty) {
      print("[AlarmHelper Nav] Medication ID is empty, cannot navigate.");
      return;
    }

    if (navigatorKey.currentState == null || navigatorKey.currentContext == null) {
      print("[AlarmHelper Nav] Navigator state or context is null, cannot navigate.");
      return;
    }

    try {
      final currentRoute = ModalRoute.of(navigatorKey.currentContext!);
      if (currentRoute?.settings.name == '/medication_detail') {
        final args = currentRoute?.settings.arguments as Map?;
        if (args?['docId'] == medicationId) {
          print("[AlarmHelper Nav] Already on the detail page for $medicationId, skipping navigation.");
          return;
        }
      }

      print("[AlarmHelper Nav] Pushing /medication_detail route for $medicationId");
      await navigatorKey.currentState?.pushNamed(
        '/medication_detail',
        arguments: {
          'docId': medicationId,
          'fromNotification': true,
          'needsConfirmation': !markAsTaken,
          'autoMarkAsTaken': markAsTaken,
        },
      );
      print("[AlarmHelper Nav] Navigation to /medication_detail successful.");

    } catch (e, stackTrace) {
      print("[AlarmHelper Nav] Error navigating to medication detail: $e\n$stackTrace");
    }
  }

  static Future<void> _handleSnooze(int originalId, String medicationId) async {
    const Duration snoozeDuration = Duration(minutes: 5);
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    final tz.TZDateTime snoozeTime = now.add(snoozeDuration);

    final int newId = generateNotificationId(medicationId, snoozeTime.toUtc()) ^ 0x1A2B3C4D;
    print("[AlarmHelper Snooze] Original ID: $originalId, Scheduling Snooze ID: $newId for time: ${_logDateFormat.format(snoozeTime)}");


    try {
      await scheduleAlarmNotification(
        id: newId,
        title: '⏰ تم التأجيل: تناول الدواء',
        body: 'تذكير بتناول دوائك $medicationId (تم التأجيل).',
        scheduledTime: snoozeTime,
        medicationId: medicationId,
        isSnoozed: true,
        isCompanionCheck: false,
        repeatInterval: null,
      );
      print("[AlarmHelper Snooze] Successfully scheduled snoozed notification $newId");
    } catch (e) {
      debugPrint("[AlarmHelper Snooze] Error scheduling snoozed notification $newId: $e");
    }
  }

  static Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
    required String medicationId,
    bool isSnoozed = false,
    required bool isCompanionCheck,
    RepeatInterval? repeatInterval,
  }) async {
    print("[AlarmHelper Schedule] Requesting schedule for ID: $id, Time: ${_logDateFormat.format(scheduledTime)}, MedID: $medicationId, Companion: $isCompanionCheck, Snoozed: $isSnoozed, Repeat: $repeatInterval");
    try {
      await _service.scheduleAlarmNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledTime,
        medicationId: medicationId,
        isSnoozed: isSnoozed,
        isCompanionCheck: isCompanionCheck,
        repeatInterval: repeatInterval,
      );
      print("[AlarmHelper Schedule] Service call successful for ID: $id");
    } catch (e, stackTrace) {
      print("[AlarmHelper Schedule] Service call FAILED for ID: $id - $e\n$stackTrace");
    }
  }

  static Future<void> scheduleDailyRepeatingNotification({
    required int id,
    required String title,
    required String body,
    required TimeOfDay timeOfDay,
    required String payload,
    required DateTime startDate,
  }) async {
    final tz.TZDateTime firstOccurrence = _nextInstanceOfTime(startDate, timeOfDay);
    print("[AlarmHelper Schedule] Daily Repeating ID: $id, First Occurrence: ${_logDateFormat.format(firstOccurrence)}");
    return scheduleAlarmNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: firstOccurrence,
      medicationId: payload,
      isCompanionCheck: false,
      repeatInterval: RepeatInterval.daily,
    );
  }

  static Future<void> scheduleWeeklyRepeatingNotification({
    required int id,
    required String title,
    required String body,
    required int weekday,
    required TimeOfDay timeOfDay,
    required String payload,
    required DateTime startDate,
  }) async {
    final tz.TZDateTime firstOccurrence = _nextInstanceOfWeekday(startDate, weekday, timeOfDay);
    print("[AlarmHelper Schedule] Weekly Repeating ID: $id, First Occurrence: ${_logDateFormat.format(firstOccurrence)}");
    return scheduleAlarmNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: firstOccurrence,
      medicationId: payload,
      isCompanionCheck: false,
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
    print("[AlarmHelper Cancel] Canceling notification ID: $id");
    await _service.cancelNotification(id);
  }

  static Future<void> cancelAllNotifications() async {
    print("[AlarmHelper Cancel] Canceling ALL notifications.");
    await _service.cancelAllNotifications();
  }

  static Future<void> logPendingNotifications() async {
    try {
      final List<PendingNotificationRequest> pendingRequests = await _service.getPendingNotifications();
      print("--------------------------------------------------");
      print("[AlarmHelper Pending] Pending Notification Requests (${pendingRequests.length}):");
      if (pendingRequests.isEmpty) {
        print("[AlarmHelper Pending]   None");
      } else {
        for (var req in pendingRequests) {
          print("[AlarmHelper Pending]   ID: ${req.id}, Title: ${req.title}, Body: ${req.body}, Payload: ${req.payload}");
        }
      }
      print("--------------------------------------------------");
    } catch (e) {
      print("[AlarmHelper Pending] Error fetching pending notifications: $e");
    }
  }


  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return _service.getPendingNotifications();
  }

  static Future<bool?> checkForNotificationPermissions() async {
    return _service.checkNotificationPermissions();
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = response.payload ?? '';
  final id = response.id ?? 0;
  final actionId = response.actionId ?? 'TAP';
  final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS ZZZZ').format(DateTime.now());

  print("--------------------------------------------------");
  print("[AlarmHelper BACKGROUND Callback] Timestamp: $timestamp");
  print("[AlarmHelper BACKGROUND Callback] Notification Interaction Received:");
  print("[AlarmHelper BACKGROUND Callback]   ID: $id");
  print("[AlarmHelper BACKGROUND Callback]   Action ID: $actionId");
  print("[AlarmHelper BACKGROUND Callback]   Payload: $payload");
  print("--------------------------------------------------");

}