import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../core/utils/ids.dart';
import '../../data/repositories/medication_repository.dart';
import '../../data/services/image_store.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/medication.dart';
import '../../domain/services/dose_calculator.dart';

/// Problems that stop the user from moving to the next step.
enum FormIssue {
  nameRequired,
  dosageRequired,
  timesRequired,
  weekdaysRequired,
  endBeforeStart,
}

/// State of the three-step add/edit medication wizard:
///  0. name and photo, 1. dosage and schedule, 2. dates and notes.
class MedicationFormViewModel extends ChangeNotifier {
  MedicationFormViewModel({
    required this.ownerId,
    required this._repository,
    required this._images,
    this.medicationId,
    this._clock = const Clock(),
  }) {
    _startDate = LocalDate.fromDateTime(_clock.now());
    _resizeDaily(1);
    if (medicationId != null) {
      _isLoading = true;
      _load();
    }
  }

  static const stepCount = 3;
  static const maxTimesPerDay = 6;

  /// Choosing every day of the week should be a daily schedule instead.
  static const maxWeekdays = 6;

  final String ownerId;
  final String? medicationId;
  final MedicationRepository _repository;
  final ImageStore _images;
  final Clock _clock;

  Medication? _original;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _notFound = false;
  int _step = 0;

  String _name = '';
  String? _imagePath;
  final _temporaryImages = <String>{};

  String _dosageAmount = '';
  DosageUnit _unit = DosageUnit.mg;
  Frequency _frequency = Frequency.daily;
  List<int?> _dailyTimes = [];
  List<bool> _dailyAuto = [];
  final Set<int> _weekdays = {};
  final Map<int, int?> _weeklyTimes = {};
  final Map<int, bool> _weeklyAuto = {};

  late LocalDate _startDate;
  LocalDate? _endDate;
  String _notes = '';

  bool get isEditing => medicationId != null;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get notFound => _notFound;
  int get step => _step;
  bool get isLastStep => _step == stepCount - 1;

  String get name => _name;
  String? get imagePath => _imagePath;
  String get dosageAmount => _dosageAmount;
  DosageUnit get unit => _unit;
  Frequency get frequency => _frequency;
  int get timesPerDay => _dailyTimes.length;
  List<int?> get dailyTimes => List.unmodifiable(_dailyTimes);
  bool isDailyAuto(int index) => _dailyAuto[index];
  List<int> get weekdays => _weekdays.toList()..sort();
  int? weeklyTime(int day) => _weeklyTimes[day];
  bool isWeeklyAuto(int day) => _weeklyAuto[day] ?? false;
  LocalDate get startDate => _startDate;
  LocalDate? get endDate => _endDate;
  String get notes => _notes;

  Future<void> _load() async {
    final medication = await _repository.get(medicationId!);
    _isLoading = false;
    if (medication == null) {
      _notFound = true;
      notifyListeners();
      return;
    }
    _original = medication;
    _name = medication.name;
    _imagePath = medication.imagePath;
    _dosageAmount = medication.dosageAmount;
    _unit = medication.dosageUnit;
    _frequency = medication.frequency;
    if (medication.frequency == Frequency.daily) {
      _dailyTimes = [for (final t in medication.times) t.minutes];
      _dailyAuto = List.filled(_dailyTimes.length, false);
      if (_dailyTimes.isEmpty) _resizeDaily(1);
    } else {
      _resizeDaily(1);
      for (final t in medication.times) {
        _weekdays.add(t.weekday!);
        _weeklyTimes[t.weekday!] = t.minutes;
        _weeklyAuto[t.weekday!] = false;
      }
    }
    _startDate = medication.startDate;
    _endDate = medication.endDate;
    _notes = medication.notes ?? '';
    notifyListeners();
  }

  // ------------------------------------------------------------- step 1

  void setName(String value) {
    _name = value;
    notifyListeners();
  }

  /// [pickedPath] is the temporary file from the image picker.
  Future<void> setImage(String pickedPath) async {
    final copy = await _images.saveCopy(pickedPath);
    await _discardTemporary(_imagePath);
    _temporaryImages.add(copy);
    _imagePath = copy;
    notifyListeners();
  }

  Future<void> removeImage() async {
    await _discardTemporary(_imagePath);
    _imagePath = null;
    notifyListeners();
  }

  Future<void> _discardTemporary(String? path) async {
    if (path != null && _temporaryImages.remove(path)) {
      await _images.deleteLocal(path);
    }
  }

  // ------------------------------------------------------------- step 2

  void setDosageAmount(String value) {
    _dosageAmount = value;
    notifyListeners();
  }

  void setUnit(DosageUnit value) {
    _unit = value;
    notifyListeners();
  }

  void setFrequency(Frequency value) {
    _frequency = value;
    notifyListeners();
  }

  void setTimesPerDay(int count) {
    _resizeDaily(count.clamp(1, maxTimesPerDay));
    _autoFillDaily();
    notifyListeners();
  }

  void _resizeDaily(int count) {
    _dailyTimes = List.generate(
      count,
      (i) => i < _dailyTimes.length ? _dailyTimes[i] : null,
    );
    _dailyAuto = List.generate(
      count,
      (i) => i < _dailyAuto.length ? _dailyAuto[i] : false,
    );
  }

  /// Setting the first time spreads the others evenly over the day (until
  /// the user picks them by hand), like the original app.
  void setDailyTime(int index, int minutes) {
    _dailyTimes[index] = minutes;
    _dailyAuto[index] = false;
    if (index == 0) _autoFillDaily();
    notifyListeners();
  }

  void _autoFillDaily() {
    final first = _dailyTimes.firstOrNull;
    if (first == null) return;
    final spaced = DoseCalculator.evenlySpaced(first, _dailyTimes.length);
    for (var i = 1; i < _dailyTimes.length; i++) {
      if (_dailyTimes[i] == null || _dailyAuto[i]) {
        _dailyTimes[i] = spaced[i];
        _dailyAuto[i] = true;
      }
    }
  }

  /// Returns false when the day limit was reached.
  bool toggleWeekday(int day) {
    if (_weekdays.remove(day)) {
      _weeklyTimes.remove(day);
      _weeklyAuto.remove(day);
    } else {
      if (_weekdays.length >= maxWeekdays) return false;
      _weekdays.add(day);
      _weeklyTimes[day] = null;
      _weeklyAuto[day] = false;
    }
    notifyListeners();
    return true;
  }

  void setWeeklyTime(int day, int minutes) {
    _weeklyTimes[day] = minutes;
    _weeklyAuto[day] = false;
    notifyListeners();
  }

  /// Copies the first selected day's time to the days without a time.
  /// Returns false if the first day has no time yet.
  bool applyFirstTimeToAll() {
    final days = weekdays;
    final first = days.isEmpty ? null : _weeklyTimes[days.first];
    if (first == null) return false;
    for (final day in days.skip(1)) {
      if (_weeklyTimes[day] == null || (_weeklyAuto[day] ?? false)) {
        _weeklyTimes[day] = first;
        _weeklyAuto[day] = true;
      }
    }
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------- step 3

  void setStartDate(LocalDate value) {
    _startDate = value;
    notifyListeners();
  }

  void setEndDate(LocalDate? value) {
    _endDate = value;
    notifyListeners();
  }

  void setNotes(String value) => _notes = value;

  // ------------------------------------------------------------- flow

  List<DoseTime> get doseTimes => _frequency == Frequency.daily
      ? [
          for (final m in {..._dailyTimes.whereType<int>()})
            DoseTime(minutes: m),
        ]
      : [
          for (final day in weekdays)
            if (_weeklyTimes[day] != null)
              DoseTime(minutes: _weeklyTimes[day]!, weekday: day),
        ];

  FormIssue? issueForStep(int step) {
    switch (step) {
      case 0:
        if (_name.trim().isEmpty) return FormIssue.nameRequired;
      case 1:
        if (_dosageAmount.trim().isEmpty) return FormIssue.dosageRequired;
        if (_frequency == Frequency.daily) {
          if (_dailyTimes.any((t) => t == null)) return FormIssue.timesRequired;
        } else {
          if (_weekdays.isEmpty) return FormIssue.weekdaysRequired;
          if (_weekdays.any((d) => _weeklyTimes[d] == null)) {
            return FormIssue.timesRequired;
          }
        }
      case 2:
        final end = _endDate;
        if (end != null && end.isBefore(_startDate)) {
          return FormIssue.endBeforeStart;
        }
    }
    return null;
  }

  /// Moves forward; returns the issue blocking it, if any.
  FormIssue? next() {
    final issue = issueForStep(_step);
    if (issue != null) return issue;
    if (_step < stepCount - 1) {
      _step++;
      notifyListeners();
    }
    return null;
  }

  bool back() {
    if (_step == 0) return false;
    _step--;
    notifyListeners();
    return true;
  }

  /// Validates every step and saves. Returns the issue if one is found.
  Future<(Medication?, FormIssue?)> save() async {
    for (var i = 0; i < stepCount; i++) {
      final issue = issueForStep(i);
      if (issue != null) {
        _step = i;
        notifyListeners();
        return (null, issue);
      }
    }
    _isSaving = true;
    notifyListeners();
    try {
      final original = _original;
      final now = _clock.nowUtc();
      final photoChanged = original?.imagePath != _imagePath;
      final medication = Medication(
        id: original?.id ?? newId(),
        ownerId: original?.ownerId ?? ownerId,
        name: _name.trim(),
        dosageAmount: _dosageAmount.trim(),
        dosageUnit: _unit,
        frequency: _frequency,
        times: doseTimes,
        startDate: _startDate,
        endDate: _endDate,
        endedAt: original?.endedAt,
        notes: _notes.trim().isEmpty ? null : _notes.trim(),
        imagePath: _imagePath,
        imageRemotePath: photoChanged ? null : original?.imageRemotePath,
        createdAt: original?.createdAt ?? now,
        updatedAt: now,
      );
      final saved = await _repository.save(medication);
      _temporaryImages.remove(_imagePath);
      if (photoChanged) await _images.deleteLocal(original?.imagePath);
      return (saved, null);
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // Photos picked but never saved.
    for (final path in _temporaryImages) {
      _images.deleteLocal(path);
    }
    super.dispose();
  }
}
