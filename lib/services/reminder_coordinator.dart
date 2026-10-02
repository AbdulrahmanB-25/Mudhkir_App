import 'dart:async';

import 'package:timezone/timezone.dart' as tz;

import '../core/notifications/reminder_service.dart';
import '../core/utils/clock.dart';
import '../core/utils/log.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/dose_log_repository.dart';
import '../data/repositories/medication_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../domain/services/dose_calculator.dart';
import '../l10n/app_localizations.dart';

/// Recomputes the user's upcoming doses and hands them to the
/// [ReminderService]. Shared by the app and the background task.
Future<void> rescheduleReminders({
  required String ownerId,
  required MedicationRepository medications,
  required DoseLogRepository logs,
  required ReminderService reminders,
  required AppLocalizations l10n,
  DoseCalculator calculator = const DoseCalculator(),
  Clock clock = const Clock(),
}) async {
  final now = clock.nowUtc();
  final to = now.add(ReminderService.scheduleWindow);
  final doses = calculator.doses(
    medications: await medications.getAll(ownerId),
    logs: await logs.getRange(ownerId, now, to),
    from: now,
    to: to,
    now: now,
    location: tz.local,
  );
  await reminders.syncDoseReminders(doses, l10n, now);
}

/// Keeps scheduled reminders in step with the database while the app runs:
/// whenever the user's medications or dose logs change, the account
/// changes, or the language changes.
class ReminderCoordinator {
  ReminderCoordinator({
    required this._auth,
    required this._settings,
    required this._medications,
    required this._logs,
    required this._reminders,
    this._clock = const Clock(),
  });

  final AuthRepository _auth;
  final SettingsRepository _settings;
  final MedicationRepository _medications;
  final DoseLogRepository _logs;
  final ReminderService _reminders;
  final Clock _clock;

  final _subscriptions = <StreamSubscription<Object?>>[];
  Timer? _debounce;
  String? _owner;

  void start() {
    _auth.addListener(_resubscribe);
    _settings.addListener(scheduleRefresh);
    _resubscribe();
  }

  void _resubscribe() {
    if (_owner == _auth.ownerId && _subscriptions.isNotEmpty) return;
    _owner = _auth.ownerId;
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions
      ..clear()
      ..add(_medications.watchAll(_owner!).listen((_) => scheduleRefresh()))
      ..add(
        _logs
            .watchRange(
              _owner!,
              _clock.nowUtc(),
              _clock.nowUtc().add(ReminderService.scheduleWindow),
            )
            .listen((_) => scheduleRefresh()),
      );
  }

  void scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    try {
      await rescheduleReminders(
        ownerId: _auth.ownerId,
        medications: _medications,
        logs: _logs,
        reminders: _reminders,
        l10n: lookupAppLocalizations(_settings.locale),
        clock: _clock,
      );
    } catch (e, s) {
      log('Reminders', 'Refresh failed', e, s);
    }
  }

  void dispose() {
    _debounce?.cancel();
    _auth.removeListener(_resubscribe);
    _settings.removeListener(scheduleRefresh);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
  }
}
