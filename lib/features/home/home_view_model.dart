import '../../domain/models/dose.dart';
import '../shared/dose_feed.dart';

class HomeViewModel extends DoseFeed {
  HomeViewModel({
    required super.ownerId,
    required super.medications,
    required super.logs,
    super.calculator,
    super.clock,
  }) {
    final start = startOf(today);
    // Today plus a week, so "next dose" can be shown when today is done.
    watchRange(start, start.add(const Duration(days: 8)));
  }

  List<DoseInstance> _today = const [];
  DoseInstance? _next;

  List<DoseInstance> get todayDoses => _today;
  DoseInstance? get nextDose => _next;
  int get takenToday =>
      _today.where((d) => d.status == DoseStatus.taken).length;
  int get missedToday =>
      _today.where((d) => d.status == DoseStatus.missed).length;
  bool get hasMedications => medications.isNotEmpty;

  @override
  void onDataChanged() {
    _today = dosesOn(today);
    final candidates = dosesBetween(
      now.subtract(calculator.missedAfter),
      now.add(const Duration(days: 7)),
    );
    _next = candidates
        .where(
          (d) => d.status == DoseStatus.due || d.status == DoseStatus.upcoming,
        )
        .firstOrNull;
  }
}
