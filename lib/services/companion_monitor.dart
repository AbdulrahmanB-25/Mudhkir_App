import 'package:timezone/timezone.dart' as tz;

import '../core/notifications/notification_payload.dart';
import '../core/notifications/reminder_service.dart';
import '../core/utils/clock.dart';
import '../data/repositories/companion_repository.dart';
import '../data/repositories/dose_log_repository.dart';
import '../data/repositories/medication_repository.dart';
import '../domain/models/dose.dart';
import '../domain/services/dose_calculator.dart';
import '../l10n/app_localizations.dart';

/// Tells a caregiver when someone they look after misses a dose.
///
/// Works on the locally synced copy of the patient's data, so it should run
/// right after a sync (app start/resume and the background task).
class CompanionMonitor {
  CompanionMonitor({
    required this._companions,
    required this._medications,
    required this._logs,
    required this._reminders,
    this._calculator = const DoseCalculator(),
    this._clock = const Clock(),
  });

  final CompanionRepository _companions;
  final MedicationRepository _medications;
  final DoseLogRepository _logs;
  final ReminderService _reminders;
  final DoseCalculator _calculator;
  final Clock _clock;

  /// Only alert about recent doses, not old history after first linking.
  static const lookBack = Duration(hours: 12);

  /// Returns the number of new alerts shown.
  Future<int> check({
    required String caregiverId,
    required AppLocalizations l10n,
  }) async {
    final now = _clock.nowUtc();
    var shown = 0;
    for (final link in await _companions.acceptedPatients(caregiverId)) {
      final from = link.updatedAt.isAfter(now.subtract(lookBack))
          ? link.updatedAt
          : now.subtract(lookBack);
      final doses = _calculator.doses(
        medications: await _medications.getAll(link.patientId),
        logs: await _logs.getRange(link.patientId, from, now),
        from: from,
        to: now,
        now: now,
        location: tz.local,
      );
      for (final dose in doses.where((d) => d.status == DoseStatus.missed)) {
        if (!await _companions.markAlerted(dose.logId)) continue;
        final name = link.patientName ?? link.patientEmail ?? '';
        await _reminders.showCompanionAlert(
          key: dose.logId,
          title: l10n.companionMissedTitle(name),
          body: l10n.companionMissedBody(name, dose.medication.name),
          payload: CompanionPayload(patientId: link.patientId),
          l10n: l10n,
        );
        shown++;
      }
    }
    return shown;
  }
}
