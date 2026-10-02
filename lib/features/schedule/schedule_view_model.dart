import '../../domain/models/dose.dart';
import '../../domain/models/local_date.dart';
import '../shared/dose_feed.dart';

/// Summary of one calendar day, for the coloured dots under each date.
enum DayMark { none, planned, allTaken, missed }

class ScheduleViewModel extends DoseFeed {
  ScheduleViewModel({
    required super.ownerId,
    required super.medications,
    required super.logs,
    super.calculator,
    super.clock,
  }) {
    _selected = today;
    _focused = today;
    _watchMonth();
  }

  late LocalDate _selected;
  late LocalDate _focused;
  List<DoseInstance> _selectedDoses = const [];
  Map<LocalDate, DayMark> _marks = const {};

  LocalDate get selectedDay => _selected;
  LocalDate get focusedDay => _focused;
  List<DoseInstance> get selectedDoses => _selectedDoses;
  DayMark markFor(LocalDate day) => _marks[day] ?? DayMark.none;

  void selectDay(LocalDate day) {
    _selected = day;
    _focused = day;
    _watchMonth();
    onDataChanged();
    notifyListeners();
  }

  void changeMonth(LocalDate focused) {
    _focused = focused;
    _watchMonth();
  }

  void goToToday() => selectDay(today);

  void _watchMonth() {
    // The visible grid can show up to a week of the next/previous months.
    final first = LocalDate(_focused.year, _focused.month, 1).addDays(-7);
    final last = LocalDate(_focused.year, _focused.month + 1, 1).addDays(7);
    watchRange(startOf(first), startOf(last));
  }

  @override
  void onDataChanged() {
    _selectedDoses = dosesOn(_selected);
    final first = LocalDate(_focused.year, _focused.month, 1).addDays(-7);
    final last = LocalDate(_focused.year, _focused.month + 1, 1).addDays(7);
    final byDay = <LocalDate, List<DoseInstance>>{};
    for (final dose in dosesBetween(startOf(first), startOf(last))) {
      final day = LocalDate.fromDateTime(dose.effectiveAt.toLocal());
      (byDay[day] ??= []).add(dose);
    }
    _marks = {
      for (final MapEntry(key: day, value: doses) in byDay.entries)
        day: doses.any((d) => d.status == DoseStatus.missed)
            ? DayMark.missed
            : doses.every((d) => d.isDone)
            ? DayMark.allTaken
            : DayMark.planned,
    };
  }
}
