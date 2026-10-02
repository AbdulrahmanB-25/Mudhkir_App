import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/models/dose.dart';
import '../../l10n/app_localizations.dart';
import '../utils/log.dart';
import 'notification_payload.dart';

/// Notification action ids, shared by Android and iOS.
abstract final class ReminderActions {
  static const take = 'take';
  static const snooze = 'snooze';
  static const skip = 'skip';
}

class ReminderPermissions {
  const ReminderPermissions({
    required this.notifications,
    required this.exactAlarms,
  });

  final bool notifications;

  /// Android 12+ only; always true elsewhere.
  final bool exactAlarms;

  bool get allGranted => notifications && exactAlarms;
}

/// Schedules medication reminders and caregiver alerts with
/// flutter_local_notifications. Everything runs on the device, so reminders
/// work without internet.
class ReminderService {
  ReminderService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _doseChannelId = 'medication_reminders_v2';
  static const _companionChannelId = 'companion_alerts';
  static const _iosDoseCategory = 'dose_reminder';
  static const snoozeDuration = Duration(minutes: 10);

  /// How far ahead reminders are scheduled. iOS keeps at most 64 pending
  /// notifications, so the window is capped by [maxScheduled].
  static const scheduleWindow = Duration(days: 7);
  static const maxScheduled = 60;

  static const _primary = Color(0xFF2E86C1);

  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  Future<void> initialize({
    required AppLocalizations l10n,
    DidReceiveNotificationResponseCallback? onResponse,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundResponse,
  }) async {
    if (_initialized) return;
    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        // Permission is requested from the app at a sensible moment instead.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: [
          DarwinNotificationCategory(
            _iosDoseCategory,
            actions: [
              DarwinNotificationAction.plain(
                ReminderActions.take,
                l10n.notificationActionTake,
              ),
              DarwinNotificationAction.plain(
                ReminderActions.snooze,
                l10n.notificationActionSnooze,
              ),
              DarwinNotificationAction.plain(
                ReminderActions.skip,
                l10n.notificationActionSkip,
                options: {DarwinNotificationActionOption.destructive},
              ),
            ],
          ),
        ],
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
    );
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        _doseChannelId,
        l10n.notificationChannelDoses,
        description: l10n.notificationChannelDosesDescription,
        importance: Importance.max,
        sound: const RawResourceAndroidNotificationSound('medication_alarm'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        _companionChannelId,
        l10n.notificationChannelCompanions,
        description: l10n.notificationChannelCompanionsDescription,
        importance: Importance.high,
      ),
    );
    _initialized = true;
  }

  /// The notification that opened the app, if any.
  Future<NotificationResponse?> launchResponse() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      return details!.notificationResponse;
    }
    return null;
  }

  Future<ReminderPermissions> permissions() async {
    if (!_isMobile) {
      return const ReminderPermissions(notifications: true, exactAlarms: true);
    }
    if (Platform.isAndroid) {
      final android = _android;
      return ReminderPermissions(
        notifications: await android?.areNotificationsEnabled() ?? false,
        exactAlarms: await android?.canScheduleExactNotifications() ?? true,
      );
    }
    final ios = await _ios?.checkPermissions();
    return ReminderPermissions(
      notifications: ios?.isEnabled ?? false,
      exactAlarms: true,
    );
  }

  Future<void> requestPermissions() async {
    if (!_isMobile) return;
    if (Platform.isAndroid) {
      await _android?.requestNotificationsPermission();
    } else {
      await _ios?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  /// Opens the system screen for "Alarms & reminders" on Android 12+.
  Future<void> requestExactAlarms() async {
    if (_isMobile && Platform.isAndroid) {
      await _android?.requestExactAlarmsPermission();
    }
  }

  NotificationDetails _doseDetails(AppLocalizations l10n) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          _doseChannelId,
          l10n.notificationChannelDoses,
          channelDescription: l10n.notificationChannelDosesDescription,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          sound: const RawResourceAndroidNotificationSound('medication_alarm'),
          color: _primary,
          visibility: NotificationVisibility.public,
          actions: [
            AndroidNotificationAction(
              ReminderActions.take,
              l10n.notificationActionTake,
            ),
            AndroidNotificationAction(
              ReminderActions.snooze,
              l10n.notificationActionSnooze,
            ),
            AndroidNotificationAction(
              ReminderActions.skip,
              l10n.notificationActionSkip,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: _iosDoseCategory,
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentSound: true,
        ),
      );

  /// Makes the pending reminders match [doses]: cancels reminders that are no
  /// longer needed and (re)schedules the rest. Snoozed reminders are kept.
  Future<void> syncDoseReminders(
    List<DoseInstance> doses,
    AppLocalizations l10n,
    DateTime now,
  ) async {
    final upcoming = doses
        .where(
          (d) =>
              (d.status == DoseStatus.upcoming) && d.effectiveAt.isAfter(now),
        )
        .take(maxScheduled)
        .toList();
    final wanted = {for (final d in upcoming) notificationIdFor(d.logId): d};

    for (final pending in await _plugin.pendingNotificationRequests()) {
      final payload = NotificationPayload.decode(pending.payload);
      if (payload is DosePayload &&
          !payload.isSnooze &&
          !wanted.containsKey(pending.id)) {
        await _plugin.cancel(id: pending.id);
      }
    }

    final mode = await _scheduleMode();
    for (final MapEntry(key: id, value: dose) in wanted.entries) {
      try {
        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: tz.TZDateTime.from(dose.effectiveAt, tz.local),
          notificationDetails: _doseDetails(l10n),
          androidScheduleMode: mode,
          title: l10n.notificationDoseTitle(dose.medication.name),
          body: l10n.notificationDoseBody(
            dose.medication.dosageAmount,
            l10n.dosageUnitName(dose.medication.dosageUnit.name),
          ),
          payload: DosePayload.fromDose(dose).encode(),
        );
      } catch (e) {
        log('Reminders', 'Could not schedule ${dose.logId}', e);
      }
    }
  }

  Future<void> snooze(
    DosePayload payload, {
    required String title,
    required String body,
    required AppLocalizations l10n,
  }) async {
    await _plugin.zonedSchedule(
      id: notificationIdFor('snooze:${payload.logId}'),
      scheduledDate: tz.TZDateTime.now(tz.UTC).add(snoozeDuration),
      notificationDetails: _doseDetails(l10n),
      androidScheduleMode: await _scheduleMode(),
      title: title,
      body: body,
      payload: payload.asSnooze().encode(),
    );
  }

  /// Removes the reminder (and any snooze) of a dose that was handled in the
  /// app, so it does not ring later.
  Future<void> cancelDose(String logId) async {
    await _plugin.cancel(id: notificationIdFor(logId));
    await _plugin.cancel(id: notificationIdFor('snooze:$logId'));
  }

  Future<void> showCompanionAlert({
    required String key,
    required String title,
    required String body,
    required CompanionPayload payload,
    required AppLocalizations l10n,
  }) => _plugin.show(
    id: notificationIdFor('companion:$key'),
    title: title,
    body: body,
    payload: payload.encode(),
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _companionChannelId,
        l10n.notificationChannelCompanions,
        importance: Importance.high,
        priority: Priority.high,
        color: _primary,
      ),
      iOS: const DarwinNotificationDetails(presentSound: true),
    ),
  );

  /// A reminder one minute from now, from the Settings screen.
  Future<void> scheduleTest(AppLocalizations l10n) async {
    await _plugin.zonedSchedule(
      id: notificationIdFor('test'),
      scheduledDate: tz.TZDateTime.now(tz.UTC).add(const Duration(minutes: 1)),
      notificationDetails: _doseDetails(l10n),
      androidScheduleMode: await _scheduleMode(),
      title: l10n.notificationTestTitle,
      body: l10n.notificationTestBody,
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<AndroidScheduleMode> _scheduleMode() async {
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    return exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
}
