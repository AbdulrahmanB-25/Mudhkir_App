import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../Features/Companions/companion_medication_tracker.dart';
import '../../Features/Medication/Add/Add_Medication_Page.dart';
import '../../main.dart';
import 'notification_service.dart';

class AlarmNotificationHelper {
  static final NotificationService _service = NotificationService();
  static FlutterLocalNotificationsPlugin get notificationsPlugin => _service.notificationsPlugin;
  static bool _isInitialized = false;
  static final DateFormat _logDateFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS ZZZZ');
  static late tz.Location _riyadhTimezone;
  static const bool _debugMode = true;

  static Future<void> initialize(BuildContext? context) async {
    // Initializes the notification helper and sets up time zones
    debugLog("Starting initialization...");
    tz_init.initializeTimeZones();
    _riyadhTimezone = tz.getLocation('Asia/Riyadh');
    tz.setLocalLocation(_riyadhTimezone);
    debugLog("Time zones initialized with Riyadh timezone (Asia/Riyadh)");
    await _checkNotificationSettings();
    if (context != null) {
      await _initializeWithContext(context);
    }
    await ensureChannelsSetup();
    debugLog("Initialization complete");
  }

  static void debugLog(String message) {
    if (_debugMode) {
      final timestamp = _logDateFormat.format(DateTime.now());
      print("[AlarmNotificationHelper] [$timestamp] $message");
    } else {
      print("[AlarmNotificationHelper] $message");
    }
  }

  static Future<void> _checkNotificationSettings() async {
    try {
      final androidPlugin = _service.notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        final bool? areEnabled = await androidPlugin.areNotificationsEnabled();
        debugLog("Notification permission status: ${areEnabled == true ? 'GRANTED' : 'NOT GRANTED'}");
        if (areEnabled != true) {
          debugLog("⚠️ WARNING: Notifications are not enabled for this app!");
          debugLog("⚠️ User needs to grant notification permission in settings");
        }
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
      await checkAndRequestExactAlarmPermission(context);
      await _processPendingNotifications();
      if (_debugMode) {
        debugLog("Scheduling test notification for debugging...");
        await showTestNotification();
      }
    }
  }

  static Future<void> _initializeWithContext(BuildContext context) async {
    debugLog("Initializing notification service with context.");
    await _service.initialize(context, _onNotificationResponse, notificationTapBackground);
    _isInitialized = true;
    debugLog("Service initialized");
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
      final medicationId = payload.replaceFirst("companion_reminder_", "");
      CompanionMedicationTracker.processCompanionDoseCheck("companion_check_$medicationId");
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
    if (actionId == 'TAKE_ACTION') {
      debugLog("Take action triggered for notification with payload: $payload");
      _navigateToMedicationDetail(payload, markAsTaken: true);
    } else if (actionId == 'SNOOZE_ACTION') {
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
    var scheduledRiyadhTime = tz.TZDateTime(
      _riyadhTimezone,
      scheduledTime.year,
      scheduledTime.month,
      scheduledTime.day,
      scheduledTime.hour,
      scheduledTime.minute,
      0,
      0,
    );

    final tz.TZDateTime nowExact = tz.TZDateTime.now(_riyadhTimezone);
    final tz.TZDateTime now = tz.TZDateTime(
      _riyadhTimezone,
      nowExact.year,
      nowExact.month,
      nowExact.day,
      nowExact.hour,
      nowExact.minute,
      0,
      0,
    );

    debugLog("Scheduling notification:");
    debugLog("- ID: $id");
    debugLog("- Title: $title");
    debugLog("- Body: $body");
    debugLog("- Adjusted time (Riyadh): ${_logDateFormat.format(scheduledRiyadhTime)}");
    debugLog("- Current time (Riyadh): ${_logDateFormat.format(now)}");
    debugLog("- Exact current time: ${_logDateFormat.format(nowExact)}");
    debugLog("- Time difference in minutes: ${scheduledRiyadhTime.difference(now).inMinutes}");
    debugLog("- Time difference in seconds: ${scheduledRiyadhTime.difference(nowExact).inSeconds}");

    try {
      await _service.cancelNotification(id);
      debugLog("Cancelled any existing notification with ID: $id");
    } catch (e) {
      debugLog("Error cancelling existing notification: $e");
    }

    final bool isExactlyNow = scheduledRiyadhTime.year == now.year &&
                             scheduledRiyadhTime.month == now.month &&
                             scheduledRiyadhTime.day == now.day &&
                             scheduledRiyadhTime.hour == now.hour &&
                             scheduledRiyadhTime.minute == now.minute;

    if (isExactlyNow) {
      debugLog("Scheduling immediate notification since time is exactly now");
      final String channelId = 'medication_alarms_v2';
      try {
        await _service.notificationsPlugin.show(
          id,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              'Medication Alarms',
              channelDescription: 'Critical medication reminders',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              enableVibration: true,
              sound: RawResourceAndroidNotificationSound('medication_alarm'),
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
          ),
          payload: medicationId,
        );
        debugLog("Immediate notification sent with ID: $id");
      } catch (e) {
        debugLog("ERROR showing immediate notification: $e");
      }
      return;
    }

    try {
      if (scheduledRiyadhTime.isBefore(now)) {
        debugLog("Scheduled time is in the past: ${scheduledRiyadhTime.toString()} vs ${now.toString()}");
        
        if (repeatInterval != null) {
          final String oldTime = scheduledRiyadhTime.toString();
          scheduledRiyadhTime = _adjustTimeForRepeat(now, scheduledRiyadhTime, repeatInterval);
          debugLog("Adjusted past time from $oldTime to future: ${scheduledRiyadhTime.toString()}");
        } else {
          debugLog("⚠️ WARNING: Cannot schedule notification for past time (${scheduledRiyadhTime.toString()})");
          return;
        }
      }

      await _service.scheduleAlarmNotification(
        id: id,
        title: title,
        body: body,
        scheduledTime: scheduledRiyadhTime,
        medicationId: medicationId,
        isSnoozed: isSnoozed,
        isCompanionCheck: isCompanionCheck,
        repeatInterval: repeatInterval,
      );

      debugLog("Future notification scheduled with ID: $id for time: ${scheduledRiyadhTime.toString()}");
    } catch (e, stackTrace) {
      debugLog("ERROR scheduling notification: $e");
      debugLog("Stack trace: $stackTrace");
    }
  }

  static List<tz.TZDateTime> _calculateDoseTimes({
    required tz.TZDateTime now,
    required tz.TZDateTime startDate,
    tz.TZDateTime? endDate,
    required String frequencyType,
    required List<dynamic> timesRaw,
  }) {
    // Calculates the next dose times based on frequency and schedule
    final Set<tz.TZDateTime> doseTimeSet = {};
    
    final tz.TZDateTime nowRounded = tz.TZDateTime(
      _riyadhTimezone,
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      0,
      0,
    );
    
    final tz.TZDateTime today = tz.TZDateTime(_riyadhTimezone, now.year, now.month, now.day);
    if (today.isBefore(startDate)) return [];

    if (frequencyType == 'يومي') {
      for (var time in timesRaw) {
        final parsedTime = TimeUtils.parseTime(time as String);
        if (parsedTime != null) {
          final tz.TZDateTime dt = tz.TZDateTime(
            _riyadhTimezone,
            today.year,
            today.month,
            today.day,
            parsedTime.hour,
            parsedTime.minute,
            0,
            0,
          );
          
          final bool isInFuture = dt.isAfter(nowRounded) || 
                                 (dt.year == nowRounded.year && 
                                  dt.month == nowRounded.month && 
                                  dt.day == nowRounded.day && 
                                  dt.hour == nowRounded.hour && 
                                  dt.minute == nowRounded.minute);
                                  
          if (isInFuture && (endDate == null || dt.isBefore(endDate))) {
            doseTimeSet.add(dt);
            debugLog("Adding dose time: ${dt.toString()}, comparison with now: $isInFuture");
          } else {
            debugLog("Skipping dose time (past or after end): ${dt.toString()}");
          }
        }
      }
    } else if (frequencyType == 'اسبوعي') {
      // Weekly frequency logic
    }

    final List<tz.TZDateTime> doseTimes = doseTimeSet.toList();
    doseTimes.sort();
    return doseTimes;
  }

  static Future<void> scheduleAllUserMedications(String userId) async {
    // Schedules notifications for all medications of a user
    debugLog("Scheduling all medications for user: $userId");
    try {
      await ensureChannelsSetup();
      await cancelAllNotifications();
      final medsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .get();
      final tz.TZDateTime now = tz.TZDateTime.now(_riyadhTimezone);
      Set<String> scheduledNotificationKeys = {};
      for (var doc in medsSnapshot.docs) {
        final data = doc.data();
        final docId = doc.id;
        final medName = data['name'] as String? ?? 'Unnamed Medication';
        final Timestamp? startTs = data['startDate'] as Timestamp?;
        final Timestamp? endTs = data['endDate'] as Timestamp?;
        if (startTs == null) continue;
        final tz.TZDateTime startDate = tz.TZDateTime.from(startTs.toDate(), _riyadhTimezone);
        final tz.TZDateTime? endDate = endTs != null ? tz.TZDateTime.from(endTs.toDate(), _riyadhTimezone) : null;
        final String frequencyType = data['frequencyType'] as String? ?? 'daily';
        final List<dynamic> timesRaw = data['times'] ?? [];
        final List<tz.TZDateTime> doseTimes = _calculateDoseTimes(
          now: now,
          startDate: startDate,
          endDate: endDate,
          frequencyType: frequencyType,
          timesRaw: timesRaw,
        );
        for (var doseTime in doseTimes) {
          String notificationKey = "${docId}_${doseTime.year}_${doseTime.month}_${doseTime.day}_${doseTime.hour}_${doseTime.minute}";
          if (scheduledNotificationKeys.contains(notificationKey)) {
            debugLog("Skipping duplicate notification for $docId at ${doseTime.toString()}");
            continue;
          }
          scheduledNotificationKeys.add(notificationKey);
          final int notificationId = generateNotificationId(docId, doseTime);
          try {
            await scheduleAlarmNotification(
              id: notificationId,
              title: "💊 Medication Reminder",
              body: "It's time to take your medication: $medName.",
              scheduledTime: doseTime,
              medicationId: docId,
              isCompanionCheck: false,
            );
          } catch (e) {
            debugLog("Error scheduling notification for $docId: $e");
          }
        }
      }
      debugLog("Scheduled ${scheduledNotificationKeys.length} unique notifications");
    } catch (e) {
      debugLog("Error scheduling medications: $e");
    }
  }

  static int generateNotificationId(String docId, tz.TZDateTime scheduledTime) {
    final tz.TZDateTime timeRiyadh = ensureRiyadhTime(scheduledTime);
    final int docHash = docId.hashCode;
    final int dateHash = timeRiyadh.year * 10000 + timeRiyadh.month * 100 + timeRiyadh.day;
    final int timeHash = timeRiyadh.hour * 100 + timeRiyadh.minute;
    final int combinedHash = ((docHash ^ dateHash ^ timeHash) & 0x7FFFFFFF);
    debugLog("Generated notification ID: $combinedHash for docId: $docId, time: ${timeRiyadh.toString()}");
    return combinedHash;
  }

  static Future<void> _processPendingNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? pendingRequests = prefs.getStringList('pending_notifications');
      if (pendingRequests == null || pendingRequests.isEmpty) {
        debugLog("No pending notification requests found");
        return;
      }
      debugLog("Processing ${pendingRequests.length} pending notification requests");
      await prefs.remove('pending_notifications');
      for (final String requestStr in pendingRequests) {
        try {
          debugLog("Processing pending request: $requestStr");
          debugLog("Actual pending notification processing would happen here");
        } catch (e) {
          debugLog("Error processing pending request: $e");
        }
      }
    } catch (e) {
      debugLog("Error in _processPendingNotifications: $e");
    }
  }

  static tz.TZDateTime ensureRiyadhTime(tz.TZDateTime time) {
    if (time.location.name != _riyadhTimezone.name) {
      return tz.TZDateTime.from(time.toLocal(), _riyadhTimezone);
    }
    return time;
  }

  static tz.TZDateTime _adjustTimeForRepeat(
      tz.TZDateTime now,
      tz.TZDateTime scheduledTime,
      RepeatInterval repeatInterval,
      ) {
    final TimeOfDay tod = TimeOfDay.fromDateTime(scheduledTime);
    if (repeatInterval == RepeatInterval.daily) {
      return _nextInstanceOfTime(now, tod);
    } else if (repeatInterval == RepeatInterval.weekly) {
      return _nextInstanceOfWeekday(now, scheduledTime.weekday, tod);
    }
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
    final tz.TZDateTime fromRiyadh = ensureRiyadhTime(from);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      _riyadhTimezone,
      fromRiyadh.year,
      fromRiyadh.month,
      fromRiyadh.day,
      tod.hour,
      tod.minute,
    );
    if (scheduledDate.isBefore(fromRiyadh) || scheduledDate.isAtSameMomentAs(fromRiyadh)) {
      scheduledDate = tz.TZDateTime(
        _riyadhTimezone,
        fromRiyadh.year,
        fromRiyadh.month,
        fromRiyadh.day + 1,
        tod.hour,
        tod.minute,
      );
    }
    debugLog("Next instance of time: ${scheduledDate.toString()} (Riyadh)");
    return scheduledDate;
  }

  static tz.TZDateTime _nextInstanceOfWeekday(
      tz.TZDateTime from,
      int weekday,
      TimeOfDay tod,
      ) {
    tz.TZDateTime scheduledDate = _nextInstanceOfTime(ensureRiyadhTime(from), tod);
    while (scheduledDate.weekday != weekday) {
      scheduledDate = tz.TZDateTime(
        _riyadhTimezone,
        scheduledDate.year,
        scheduledDate.month,
        scheduledDate.day + 1,
        tod.hour,
        tod.minute,
      );
    }
    debugLog("Next instance of weekday $weekday: ${scheduledDate.toString()} (Riyadh)");
    return scheduledDate;
  }

  static String getFormattedTimeWithDate(BuildContext context, tz.TZDateTime dateTime) {
    try {
      final tz.TZDateTime dateTimeRiyadh = ensureRiyadhTime(dateTime);
      final tz.TZDateTime nowRiyadh = tz.TZDateTime.now(_riyadhTimezone);
      debugLog("Formatting time: Current Riyadh: ${nowRiyadh.toString()}, Target Riyadh: ${dateTimeRiyadh.toString()}");
      final DateTime todayDate = DateTime(nowRiyadh.year, nowRiyadh.month, nowRiyadh.day);
      final DateTime medicationDate = DateTime(dateTimeRiyadh.year, dateTimeRiyadh.month, dateTimeRiyadh.day);
      final DateTime tomorrowDate = DateTime(todayDate.year, todayDate.month, todayDate.day + 1);
      final TimeOfDay tod = TimeOfDay.fromDateTime(dateTimeRiyadh);
      final int hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
      final String minuteStr = tod.minute.toString().padLeft(2, '0');
      final String period = tod.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
      String timeStr = '$hour:$minuteStr $period';
      if (medicationDate.day == tomorrowDate.day &&
          medicationDate.month == tomorrowDate.month &&
          medicationDate.year == tomorrowDate.year) {
        timeStr += " (غداً)";
      } else if (medicationDate.day != todayDate.day ||
          medicationDate.month != todayDate.month ||
          medicationDate.year != todayDate.year) {
        final String formattedDate = DateFormat('dd/MM', 'ar').format(medicationDate);
        timeStr += " ($formattedDate)";
      }
      debugLog("Final formatted time: $timeStr");
      return timeStr;
    } catch (e, stack) {
      debugLog("Error formatting time: $e");
      debugLog("Stack trace: $stack");
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

  static Future<void> showTestNotification() async {
    debugLog("Setting up test notifications");
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
    final int testId2 = 999992;
    final tz.TZDateTime testTime2 = tz.TZDateTime.now(_riyadhTimezone).add(const Duration(minutes: 1));
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
    await logPendingNotifications();
    debugLog("Test notifications setup complete");
  }

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
        if (isAM && hour == 12) hour = 0;
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
      try {
        bool? hasExactAlarm;
        try {
          final bool? areNotificationsEnabled = await androidPlugin.areNotificationsEnabled();
          debugLog("Notification permission status: $areNotificationsEnabled");
          hasExactAlarm = areNotificationsEnabled;
        } catch (e) {
          debugLog("Error checking notification permissions: $e");
          hasExactAlarm = true;
        }
        debugLog("Exact alarm permission status (estimated): $hasExactAlarm");
        if (hasExactAlarm == false) {
          final bool shouldRequest = await _showExactAlarmPermissionDialog(context);
          if (shouldRequest) {
            await _openAlarmPermissionSettings(context);
            return true;
          }
          return false;
        }
        return hasExactAlarm ?? false;
      } catch (e) {
        debugLog("Error checking exact alarm permission: $e");
        return true;
      }
    } catch (e) {
      debugLog("Error in checkAndRequestExactAlarmPermission: $e");
      return false;
    }
  }

  static Future<void> _openAlarmPermissionSettings(BuildContext context) async {
    try {
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
          await androidPlugin.getNotificationAppLaunchDetails();
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
