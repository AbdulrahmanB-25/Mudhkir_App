import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import '../../data/local/app_database.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../data/repositories/medication_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/image_store.dart';
import '../../domain/models/dose.dart';
import '../../l10n/app_localizations.dart';
import '../utils/log.dart';
import 'notification_payload.dart';
import 'reminder_service.dart';

/// Records what the user chose from a reminder's action buttons.
/// Used by both the foreground handler and [onBackgroundNotificationResponse].
Future<void> handleDoseAction({
  required String action,
  required DosePayload payload,
  required AppDatabase db,
  required ReminderService reminders,
}) async {
  final logs = DoseLogRepository(db);
  switch (action) {
    case ReminderActions.take:
      await logs.record(
        ownerId: payload.ownerId,
        medicationId: payload.medicationId,
        scheduledAt: payload.scheduledAt,
        status: DoseLogStatus.taken,
        actedBy: payload.ownerId,
      );
    case ReminderActions.skip:
      await logs.record(
        ownerId: payload.ownerId,
        medicationId: payload.medicationId,
        scheduledAt: payload.scheduledAt,
        status: DoseLogStatus.skipped,
        actedBy: payload.ownerId,
      );
    case ReminderActions.snooze:
      final medication = await MedicationRepository(
        db,
        ImageStore(),
      ).get(payload.medicationId);
      if (medication == null) return;
      final l10n = lookupAppLocalizations(
        await SettingsRepository.readLocale(db),
      );
      await reminders.snooze(
        payload,
        l10n: l10n,
        title: l10n.notificationDoseTitle(medication.name),
        body: l10n.notificationDoseBody(
          medication.dosageAmount,
          l10n.dosageUnitName(medication.dosageUnit.name),
        ),
      );
  }
}

/// Runs in a background isolate when an action button is pressed while the
/// app is closed. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationResponse(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  tzdata.initializeTimeZones();

  final payload = NotificationPayload.decode(response.payload);
  final action = response.actionId;
  if (payload is! DosePayload || action == null) return;

  final db = AppDatabase();
  try {
    final reminders = ReminderService();
    if (action == ReminderActions.snooze) {
      final l10n = lookupAppLocalizations(
        await SettingsRepository.readLocale(db),
      );
      await reminders.initialize(
        l10n: l10n,
        onBackgroundResponse: onBackgroundNotificationResponse,
      );
    }
    await handleDoseAction(
      action: action,
      payload: payload,
      db: db,
      reminders: reminders,
    );
  } catch (e, s) {
    log('NotificationAction', 'Failed to handle $action', e, s);
  } finally {
    await db.close();
  }
}
