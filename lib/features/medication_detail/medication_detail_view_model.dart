import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../data/repositories/dose_log_repository.dart';
import '../../data/repositories/medication_repository.dart';
import '../../domain/models/dose.dart';
import '../../domain/models/medication.dart';
import '../../domain/services/dose_calculator.dart';

class MedicationDetailViewModel extends ChangeNotifier {
  MedicationDetailViewModel({
    required this.medicationId,
    required this._medications,
    required DoseLogRepository logs,
    this.doseAt,
    this._calculator = const DoseCalculator(),
    this._clock = const Clock(),
  }) {
    _medicationSub = _medications.watch(medicationId).listen((m) {
      _medication = m;
      _loaded = true;
      notifyListeners();
    });
    _historySub = logs.watchForMedication(medicationId).listen((h) {
      _history = h;
      notifyListeners();
    });
  }

  final String medicationId;

  /// The dose the user came for (from a notification or a list), if any.
  final DateTime? doseAt;
  final MedicationRepository _medications;
  final DoseCalculator _calculator;
  final Clock _clock;

  late final StreamSubscription<Medication?> _medicationSub;
  late final StreamSubscription<List<DoseLog>> _historySub;

  Medication? _medication;
  List<DoseLog> _history = const [];
  bool _loaded = false;

  bool get isLoading => !_loaded;
  Medication? get medication => _medication;
  List<DoseLog> get history => _history;

  /// The selected dose with its current status.
  DoseInstance? get dose {
    final medication = _medication;
    final at = doseAt;
    if (medication == null || at == null) return null;
    final log = _history.where((l) => l.scheduledAt == at).firstOrNull;
    final effective = log?.rescheduledTo ?? at;
    return DoseInstance(
      medication: medication,
      scheduledAt: at,
      log: log,
      status: _calculator.statusFor(log, effective, _clock.nowUtc()),
    );
  }

  /// Adherence over the recorded history (taken / recorded).
  double? get adherence {
    final relevant = _history.where(
      (l) => l.status != DoseLogStatus.rescheduled,
    );
    if (relevant.isEmpty) return null;
    final taken = relevant.where((l) => l.status == DoseLogStatus.taken).length;
    return taken / relevant.length;
  }

  Future<void> end() => _medications.end(medicationId);
  Future<void> resume() => _medications.resume(medicationId);
  Future<void> delete() => _medications.delete(medicationId);

  @override
  void dispose() {
    unawaited(_medicationSub.cancel());
    unawaited(_historySub.cancel());
    super.dispose();
  }
}
