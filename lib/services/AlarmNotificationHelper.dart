import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_init;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // Import to access navigatorKey

class AlarmNotificationHelper {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static FlutterLocalNotificationsPlugin get notificationsPlugin => _notificationsPlugin;

  static Future<void> initialize(BuildContext context) async {
    debugPrint("[AlarmHelper] Initializing...");

    tz_init.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    bool? ok = await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    debugPrint("[AlarmHelper] Plugin initialized: $ok");

    await _setupNotificationChannels();
    await _requestPermissions();

    debugPrint("[AlarmHelper] Initialization complete");
  }

  static Future<void> _setupNotificationChannels() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) {
        debugPrint("[AlarmHelper] Android impl not found");
        return;
      }

      AndroidNotificationChannel alarmChannel = AndroidNotificationChannel(
        'medication_alarms',
        'Medication Alarms',
        description: 'Critical medication reminders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        sound: const RawResourceAndroidNotificationSound('alarm_sound'),
        vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      );

      AndroidNotificationChannel dailyChannel = AndroidNotificationChannel(
        'daily_reminders',
        'Daily Reminders',
        description: 'Daily medication reminders',
        importance: Importance.high,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('reminder_sound'),
      );

      AndroidNotificationChannel weeklyChannel = AndroidNotificationChannel(
        'weekly_reminders',
        'Weekly Reminders',
        description: 'Weekly medication reminders',
        importance: Importance.high,
        playSound: true,
      );

      await androidPlugin.createNotificationChannel(alarmChannel);
      await androidPlugin.createNotificationChannel(dailyChannel);
      await androidPlugin.createNotificationChannel(weeklyChannel);

      debugPrint("[AlarmHelper] Android channels created");
    }

    if (Platform.isIOS) {
      final iosPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

      if (iosPlugin == null) {
        debugPrint("[AlarmHelper] iOS impl not found");
        return;
      }

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

      await iosPlugin.setNotificationCategories(<DarwinNotificationCategory>[
        category,
      ]);

      debugPrint("[AlarmHelper] iOS categories set");
    }
  }

  static Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      final iosPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint("[AlarmHelper] iOS permissions requested");
      }
    }
    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final bool? granted = await androidPlugin?.requestNotificationsPermission();
      debugPrint("[AlarmHelper] Android notification permission: $granted");
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    debugPrint(
        "[AlarmHelper] Notification tapped: id=${response.id}, action=${response.actionId}, payload=${response.payload}");
    final payload = response.payload ?? '';

    if (response.actionId == 'TAKE_ACTION') {
      debugPrint("[AlarmHelper] TAKE_ACTION for $payload");
      _navigateToMedicationDetail(payload, markAsTaken: true);
    } else if (response.actionId == 'SNOOZE_ACTION') {
      debugPrint("[AlarmHelper] SNOOZE_ACTION for $payload");
      _handleSnooze(response.id ?? 0, payload);
    } else {
      debugPrint("[AlarmHelper] Default tap for $payload");
      _navigateToMedicationDetail(payload);
    }
  }

  static Future<void> _navigateToMedicationDetail(String medicationId, {bool markAsTaken = false}) async {
    if (medicationId.isEmpty) {
      debugPrint("[AlarmHelper] Cannot navigate: Empty medication ID");
      return;
    }

    try {
      final String timeIso = DateTime.now().toUtc().toIso8601String();
      final String confirmationKey = 'PREF_CONFIRMATION_SHOWN_PREFIX${medicationId}_$timeIso';

      final prefs = await SharedPreferences.getInstance();
      final bool alreadyShown = prefs.getBool(confirmationKey) ?? false;

      if (alreadyShown) {
        debugPrint("[AlarmHelper] Notification for $medicationId already handled, skipping navigation");
        return;
      }

      await prefs.setBool(confirmationKey, true);

      navigatorKey.currentState?.pushNamed(
        '/medication_detail',
        arguments: {
          'docId': medicationId,
          'fromNotification': true,
          'needsConfirmation': true,
          'confirmationTimeIso': timeIso,
          'confirmationKey': confirmationKey,
          'autoMarkAsTaken': markAsTaken,
        },
      );

      debugPrint("[AlarmHelper] Navigated to medication detail for $medicationId");
    } catch (e) {
      debugPrint("[AlarmHelper] Error navigating to medication detail: $e");
    }
  }

  static Future<void> _handleSnooze(int originalId, String medicationId) async {
    const Duration snoozeDuration = Duration(minutes: 5);
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    final tz.TZDateTime snoozeTime = now.add(snoozeDuration);

    final int newId = generateNotificationId(medicationId, snoozeTime.toUtc());
    debugPrint("[AlarmHelper] Snoozing original notification $originalId -> new ID $newId at $snoozeTime");

    try {
      await scheduleAlarmNotification(
        id: newId,
        title: '⏰ Snoozed: Take Medication',
        body: 'Reminder to take your medication (snoozed).',
        scheduledTime: snoozeTime.toLocal(),
        medicationId: medicationId,
        isSnoozed: true,
      );
    } catch (e) {
      print("[AlarmHelper] Error scheduling snoozed notification: $e");
    }
  }

  static Future<void> scheduleAlarmNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required String medicationId,
    bool isSnoozed = false,
  }) async {
    debugPrint("[AlarmHelper] Scheduling ALARM $id at $scheduledTime");

    final androidDetails = AndroidNotificationDetails(
      'medication_alarms',
      'Medication Alarms',
      channelDescription: 'Critical medication reminders',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      sound: const RawResourceAndroidNotificationSound('alarm_sound'),
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
      category: AndroidNotificationCategory.alarm,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('TAKE_ACTION', 'Take Now'),
        AndroidNotificationAction('SNOOZE_ACTION', 'Snooze (5 min)'),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      sound: 'alarm_sound.aiff',
      categoryIdentifier: 'medication_category',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final tzTime = tz.TZDateTime.from(scheduledTime, tz.local);
    if (tzTime.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint("[AlarmHelper] Cannot schedule in the past");
      return;
    }

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: medicationId,
      );
      debugPrint("[AlarmHelper] Alarm $id scheduled");
    } catch (e) {
      debugPrint("[AlarmHelper] Error scheduling alarm $id: $e");
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
    DateTime? endDate,
  }) async {
    debugPrint(
        "[AlarmHelper] Scheduling DAILY $id at ${timeOfDay.format(context)} from $startDate");

    const androidDetails = AndroidNotificationDetails(
      'daily_reminders',
      'Daily Reminders',
      channelDescription: 'Daily medication reminders',
      importance: Importance.high,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('reminder_sound'),
    );

    const iosDetails = DarwinNotificationDetails(
      sound: 'reminder_sound.aiff',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final first = _nextInstanceOfTime(startDate, timeOfDay);
    if (endDate != null &&
        first.isAfter(tz.TZDateTime.from(endDate, tz.local))) {
      debugPrint("[AlarmHelper] First after endDate, skipping");
      return;
    }

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        first,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint("[AlarmHelper] DAILY $id scheduled");
    } catch (e) {
      debugPrint("[AlarmHelper] Error scheduling DAILY $id: $e");
    }
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
    DateTime? endDate,
  }) async {
    debugPrint(
        "[AlarmHelper] Scheduling WEEKLY $id on $weekday at ${timeOfDay.format(context)}");

    const androidDetails = AndroidNotificationDetails(
      'weekly_reminders',
      'Weekly Reminders',
      channelDescription: 'Weekly medication reminders',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final first = _nextInstanceOfWeekday(startDate, weekday, timeOfDay);
    if (endDate != null &&
        first.isAfter(tz.TZDateTime.from(endDate, tz.local))) {
      debugPrint("[AlarmHelper] First after endDate, skipping");
      return;
    }

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        first,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      debugPrint("[AlarmHelper] WEEKLY $id scheduled");
    } catch (e) {
      debugPrint("[AlarmHelper] Error scheduling WEEKLY $id: $e");
    }
  }

  static tz.TZDateTime _nextInstanceOfTime(DateTime from, TimeOfDay tod) {
    final base = tz.TZDateTime.from(from, tz.local);
    tz.TZDateTime sched = tz.TZDateTime(
        tz.local, base.year, base.month, base.day, tod.hour, tod.minute);
    if (sched.isBefore(tz.TZDateTime.now(tz.local))) {
      sched = sched.add(const Duration(days: 1));
    }
    return sched;
  }

  static tz.TZDateTime _nextInstanceOfWeekday(DateTime from, int weekday, TimeOfDay tod) {
    tz.TZDateTime sched = _nextInstanceOfTime(from, tod);
    while (sched.weekday != weekday) {
      sched = sched.add(const Duration(days: 1));
    }
    return sched;
  }

  static int generateNotificationId(String docId, DateTime scheduledUtcTime) {
    final int docHash = docId.hashCode & 0x0FFFFFFF;
    final int timeHash = scheduledUtcTime.millisecondsSinceEpoch & 0x0FFFFFFF;
    return (docHash ^ timeHash) & 0x7FFFFFFF;
  }

  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
    debugPrint("[AlarmHelper] Canceled $id");
  }

  static Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    debugPrint("[AlarmHelper] All canceled");
  }

  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    final list = await _notificationsPlugin.pendingNotificationRequests();
    debugPrint("[AlarmHelper] Pending: ${list.length}");
    return list;
  }

  static Future<bool?> checkForNotificationPermissions() async {
    try {
      if (Platform.isIOS) {
        final iosPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        if (iosPlugin == null) return null;
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted;
      } else if (Platform.isAndroid) {
        final androidPlugin = _notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await androidPlugin?.areNotificationsEnabled();
      }
    } catch (e) {
      debugPrint("[AlarmHelper] Permission check error: $e");
    }
    return null;
  }
}

extension on IOSFlutterLocalNotificationsPlugin {
  setNotificationCategories(List<DarwinNotificationCategory> list) {}
}

// Required for background notification processing
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final String? payload = response.payload;
  if (payload != null && payload.isNotEmpty) {
    print("[Background] Notification tapped with payload: $payload");
    // You should handle saving this and checking it on resume to navigate.
  }
}