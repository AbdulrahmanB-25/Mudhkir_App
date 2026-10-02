import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/utils/clock.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../data/repositories/medication_repository.dart';
import '../../domain/models/dose.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/medication.dart';
import '../../domain/services/dose_calculator.dart';

/// Watches one person's medications and dose logs for a date range and
/// recomputes their doses whenever data changes (and every minute, so
/// "upcoming" turns into "due" and "missed" on time).
///
/// Base for the Home, Schedule and companion view models.
class DoseFeed extends ChangeNotifier {
  DoseFeed({
    required this.ownerId,
    required MedicationRepository medications,
    required DoseLogRepository logs,
    this._calculator = const DoseCalculator(),
    this._clock = const Clock(),
    tz.Location? location,
  }) : _medicationsRepo = medications,
       _logsRepo = logs,
       _location = location ?? tz.local;

  final String ownerId;
  final MedicationRepository _medicationsRepo;
  final DoseLogRepository _logsRepo;
  final DoseCalculator _calculator;
  final Clock _clock;
  final tz.Location _location;

  StreamSubscription<List<Medication>>? _medicationsSub;
  StreamSubscription<List<DoseLog>>? _logsSub;
  Timer? _ticker;

  List<Medication> _medications = const [];
  List<DoseLog> _logs = const [];
  bool _medicationsLoaded = false;
  bool _logsLoaded = false;
  DateTime? _from;
  DateTime? _to;

  bool get isLoading => !_medicationsLoaded || !_logsLoaded;
  List<Medication> get medications => _medications;
  DateTime get now => _clock.nowUtc();
  tz.Location get location => _location;
  DoseCalculator get calculator => _calculator;
  LocalDate get today =>
      LocalDate.fromDateTime(tz.TZDateTime.from(now, _location));

  /// Start of [day] in the user's time zone, as a UTC instant.
  DateTime startOf(LocalDate day) =>
      tz.TZDateTime(_location, day.year, day.month, day.day).toUtc();

  /// Starts watching data for `[from, to)`.
  @protected
  void watchRange(DateTime from, DateTime to) {
    if (from == _from && to == _to) return;
    _from = from;
    _to = to;
    _medicationsSub ??= _medicationsRepo.watchAll(ownerId).listen((value) {
      _medications = value;
      _medicationsLoaded = true;
      _recompute();
    });
    unawaited(_logsSub?.cancel());
    _logsSub = _logsRepo.watchRange(ownerId, from, to).listen((value) {
      _logs = value;
      _logsLoaded = true;
      _recompute();
    });
    _ticker ??= Timer.periodic(const Duration(minutes: 1), (_) => _recompute());
  }

  /// Doses whose effective time is in `[from, to)`.
  List<DoseInstance> dosesBetween(DateTime from, DateTime to) =>
      _calculator.doses(
        medications: _medications,
        logs: _logs,
        from: from,
        to: to,
        now: now,
        location: _location,
      );

  List<DoseInstance> dosesOn(LocalDate day) =>
      dosesBetween(startOf(day), startOf(day.addDays(1)));

  void _recompute() {
    if (isLoading) return;
    onDataChanged();
    notifyListeners();
  }

  /// Subclasses refresh derived state here.
  @protected
  void onDataChanged() {}

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_medicationsSub?.cancel());
    unawaited(_logsSub?.cancel());
    super.dispose();
  }
}
