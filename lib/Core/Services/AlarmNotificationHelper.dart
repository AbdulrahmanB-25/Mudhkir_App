import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../Features/Companions/companion_medication_tracker.dart';

import '../../main.dart';
import 'notification_service.dart';

class AlarmNotificationHelper {
  static final NotificationService _service = NotificationService();
  static FlutterLocalNotificationsPlugin get notificationsPlugin => _service.notificationsPlugin;
  static bool _isInitialized = false;
  static final DateFormat _logDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS ZZZZ');

  // Define UTC+3 timezone location for Saudi Arabia
  static late tz.Location _utcPlus3Location;

  // Debug flag for verbose logging
  static const bool _debugMode = true;

  static Future<void> initialize(BuildContext? context) async {
    debugLog("Starting initialization...");
    tz_init.initializeTimeZones();

    // Set up UTC+3 timezone location
    _utcPlus3Location = tz.getLocation('Asia/Riyadh'); // Saudi Arabia is UTC+3
    tz.setLocalLocation(_utcPlus3Location); // Set as default local timezone

    debugLog("Time zones initialized with UTC+3 (Asia/Riyadh)");
    debugLog("Current time in UTC+3: ${tz.TZDateTime.now(_utcPlus3Location)}");
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

    if (payload.startsWith('companion_check_')) {
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
    final tz.TZDateTime now = tz.TZDateTime.now(_utcPlus3Location);
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
    // Make sure we're using UTC+3 time
    tz.TZDateTime scheduledUtcPlus3 = ensureUtcPlus3Time(scheduledTime);

    debugLog("Scheduling notification:");
    debugLog("- ID: $id");
    debugLog("- Title: $title");
    debugLog("- Body: $body");
    debugLog("- Original time: ${_logDateFormat.format(scheduledTime)}");
    debugLog("- Adjusted time (UTC+3): ${_logDateFormat.format(scheduledUtcPlus3)}");
    debugLog("- Payload: $medicationId");
    debugLog("- Current time (UTC+3): ${_logDateFormat.format(tz.TZDateTime.now(_utcPlus3Location))}");
    debugLog("- Current time (UTC): ${_logDateFormat.format(DateTime.now().toUtc())}");

    if (!_isInitialized) {
      debugLog("⚠️ WARNING: Trying to schedule notification before initialization!");
      
      // Create a pending notification request to schedule once initialization completes
      final pendingRequest = {
        'id': id,
        'title': title,
        'body': body,
        'scheduledTime': scheduledUtcPlus3,
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

    final now = tz.TZDateTime.now(_utcPlus3Location);
    final int secondsDifference = scheduledUtcPlus3.difference(now).inSeconds;

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
      if (scheduledUtcPlus3.isBefore(now)) {
        // If the time is in the past, adjust based on repeat interval
        if (repeatInterval != null) {
          final oldTime = scheduledUtcPlus3.toString();
          scheduledUtcPlus3 = _adjustTimeForRepeat(now, scheduledUtcPlus3, repeatInterval);
          debugLog("Adjusted past time from $oldTime to future: ${scheduledUtcPlus3.toString()}");
        } else {
          debugLog("⚠️ WARNING: Cannot schedule notification for past time (${scheduledUtcPlus3.toString()})");
          return;
        }
      }

      // Schedule the notification using the service
      await _service.scheduleAlarmNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledUtcPlus3, // Use the UTC+3 time for scheduling
        medicationId: medicationId,
        isSnoozed: isSnoozed,
        isCompanionCheck: isCompanionCheck,
        repeatInterval: repeatInterval,
      );

      // Also schedule a verification notification 1 minute after the main one
      // This helps verify that scheduling works correctly
      if (_debugMode) {
        final verificationTime = scheduledUtcPlus3.add(Duration(minutes: 1));
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

      debugLog("Future notification scheduled with ID: $id for time: ${scheduledUtcPlus3.toString()}");
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

  // Helper method to ensure a time is in UTC+3
  static tz.TZDateTime ensureUtcPlus3Time(tz.TZDateTime time) {
    if (time.location.name != _utcPlus3Location.name) {
      debugLog("Converting time from ${time.location.name} to UTC+3 (Asia/Riyadh)");
      // Convert to UTC+3
      return tz.TZDateTime.from(time.toLocal(), _utcPlus3Location);
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
    // Convert startDate to UTC+3 if not already
    final tz.TZDateTime startDateUtcPlus3 = tz.TZDateTime.from(startDate, _utcPlus3Location);
    final tz.TZDateTime firstOccurrence = _nextInstanceOfTime(startDateUtcPlus3, timeOfDay);

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
    // Convert startDate to UTC+3 if not already
    final tz.TZDateTime startDateUtcPlus3 = tz.TZDateTime.from(startDate, _utcPlus3Location);
    final tz.TZDateTime firstOccurrence = _nextInstanceOfWeekday(startDateUtcPlus3, weekday, timeOfDay);

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
    // Make sure 'from' is in UTC+3
    tz.TZDateTime fromUtcPlus3 = ensureUtcPlus3Time(from);

    // Create a date with the given time in UTC+3
    tz.TZDateTime scheduledDate = tz.TZDateTime(
        _utcPlus3Location,
        fromUtcPlus3.year,
        fromUtcPlus3.month,
        fromUtcPlus3.day,
        tod.hour,
        tod.minute
    );

    // If the time already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(fromUtcPlus3) || scheduledDate.isAtSameMomentAs(fromUtcPlus3)) {
      scheduledDate = tz.TZDateTime(
          _utcPlus3Location,
          fromUtcPlus3.year,
          fromUtcPlus3.month,
          fromUtcPlus3.day + 1,
          tod.hour,
          tod.minute
      );
    }

    debugLog("Next instance of time: ${scheduledDate.toString()} (UTC+3)");
    return scheduledDate;
  }

  static tz.TZDateTime _nextInstanceOfWeekday(tz.TZDateTime from, int weekday, TimeOfDay tod) {
    // Make sure 'from' is in UTC+3
    tz.TZDateTime fromUtcPlus3 = ensureUtcPlus3Time(from);

    // Get the next instance of the specified time
    tz.TZDateTime scheduledDate = _nextInstanceOfTime(fromUtcPlus3, tod);

    // Keep adding days until we hit the target weekday
    while (scheduledDate.weekday != weekday) {
      scheduledDate = tz.TZDateTime(
          _utcPlus3Location,
          scheduledDate.year,
          scheduledDate.month,
          scheduledDate.day + 1,
          tod.hour,
          tod.minute
      );
    }

    debugLog("Next instance of weekday $weekday: ${scheduledDate.toString()} (UTC+3)");
    return scheduledDate;
  }

  static int generateNotificationId(String docId, tz.TZDateTime scheduledTime) {
    // Make sure the scheduled time is in UTC+3
    final tz.TZDateTime timeUtcPlus3 = ensureUtcPlus3Time(scheduledTime);

    final int docHash = docId.hashCode;
    final int timeHash = timeUtcPlus3.millisecondsSinceEpoch ~/ 1000;
    final int combinedHash = (docHash ^ timeHash) & 0x7FFFFFFF;

    debugLog("Generated notification ID: $combinedHash for docId: $docId, time: ${timeUtcPlus3.toString()}");
    return combinedHash;
  }

  static String getFormattedTimeWithDate(BuildContext context, tz.TZDateTime dateTime) {
    try {
      // Ensure we're using UTC+3 timezone
      final tz.TZDateTime dateTimeUtcPlus3 = ensureUtcPlus3Time(dateTime);

      // Current time in UTC+3
      final tz.TZDateTime nowUtcPlus3 = tz.TZDateTime.now(_utcPlus3Location);

      // For debugging timezone issues
      debugLog("Formatting time: Current UTC+3: ${nowUtcPlus3.toString()}, Target UTC+3: ${dateTimeUtcPlus3.toString()}");

      // Create date-only objects for comparison (in UTC+3)
      final DateTime todayDate = DateTime(nowUtcPlus3.year, nowUtcPlus3.month, nowUtcPlus3.day);
      final DateTime medicationDate = DateTime(dateTimeUtcPlus3.year, dateTimeUtcPlus3.month, dateTimeUtcPlus3.day);
      final DateTime tomorrowDate = DateTime(todayDate.year, todayDate.month, todayDate.day + 1);

      // Format the time portion
      final TimeOfDay tod = TimeOfDay.fromDateTime(dateTimeUtcPlus3);
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
    final tz.TZDateTime testTime2 = tz.TZDateTime.now(_utcPlus3Location).add(const Duration(seconds: 30));

    try {
      await scheduleAlarmNotification(
        id: testId2,
        title: "⚠️ اختبار الإشعارات (30 ثانية)",
        body: "هذا اختبار للتحقق من دقة توقيت الإشعارات. الوقت المحدد: ${testTime2.toString()}",
        scheduledTime: testTime2,
        medicationId: "test_30sec",
        isCompanionCheck: false,
      );
      debugLog("Scheduled 30-second test notification with ID: $testId2");
    } catch (e) {
      debugLog("Error scheduling 30-second test notification: $e");
    }

    // Test 3: Scheduled in 2 minutes
    final int testId3 = 999993;
    final tz.TZDateTime testTime3 = tz.TZDateTime.now(_utcPlus3Location).add(const Duration(minutes: 2));

    try {
      await scheduleAlarmNotification(
        id: testId3,
        title: "⚠️ اختبار الإشعارات (2 دقيقة)",
        body: "هذا اختبار للتحقق من استمرار عمل الإشعارات. الوقت المحدد: ${testTime3.toString()}",
        scheduledTime: testTime3,
        medicationId: "test_2min",
        isCompanionCheck: false,
      );
      debugLog("Scheduled 2-minute test notification with ID: $testId3");
    } catch (e) {
      debugLog("Error scheduling 2-minute test notification: $e");
    }

    // Log all pending notifications to verify
    await logPendingNotifications();
  }

  // Method to guide users to disable battery optimization
  static Future<void> showBatteryOptimizationGuide(BuildContext context) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("تفعيل الإشعارات"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("للحصول على إشعارات دقيقة للأدوية، يرجى:"),
              SizedBox(height: 10),
              Text("1. فتح إعدادات الهاتف"),
              Text("2. البحث عن \"تحسين البطارية\" أو \"Battery Optimization\""),
              Text("3. العثور على تطبيق مُذكر وإلغاء تفعيل تحسين البطارية له"),
              SizedBox(height: 10),
              Text("هذا ضروري لضمان عمل تذكيرات الدواء في الوقت المحدد."),
            ],
          ),
          actions: [
            TextButton(
              child: Text("حسناً"),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = response.payload ?? '';
  final id = response.id ?? 0;
  final actionId = response.actionId ?? 'TAP';
  final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS ZZZZ').format(DateTime.now());

  print("--------------------------------------------------");
  print("[AlarmNotificationHelper BACKGROUND] Timestamp: $timestamp");
  print("[AlarmNotificationHelper BACKGROUND] Notification Interaction Received:");
  print("[AlarmNotificationHelper BACKGROUND]   ID: $id");
  print("[AlarmNotificationHelper BACKGROUND]   Action ID: $actionId");
  print("[AlarmNotificationHelper BACKGROUND]   Payload: $payload");
  print("--------------------------------------------------");
}
