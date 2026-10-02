import 'package:timezone/timezone.dart' as tz;

import '../models/dose.dart';
import '../models/local_date.dart';
import '../models/medication.dart';

/// Turns medication schedules and dose logs into concrete doses.
///
/// Pure and synchronous so it can be unit-tested and reused by the UI, the
/// reminder scheduler and the background companion check.
class DoseCalculator {
  const DoseCalculator({this.missedAfter = const Duration(hours: 1)});

  /// How long after its time an untaken dose counts as missed.
  final Duration missedAfter;

  /// Planned dose times (UTC) of [medication] in `[from, to)`, using the
  /// wall-clock times of [location].
  List<DateTime> occurrences(
    Medication medication,
    DateTime from,
    DateTime to,
    tz.Location location,
  ) {
    if (medication.times.isEmpty || !from.isBefore(to)) return const [];

    final firstDay = LocalDate.fromDateTime(tz.TZDateTime.from(from, location));
    final lastDay = LocalDate.fromDateTime(tz.TZDateTime.from(to, location));
    final result = <DateTime>[];

    for (var day = firstDay; !day.isAfter(lastDay); day = day.addDays(1)) {
      if (day.isBefore(medication.startDate)) continue;
      final endDate = medication.endDate;
      if (endDate != null && day.isAfter(endDate)) break;

      for (final time in medication.times) {
        if (time.weekday != null && time.weekday != day.weekday) continue;
        final at = tz.TZDateTime(
          location,
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ).toUtc();
        if (at.isBefore(from) || !at.isBefore(to)) continue;
        final endedAt = medication.endedAt;
        if (endedAt != null && !at.isBefore(endedAt)) continue;
        result.add(at);
      }
    }
    result.sort();
    return result;
  }

  /// All doses whose effective time (after rescheduling) is in `[from, to)`.
  List<DoseInstance> doses({
    required Iterable<Medication> medications,
    required Iterable<DoseLog> logs,
    required DateTime from,
    required DateTime to,
    required DateTime now,
    required tz.Location location,
  }) {
    final logsById = {for (final log in logs) log.id: log};
    final result = <DoseInstance>[];
    // A dose can be moved by up to a day, so look a day beyond the window.
    final searchFrom = from.subtract(const Duration(days: 1));
    final searchTo = to.add(const Duration(days: 1));

    for (final medication in medications) {
      for (final at in occurrences(
        medication,
        searchFrom,
        searchTo,
        location,
      )) {
        final log = logsById[DoseLog.idFor(medication.id, at)];
        final effectiveAt = log?.rescheduledTo ?? at;
        if (effectiveAt.isBefore(from) || !effectiveAt.isBefore(to)) continue;
        result.add(
          DoseInstance(
            medication: medication,
            scheduledAt: at,
            log: log,
            status: statusFor(log, effectiveAt, now),
          ),
        );
      }
    }
    result.sort((a, b) {
      final byTime = a.effectiveAt.compareTo(b.effectiveAt);
      return byTime != 0
          ? byTime
          : a.medication.name.compareTo(b.medication.name);
    });
    return result;
  }

  DoseStatus statusFor(DoseLog? log, DateTime effectiveAt, DateTime now) {
    switch (log?.status) {
      case DoseLogStatus.taken:
        return DoseStatus.taken;
      case DoseLogStatus.skipped:
        return DoseStatus.skipped;
      case DoseLogStatus.rescheduled:
      case null:
        if (now.isBefore(effectiveAt)) return DoseStatus.upcoming;
        if (now.isBefore(effectiveAt.add(missedAfter))) return DoseStatus.due;
        return DoseStatus.missed;
    }
  }

  /// The next dose that still needs action (due or upcoming) at or after
  /// [now] minus [missedAfter].
  DoseInstance? nextDose({
    required Iterable<Medication> medications,
    required Iterable<DoseLog> logs,
    required DateTime now,
    required tz.Location location,
    Duration lookAhead = const Duration(days: 7),
  }) {
    final candidates = doses(
      medications: medications,
      logs: logs,
      from: now.subtract(missedAfter),
      to: now.add(lookAhead),
      now: now,
      location: location,
    );
    for (final dose in candidates) {
      if (dose.status == DoseStatus.due || dose.status == DoseStatus.upcoming) {
        return dose;
      }
    }
    return null;
  }

  /// Spreads [count] daily doses evenly over 24 hours starting at [first],
  /// the way the original app auto-filled the remaining times.
  static List<int> evenlySpaced(int first, int count) {
    if (count <= 0) return const [];
    final interval = (24 * 60 / count).round();
    return [for (var i = 0; i < count; i++) (first + interval * i) % (24 * 60)];
  }
}
