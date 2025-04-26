import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

// Import platform-specific service implementations
import 'notification_service.dart';

class AlarmNotificationHelper {
  static final NotificationService _service = NotificationService();
  static FlutterLocalNotificationsPlugin get notificationsPlugin => _service.notificationsPlugin;
  static bool _isInitialized = false;

  static Future<void> initialize(BuildContext? context) async {
    tz_init.initializeTimeZones();

    // Only proceed with context-dependent initialization if context is provided
    if (context != null) {
      await _initializeWithContext(context);
    } else {
      print("[AlarmNotificationHelper] Initialized timezone data. Will complete setup when context is available.");
    }

    // Channels setup doesn't require context
    await ensureChannelsSetup();
  }

  // Method to complete initialization when context is available
  static Future<void> completeInitialization(BuildContext context) async {
    if (!_isInitialized) {
      await _initializeWithContext(context);
      print("[AlarmNotificationHelper] Initialization completed with context.");
    }
  }

  // Private method to handle context-dependent initialization
  static Future<void> _initializeWithContext(BuildContext context) async {
    await _service.initialize(
        context,
        _onNotificationResponse,
        notificationTapBackground
    );
    _isInitialized = true;
  }

  static Future<void> ensureChannelsSetup() async {
    // Call the platform-specific channel setup
    await _service.setupNotificationChannels();
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    final id = response.id ?? 0;

    if (payload.isEmpty) {
      return;
    }

    if (response.actionId == 'TAKE_ACTION') {
      _navigateToMedicationDetail(payload, markAsTaken: true);
    } else if (response.actionId == 'SNOOZE_ACTION') {
      _handleSnooze(id, payload);
    } else {
      _navigateToMedicationDetail(payload);
    }
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
      debugPrint("[AlarmHelper] Error navigating to medication detail: $e\n$stackTrace");
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
      debugPrint("[AlarmHelper] Error scheduling snoozed notification $newId: $e");
    }
  }

  static Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String medicationId,
    bool isSnoozed = false,
    RepeatInterval? repeatInterval,
  }) async {
    return _service.scheduleAlarmNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
      medicationId: medicationId,
      isSnoozed: isSnoozed,
      repeatInterval: repeatInterval,
    );
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
    return _service.cancelNotification(id);
  }

  static Future<void> cancelAllNotifications() async {
    return _service.cancelAllNotifications();
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
  final String? payload = response.payload;
  final String? actionId = response.actionId;
  final int? id = response.id;
  print("[Background] Notification tapped: id=$id, action=$actionId, payload=$payload");
}
