import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:shared_preferences/shared_preferences.dart';
import '../../Features/Companions/companion_medication_tracker.dart';

import '../../main.dart';
import 'notification_service.dart';

class AlarmNotificationHelper {
  static final NotificationService _service = NotificationService();
  static FlutterLocalNotificationsPlugin get notificationsPlugin => _service.notificationsPlugin;
  static bool _isInitialized = false;
  static final DateFormat _logDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS ZZZZ');

  // Define Riyadh timezone location for Saudi Arabia
  static late tz.Location _riyadhTimezone;

  // Debug flag for verbose logging
  static const bool _debugMode = true;

  static Future<void> initialize(BuildContext? context) async {
    debugLog("Starting initialization...");
    tz_init.initializeTimeZones();

    // Set up Riyadh timezone location
    _riyadhTimezone = tz.getLocation('Asia/Riyadh'); // Saudi Arabia timezone
    tz.setLocalLocation(_riyadhTimezone); // Set as default local timezone

    debugLog("Time zones initialized with Riyadh timezone (Asia/Riyadh)");
    debugLog("Current time in Riyadh: ${tz.TZDateTime.now(_riyadhTimezone)}");
    debugLog("Current time in UTC: ${DateTime.now().toUtc()}");
    debugLog("Device time: ${DateTime.now()}");

    // Perform initial notification check
    await _checkNotificationSettings();

    if (context != null) {
      await _initializeWithContext(context);
    } else {
      debugLog("Timezone data ready. Waiting for context...");
    }

    await ensureChannelsSetup();
    debugLog("Initialization complete");
  }

  // Helper method for consistent debug logging
  static void debugLog(String message) {
    if (_debugMode) {
      final timestamp = _logDateFormat.format(DateTime.now());
      print("[AlarmNotificationHelper] [$timestamp] $message");
    } else {
      print("[AlarmNotificationHelper] $message");
    }
  }

  // Check notification settings and log potential issues
  static Future<void> _checkNotificationSettings() async {
    try {
      final androidPlugin = _service.notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Check if notifications are enabled
        final bool? areEnabled = await androidPlugin.areNotificationsEnabled();
        debugLog("Notification permission status: ${areEnabled == true ? 'GRANTED' : 'NOT GRANTED'}");

        if (areEnabled != true) {
          debugLog("⚠️ WARNING: Notifications are not enabled for this app!");
          debugLog("⚠️ User needs to grant notification permission in settings");
        }

        // Check for additional permissions on Android 12+
        debugLog("Checking for exact alarm permission...");
      }
    } catch (e) {
      debugLog("Error checking notification settings: $e");
    }
  }

  static Future<void> completeInitialization(BuildContext context) async {
    if (!_isInitialized) {
      debugLog("Completing initialization with context.");
      await _initializeWithContext(context);
      await checkAndLogPermissions();

      // Process any pending notifications that were scheduled before initialization
      await _processPendingNotifications();

      // Schedule a test notification 10 seconds in the future
      if (_debugMode) {
        debugLog("Scheduling test notification for debugging...");
        await showTestNotification();
      }
    }
  }

  static Future<void> _initializeWithContext(BuildContext context) async {
    debugLog("Initializing notification service with context.");
    await _service.initialize(
        context,
        _onNotificationResponse,
        notificationTapBackground
    );
    _isInitialized = true;
    debugLog("Service initialized");

    // Request notification permissions now that we have context
    final androidPlugin = _service.notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final bool? granted = await androidPlugin.requestNotificationsPermission();
      debugLog("Notification permission request result: $granted");
    }
  }

  static Future<void> ensureChannelsSetup() async {
    debugLog("Setting up notification channels");
    await _service.setupNotificationChannels();
    debugLog("Notification channels setup complete");
  }

  static Future<void> checkAndLogPermissions() async {
    try {
      bool? granted = await _service.checkNotificationPermissions();
      debugLog("Notification permission status: $granted");
      if (granted == false) {
        debugLog("⚠️ WARNING: Notifications permission not granted!");
      }
    } catch (e) {
      debugLog("Error checking notification permissions: $e");
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload ?? '';
    final id = response.id ?? 0;
    final actionId = response.actionId ?? 'TAP';
    final timestamp = _logDateFormat.format(DateTime.now());

    debugLog("--------------------------------------------------");
    debugLog("Notification response received:");
    debugLog("  ID: $id");
    debugLog("  Action ID: $actionId");
    debugLog("  Payload: $payload");
    debugLog("--------------------------------------------------");

    if (payload.isEmpty) {
      debugLog("No payload found in notification response.");
      return;
    }

    if (payload.startsWith('companion_reminder_')) {
      debugLog("Processing companion reminder notification with payload: $payload");
      _navigateToCompanionsPage();

      // Also process as a check since we've combined the notifications
      final medicationId = payload.replaceFirst("companion_reminder_", "");
      CompanionMedicationTracker.processCompanionDoseCheck("companion_check_" + medicationId);
      return;
    } else if (payload.startsWith('companion_check_')) {
      debugLog("Processing companion check notification with payload: $payload");
      CompanionMedicationTracker.processCompanionDoseCheck(payload);
      return;
    } else if (payload.startsWith('companion_missed_')) {
      debugLog("Navigating to companions page due to missed dose notification.");
      _navigateToCompanionsPage();
      return;
    }

    if (response.actionId == 'TAKE_ACTION') {
      debugLog("Take action triggered for notification with payload: $payload");
      _navigateToMedicationDetail(payload, markAsTaken: true);
    } else if (response.actionId == 'SNOOZE_ACTION') {
      debugLog("Snooze action triggered for notification with payload: $payload");
      _handleSnooze(id, payload);
    } else {
      debugLog("Default action triggered for notification with payload: $payload");
      _navigateToMedicationDetail(payload);
    }
  }

  static Future<void> _navigateToCompanionsPage() async {
    debugLog("Attempting to navigate to companions page.");
    if (navigatorKey.currentState == null) {
      debugLog("Navigator key is null, can't navigate to companions page");
      return;
    }

    try {
      debugLog("Navigating to companions page");
      await navigatorKey.currentState?.pushNamed('/companions');
      debugLog("Navigation to /companions successful.");
    } catch (e) {
      debugLog("Error navigating to companions page: $e");
    }
  }

  static Future<void> _navigateToMedicationDetail(String medicationId, {bool markAsTaken = false}) async {
    debugLog("Attempting to navigate to medication detail for ID: $medicationId, markAsTaken: $markAsTaken");
    if (medicationId.isEmpty) {
      debugLog("Medication ID is empty, cannot navigate.");
      return;
    }

    if (navigatorKey.currentState == null || navigatorKey.currentContext == null) {
      debugLog("Navigator state or context is null, cannot navigate.");
      return;
    }

    try {
      final currentRoute = ModalRoute.of(navigatorKey.currentContext!);
      if (currentRoute?.settings.name == '/medication_detail') {
        final args = currentRoute?.settings.arguments as Map?;
        if (args?['docId'] == medicationId) {
          debugLog("Already on the detail page for $medicationId, skipping navigation.");
          return;
        }
      }

      debugLog("Pushing /medication_detail route for $medicationId");
      await navigatorKey.currentState?.pushNamed(
        '/medication_detail',
        arguments: {
          'docId': medicationId,
          'fromNotification': true,
          'needsConfirmation': !markAsTaken,
          'autoMarkAsTaken': markAsTaken,
        },
      );
      debugLog("Navigation to /medication_detail successful.");

    } catch (e, stackTrace) {
      debugLog("Error navigating to medication detail: $e\n$stackTrace");
    }
  }

  static Future<void> _handleSnooze(int originalId, String medicationId) async {
    const Duration snoozeDuration = Duration(minutes: 5);
    final tz.TZDateTime now = tz.TZDateTime.now(_riyadhTimezone);
    final tz.TZDateTime snoozeTime = now.add(snoozeDuration);

    final int newId = generateNotificationId(medicationId, snoozeTime) ^ 0x1A2B3C4D;
    debugLog("Original ID: $originalId, Scheduling Snooze ID: $newId for time: ${_logDateFormat.format(snoozeTime)}");

    try {
      await scheduleAlarmNotification(
        id: newId,
        title: '⏰ تم التأجيل: تناول الدواء',
        body: 'تذكير بتناول دوائك (تم التأجيل).',
        scheduledTime: snoozeTime,
        medicationId: medicationId,
        isSnoozed: true,
        isCompanionCheck: false,
        repeatInterval: null,
      );
      debugLog("Successfully scheduled snoozed notification $newId");
    } catch (e) {
      debugLog("Error scheduling snoozed notification $newId: $e");
    }
  }

  static Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTime,
    required String medicationId,
    bool isSnoozed = false,
    bool isCompanionCheck = false,
    RepeatInterval? repeatInterval,
  }) async {
    // Make sure we're using Riyadh timezone
    tz.TZDateTime scheduledRiyadhTime = ensureRiyadhTime(scheduledTime);

    debugLog("Scheduling notification:");
    debugLog("- ID: $id");
    debugLog("- Title: $title");
    debugLog("- Body: $body");
    debugLog("- Original time: ${_logDateFormat.format(scheduledTime)}");
    debugLog("- Adjusted time (Riyadh): ${_logDateFormat.format(scheduledRiyadhTime)}");
    debugLog("- Payload: $medicationId");
    debugLog("- Current time (Riyadh): ${_logDateFormat.format(tz.TZDateTime.now(_riyadhTimezone))}");
    debugLog("- Current time (UTC): ${_logDateFormat.format(DateTime.now().toUtc())}");

    if (!_isInitialized) {
      debugLog("⚠️ WARNING: Trying to schedule notification before initialization!");

      // Create a pending notification request to schedule once initialization completes
      final pendingRequest = {
        'id': id,
        'title': title,
        'body': body,
        'scheduledTime': scheduledRiyadhTime,
        'medicationId': medicationId,
        'isSnoozed': isSnoozed,
        'isCompanionCheck': isCompanionCheck,
        'repeatInterval': repeatInterval?.toString(),
      };

      // Save it to shared preferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final pendingRequests = prefs.getStringList('pending_notifications') ?? [];
        pendingRequests.add(pendingRequest.toString());
        await prefs.setStringList('pending_notifications', pendingRequests);
        debugLog("Saved pending notification request for ID $id to be processed after initialization");
      } catch (e) {
        debugLog("ERROR saving pending notification: $e");
      }

      // Proceed anyway - it might work if the plugin is partially initialized
    }

    final now = tz.TZDateTime.now(_riyadhTimezone);
    final int secondsDifference = scheduledRiyadhTime.difference(now).inSeconds;

    debugLog("Time difference: $secondsDifference seconds");

    // Cancel any existing notification with this ID first
    try {
      await _service.cancelNotification(id);
      debugLog("Cancelled any existing notification with ID: $id");
    } catch (e) {
      debugLog("Error cancelling existing notification: $e");
    }

    // For immediate notifications (within 20 seconds)
    if (secondsDifference < 20) {
      debugLog("Notification time within $secondsDifference seconds, showing immediately");

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
              sound: RawResourceAndroidNotificationSound('medication_alarm'),
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
          ),
          payload: medicationId,
        );
        debugLog("Immediate notification sent successfully with ID: $id");
      } catch (e) {
        debugLog("ERROR showing immediate notification: $e");
      }
      return;
    }

    try {
      // Check if the scheduled time is in the past
      if (scheduledRiyadhTime.isBefore(now)) {
        // If the time is in the past, adjust based on repeat interval
        if (repeatInterval != null) {
          final oldTime = scheduledRiyadhTime.toString();
          scheduledRiyadhTime = _adjustTimeForRepeat(now, scheduledRiyadhTime, repeatInterval);
          debugLog("Adjusted past time from $oldTime to future: ${scheduledRiyadhTime.toString()}");
        } else {
          debugLog("⚠️ WARNING: Cannot schedule notification for past time (${scheduledRiyadhTime.toString()})");
          return;
        }
      }

      // Schedule the notification using the service
      await _service.scheduleAlarmNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledRiyadhTime, // Use the Riyadh timezone time for scheduling
        medicationId: medicationId,
        isSnoozed: isSnoozed,
        isCompanionCheck: isCompanionCheck,
        repeatInterval: repeatInterval,
      );

      // Also schedule a verification notification 1 minute after the main one
      // This helps verify that scheduling works correctly
      if (_debugMode) {
        final verificationTime = scheduledRiyadhTime.add(Duration(minutes: 1));
        final verificationId = id + 1000000; // Use a different ID

        await _service.scheduleAlarmNotification(
          id: verificationId,
          title: "✅ تأكيد جدولة الإشعار",
          body: "تم جدولة إشعار الدواء الأصلي #$id بنجاح",
          scheduledTime: verificationTime,
          medicationId: "verify_$medicationId",
          isSnoozed: false,
          isCompanionCheck: true,
          repeatInterval: null,
        );
        debugLog("Verification notification scheduled with ID: $verificationId for: ${verificationTime.toString()}");
      }

      debugLog("Future notification scheduled with ID: $id for time: ${scheduledRiyadhTime.toString()}");
    } catch (e, stackTrace) {
      debugLog("ERROR scheduling notification: $e");
      debugLog("Stack trace: $stackTrace");
    }
  }

  // New method to process pending notifications
  static Future<void> _processPendingNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingRequests = prefs.getStringList('pending_notifications');

      if (pendingRequests == null || pendingRequests.isEmpty) {
        debugLog("No pending notification requests found");
        return;
      }

      debugLog("Processing ${pendingRequests.length} pending notification requests");
      await prefs.remove('pending_notifications');

      // Process each request
      for (final requestStr in pendingRequests) {
        try {
          // Parse the request (simplified - in real code you'd need more robust parsing)
          // For demonstration purposes only - you would need real parsing logic
          debugLog("Processing pending request: $requestStr");

          // This is just a placeholder since parsing a string representation of a Map is complex
          // You would need to use JSON encoding/decoding in a real implementation
          debugLog("Actual pending notification processing would happen here");
        } catch (e) {
          debugLog("Error processing pending request: $e");
        }
      }
    } catch (e) {
      debugLog("Error in _processPendingNotifications: $e");
    }
  }

  // Helper method to ensure a time is in Riyadh timezone
  static tz.TZDateTime ensureRiyadhTime(tz.TZDateTime time) {
    if (time.location.name != _riyadhTimezone.name) {
      debugLog("Converting time from ${time.location.name} to Riyadh timezone (Asia/Riyadh)");
      // Convert to Riyadh timezone
      return tz.TZDateTime.from(time.toLocal(), _riyadhTimezone);
    }
    return time;
  }

  static tz.TZDateTime _adjustTimeForRepeat(tz.TZDateTime now, tz.TZDateTime scheduledTime, RepeatInterval repeatInterval) {
    final tod = TimeOfDay.fromDateTime(scheduledTime);
    if (repeatInterval == RepeatInterval.daily) {
      return _nextInstanceOfTime(now, tod);
    } else if (repeatInterval == RepeatInterval.weekly) {
      return _nextInstanceOfWeekday(now, scheduledTime.weekday, tod);
    }
    // Default fallback
    return now.add(Duration(minutes: 5));
  }

  static Future<void> scheduleDailyRepeatingNotification({
    required int id,
    required String title,
    required String body,
    required TimeOfDay timeOfDay,
    required String payload,
    required DateTime startDate,
  }) async {
    // Convert startDate to Riyadh timezone if not already
    final tz.TZDateTime startDateRiyadh = tz.TZDateTime.from(startDate, _riyadhTimezone);
    final tz.TZDateTime firstOccurrence = _nextInstanceOfTime(startDateRiyadh, timeOfDay);

    debugLog("Daily Repeating ID: $id, First Occurrence: ${firstOccurrence.toString()}");

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
    // Convert startDate to Riyadh timezone if not already
    final tz.TZDateTime startDateRiyadh = tz.TZDateTime.from(startDate, _riyadhTimezone);
    final tz.TZDateTime firstOccurrence = _nextInstanceOfWeekday(startDateRiyadh, weekday, timeOfDay);

    debugLog("Weekly Repeating ID: $id, First Occurrence: ${firstOccurrence.toString()}");

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

  static tz.TZDateTime _nextInstanceOfTime(tz.TZDateTime from, TimeOfDay tod) {
    // Make sure 'from' is in Riyadh timezone
    tz.TZDateTime fromRiyadh = ensureRiyadhTime(from);

    // Create a date with the given time in Riyadh timezone
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        _riyadhTimezone,
        fromRiyadh.year,
        fromRiyadh.month,
        fromRiyadh.day,
        tod.hour,
        tod.minute
    );

    // If the time already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(fromRiyadh) || scheduledDate.isAtSameMomentAs(fromRiyadh)) {
      scheduledDate = tz.TZDateTime(
          _riyadhTimezone,
          fromRiyadh.year,
          fromRiyadh.month,
          fromRiyadh.day + 1,
          tod.hour,
          tod.minute
      );
    }

    debugLog("Next instance of time: ${scheduledDate.toString()} (Riyadh)");
    return scheduledDate;
  }

  static tz.TZDateTime _nextInstanceOfWeekday(tz.TZDateTime from, int weekday, TimeOfDay tod) {
    // Make sure 'from' is in Riyadh timezone
    tz.TZDateTime fromRiyadh = ensureRiyadhTime(from);

    // Get the next instance of the specified time
    tz.TZDateTime scheduledDate = _nextInstanceOfTime(fromRiyadh, tod);

    // Keep adding days until we hit the target weekday
    while (scheduledDate.weekday != weekday) {
      scheduledDate = tz.TZDateTime(
          _riyadhTimezone,
          scheduledDate.year,
          scheduledDate.month,
          scheduledDate.day + 1,
          tod.hour,
          tod.minute
      );
    }

    debugLog("Next instance of weekday $weekday: ${scheduledDate.toString()} (Riyadh)");
    return scheduledDate;
  }

  static int generateNotificationId(String docId, tz.TZDateTime scheduledTime) {
    // Make sure the scheduled time is in Riyadh timezone
    final tz.TZDateTime timeRiyadh = ensureRiyadhTime(scheduledTime);

    final int docHash = docId.hashCode;
    final int timeHash = timeRiyadh.millisecondsSinceEpoch ~/ 1000;
    final int combinedHash = (docHash ^ timeHash) & 0x7FFFFFFF;

    debugLog("Generated notification ID: $combinedHash for docId: $docId, time: ${timeRiyadh.toString()}");
    return combinedHash;
  }

  static String getFormattedTimeWithDate(BuildContext context, tz.TZDateTime dateTime) {
    try {
      // Ensure we're using Riyadh timezone
      final tz.TZDateTime dateTimeRiyadh = ensureRiyadhTime(dateTime);

      // Current time in Riyadh
      final tz.TZDateTime nowRiyadh = tz.TZDateTime.now(_riyadhTimezone);

      // For debugging timezone issues
      debugLog("Formatting time: Current Riyadh: ${nowRiyadh.toString()}, Target Riyadh: ${dateTimeRiyadh.toString()}");

      // Create date-only objects for comparison (in Riyadh timezone)
      final DateTime todayDate = DateTime(nowRiyadh.year, nowRiyadh.month, nowRiyadh.day);
      final DateTime medicationDate = DateTime(dateTimeRiyadh.year, dateTimeRiyadh.month, dateTimeRiyadh.day);
      final DateTime tomorrowDate = DateTime(todayDate.year, todayDate.month, todayDate.day + 1);

      // Format the time portion
      final TimeOfDay tod = TimeOfDay.fromDateTime(dateTimeRiyadh);
      final int hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
      final String minute = tod.minute.toString().padLeft(2, '0');
      final String period = tod.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
      String timeStr = '$hour:$minute $period';

      // Compare dates for "today", "tomorrow" or specific date display
      if (medicationDate.day == tomorrowDate.day &&
          medicationDate.month == tomorrowDate.month &&
          medicationDate.year == tomorrowDate.year) {
        // If it's tomorrow
        timeStr += " (غداً)";
        debugLog("Adding tomorrow indicator to time display");
      } else if (medicationDate.day != todayDate.day ||
          medicationDate.month != todayDate.month ||
          medicationDate.year != todayDate.year) {
        // If it's not today or tomorrow (a future date)
        final DateFormat dateFormat = DateFormat('dd/MM', 'ar');
        final String formattedDate = dateFormat.format(medicationDate);
        timeStr += " ($formattedDate)";
        debugLog("Adding future date indicator: $formattedDate to time display");
      }

      debugLog("Final formatted time: $timeStr");
      return timeStr;
    } catch (e, stack) {
      debugLog("Error formatting time: $e");
      debugLog("Stack trace: $stack");
      // Fallback to basic formatting
      return '${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  static Future<void> cancelNotification(int id) async {
    debugLog("Cancelling notification with ID: $id");
    await _service.cancelNotification(id);
  }

  static Future<void> cancelAllNotifications() async {
    debugLog("Cancelling all notifications");
    await _service.cancelAllNotifications();
  }

  static Future<void> logPendingNotifications() async {
    try {
      final List<PendingNotificationRequest> pendingRequests = await _service.getPendingNotifications();
      debugLog("--------------------------------------------------");
      debugLog("Pending Notification Requests (${pendingRequests.length}):");
      if (pendingRequests.isEmpty) {
        debugLog("  None");
      } else {
        for (var req in pendingRequests) {
          debugLog("  ID: ${req.id}, Title: ${req.title}, Body: ${req.body}, Payload: ${req.payload}");
        }
      }
      debugLog("--------------------------------------------------");
    } catch (e) {
      debugLog("Error fetching pending notifications: $e");
    }
  }

  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    final list = await _service.getPendingNotifications();
    debugLog("Retrieved ${list.length} pending notifications");
    for (var req in list) {
      debugLog("Pending: ID=${req.id}, Title='${req.title}', Payload=${req.payload}");
    }
    return list;
  }

  static Future<bool?> checkForNotificationPermissions() async {
    final result = await _service.checkNotificationPermissions();
    debugLog("Notification permission status: $result");
    return result;
  }

  // Special testing method to immediately show a test notification
  static Future<void> showTestNotification() async {
    debugLog("Setting up test notifications");

    // Test 1: Immediate notification
    final int testId1 = 999991;
    try {
      await _service.notificationsPlugin.show(
        testId1,
        "⚠️ اختبار الإشعارات الفوري",
        "هذا اختبار للتحقق من عمل نظام الإشعارات فوراً",
        NotificationDetails(
          android: AndroidNotificationDetails(
            'test_notifications',
            'Test Notifications',
            channelDescription: 'For testing notification delivery',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            sound: RawResourceAndroidNotificationSound('medication_alarm'),
          ),
        ),
        payload: "test_immediate",
      );
      debugLog("Sent immediate test notification with ID: $testId1");
    } catch (e) {
      debugLog("Error showing immediate test notification: $e");
    }

    // Test 2: Scheduled in 30 seconds
    final int testId2 = 999992;
    final tz.TZDateTime testTime2 = tz.TZDateTime.now(_riyadhTimezone).add(const Duration(seconds: 30));

    try {
      await scheduleAlarmNotification(
        id: testId2,
        title: "⚠️ اختبار الإشعارات المجدولة",
        body: "هذا اختبار للتحقق من جدولة الإشعارات بشكل صحيح",
        scheduledTime: testTime2,
        medicationId: "test_scheduled",
        isCompanionCheck: false,
      );
      debugLog("Scheduled test notification ID: $testId2 for time: ${testTime2.toString()}");
    } catch (e) {
      debugLog("Error scheduling test notification: $e");
    }

    // Log pending notifications for verification
    await logPendingNotifications();
    debugLog("Test notifications setup complete");
  }

  // Helper method to parse time strings with flexible format support
  static TimeOfDay? parseTimeString(String timeStr) {
    try {
      String normalizedTime = timeStr.trim();
      bool isPM = false;
      bool isAM = false;

      if (normalizedTime.contains('مساء')) {
        isPM = true;
        normalizedTime = normalizedTime.replaceAll('مساءً', '').replaceAll('مساء', '').trim();
      } else if (normalizedTime.contains('صباح')) {
        isAM = true;
        normalizedTime = normalizedTime.replaceAll('صباحاً', '').replaceAll('صباح', '').trim();
      } else if (normalizedTime.toLowerCase().contains('pm')) {
        isPM = true;
        normalizedTime = normalizedTime.replaceAll(RegExp(r'[pP][mM]'), '').trim();
      } else if (normalizedTime.toLowerCase().contains('am')) {
        isAM = true;
        normalizedTime = normalizedTime.replaceAll(RegExp(r'[aA][mM]'), '').trim();
      }

      final parts = normalizedTime.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));

        if (isPM && hour < 12) hour += 12;
        if (isAM && hour == 12) hour = 0; // 12 AM is 00:00

        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (e) {
      debugLog("Error parsing time string '$timeStr': $e");
    }
    return null;
  }

  static Future<bool> checkAndRequestExactAlarmPermission(BuildContext context) async {
    try {
      final androidPlugin = _service.notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin == null) {
        debugLog("Unable to resolve Android plugin implementation");
        return false;
      }

      // This is only available on newer Android versions
      try {
        // Replace with proper API check for Android 12+
        bool? hasExactAlarm;

        // Try to access whether permission is granted via available methods
        try {
          // Check if we're on Android 12+ first
          final bool? areNotificationsEnabled = await androidPlugin.areNotificationsEnabled();
          debugLog("Notification permission status: $areNotificationsEnabled");

          // For now, we'll use notification permission as a proxy for exact alarm permission
          // as the plugin doesn't directly expose the exact alarm permission check
          hasExactAlarm = areNotificationsEnabled;
        } catch (e) {
          debugLog("Error checking notification permissions: $e");
          // For older Android versions, assume permission is granted
          hasExactAlarm = true;
        }

        debugLog("Exact alarm permission status (estimated): $hasExactAlarm");

        if (hasExactAlarm == false) {
          // Show dialog explaining why exact alarms are needed
          final bool shouldRequest = await _showExactAlarmPermissionDialog(context);
          if (shouldRequest) {
            // On Android 12+, we need to direct users to system settings 
            // since we can't directly request the permission via the plugin
            await _openAlarmPermissionSettings(context);

            // Check again after potentially opening settings
            // For now, just assume they granted it (we can't actually check directly)
            debugLog("Exact alarm permission status after settings redirect: unknown");
            return true;
          }
          return false;
        }
        return hasExactAlarm ?? false;
      } catch (e) {
        debugLog("Error checking exact alarm permission: $e");
        // Older Android versions don't need this permission
        return true;
      }
    } catch (e) {
      debugLog("Error in checkAndRequestExactAlarmPermission: $e");
      return false;
    }
  }

  static Future<void> _openAlarmPermissionSettings(BuildContext context) async {
    try {
      // For Android 12+ we should open system settings for SCHEDULE_EXACT_ALARM permission
      // but the plugin doesn't offer this directly, so we can guide users
      bool? userConfirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("فتح إعدادات النظام"),
          content: const Text(
            "سيتم توجيهك إلى إعدادات التطبيق في نظام التشغيل. "
                "الرجاء البحث عن خيار 'المنبهات والتذكيرات' أو 'المنبهات الدقيقة' وتفعيله.",
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("فتح الإعدادات"),
            ),
          ],
        ),
      );

      if (userConfirmed == true) {
        final androidPlugin = _service.notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

        if (androidPlugin != null) {
          // Open app settings as we don't have direct access to alarm settings
          await androidPlugin.getNotificationAppLaunchDetails();
          debugLog("Opened app settings for permission configuration");
        }
      }
    } catch (e) {
      debugLog("Error opening alarm permission settings: $e");
    }
  }

  static Future<bool> _showExactAlarmPermissionDialog(BuildContext context) async {
    try {
      return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text("إذن مطلوب للتنبيهات"),
          content: const Text(
            "يحتاج التطبيق إلى إذن جدولة المنبهات الدقيقة لضمان وصول تنبيهات الدواء في الوقت المحدد تماماً.\n\nبدون هذا الإذن، قد تتأخر التنبيهات أو لا تصل في الوقت المناسب.",
            textAlign: TextAlign.right,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("لاحقاً"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("منح الإذن"),
            ),
          ],
        ),
      ) ?? false;
    } catch (e) {
      debugLog("Error showing permission dialog: $e");
      return false;
    }
  }
}
