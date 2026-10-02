import 'package:flutter_test/flutter_test.dart';
import 'package:mudhkir_app/domain/models/dose.dart';
import 'package:mudhkir_app/domain/models/local_date.dart';
import 'package:mudhkir_app/domain/models/medication.dart';
import 'package:mudhkir_app/domain/services/dose_calculator.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Medication med({
  String id = 'm1',
  Frequency frequency = Frequency.daily,
  List<DoseTime> times = const [DoseTime(minutes: 8 * 60)],
  LocalDate start = const LocalDate(2026, 1, 1),
  LocalDate? end,
  DateTime? endedAt,
}) {
  final created = DateTime.utc(2026);
  return Medication(
    id: id,
    ownerId: 'u1',
    name: 'Panadol $id',
    dosageAmount: '500',
    dosageUnit: DosageUnit.mg,
    frequency: frequency,
    times: times,
    startDate: start,
    endDate: end,
    endedAt: endedAt,
    createdAt: created,
    updatedAt: created,
  );
}

DoseLog logFor(
  Medication m,
  DateTime scheduledAt,
  DoseLogStatus status, {
  DateTime? rescheduledTo,
}) => DoseLog(
  id: DoseLog.idFor(m.id, scheduledAt),
  ownerId: m.ownerId,
  medicationId: m.id,
  scheduledAt: scheduledAt,
  status: status,
  actedAt: scheduledAt,
  rescheduledTo: rescheduledTo,
  updatedAt: scheduledAt,
);

void main() {
  late tz.Location riyadh;
  late tz.Location newYork;
  const calc = DoseCalculator();

  setUpAll(() {
    tzdata.initializeTimeZones();
    riyadh = tz.getLocation('Asia/Riyadh'); // UTC+3, no DST
    newYork = tz.getLocation('America/New_York');
  });

  group('occurrences', () {
    test('daily times are produced every day in local time', () {
      final m = med(
        times: const [
          DoseTime(minutes: 8 * 60),
          DoseTime(minutes: 20 * 60),
        ],
      );
      final result = calc.occurrences(
        m,
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 3),
        riyadh,
      );
      expect(result, [
        DateTime.utc(2026, 3, 1, 5), // 08:00 Riyadh
        DateTime.utc(2026, 3, 1, 17), // 20:00 Riyadh
        DateTime.utc(2026, 3, 2, 5),
        DateTime.utc(2026, 3, 2, 17),
      ]);
    });

    test('weekly times only fall on their weekday', () {
      // 2026-03-02 is a Monday (1), 2026-03-04 a Wednesday (3).
      final m = med(
        frequency: Frequency.weekly,
        times: const [
          DoseTime(minutes: 9 * 60, weekday: 1),
          DoseTime(minutes: 21 * 60, weekday: 3),
        ],
      );
      final result = calc.occurrences(
        m,
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 8),
        riyadh,
      );
      expect(result, [
        DateTime.utc(2026, 3, 2, 6),
        DateTime.utc(2026, 3, 4, 18),
      ]);
    });

    test('respects start date, end date and early stop', () {
      final m = med(
        start: const LocalDate(2026, 3, 2),
        end: const LocalDate(2026, 3, 4),
      );
      final result = calc.occurrences(
        m,
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 10),
        riyadh,
      );
      expect(result, [
        DateTime.utc(2026, 3, 2, 5),
        DateTime.utc(2026, 3, 3, 5),
        DateTime.utc(2026, 3, 4, 5),
      ]);

      final stopped = med(endedAt: DateTime.utc(2026, 3, 3, 12));
      expect(
        calc.occurrences(
          stopped,
          DateTime.utc(2026, 3, 2),
          DateTime.utc(2026, 3, 6),
          riyadh,
        ),
        [DateTime.utc(2026, 3, 2, 5), DateTime.utc(2026, 3, 3, 5)],
      );
    });

    test('keeps wall-clock time across a daylight-saving change', () {
      // US clocks moved forward on 2026-03-08.
      final m = med(times: const [DoseTime(minutes: 9 * 60)]);
      final result = calc.occurrences(
        m,
        DateTime.utc(2026, 3, 7),
        DateTime.utc(2026, 3, 10),
        newYork,
      );
      expect(result, [
        DateTime.utc(2026, 3, 7, 14), // 09:00 EST (UTC-5)
        DateTime.utc(2026, 3, 8, 13), // 09:00 EDT (UTC-4)
        DateTime.utc(2026, 3, 9, 13),
      ]);
    });
  });

  group('doses', () {
    final m = med(
      times: const [
        DoseTime(minutes: 8 * 60),
        DoseTime(minutes: 20 * 60),
      ],
    );
    final morning = DateTime.utc(2026, 3, 1, 5);
    final evening = DateTime.utc(2026, 3, 1, 17);
    final dayStart = DateTime.utc(2026, 2, 28, 21); // Riyadh midnight
    final dayEnd = DateTime.utc(2026, 3, 1, 21);

    List<DoseInstance> today(List<DoseLog> logs, DateTime now) => calc.doses(
      medications: [m],
      logs: logs,
      from: dayStart,
      to: dayEnd,
      now: now,
      location: riyadh,
    );

    test('derives status from logs and the clock', () {
      final now = DateTime.utc(2026, 3, 1, 17, 30);
      var doses = today(const [], now);
      expect(doses.map((d) => d.status), [DoseStatus.missed, DoseStatus.due]);

      doses = today([logFor(m, morning, DoseLogStatus.taken)], now);
      expect(doses.map((d) => d.status), [DoseStatus.taken, DoseStatus.due]);

      doses = today([
        logFor(m, evening, DoseLogStatus.skipped),
      ], DateTime.utc(2026, 3, 1, 4));
      expect(doses.map((d) => d.status), [
        DoseStatus.upcoming,
        DoseStatus.skipped,
      ]);
    });

    test('a rescheduled dose moves to its new time', () {
      final newTime = DateTime.utc(2026, 3, 1, 19);
      final doses = today([
        logFor(m, morning, DoseLogStatus.rescheduled, rescheduledTo: newTime),
      ], DateTime.utc(2026, 3, 1, 12));
      expect(doses.map((d) => d.effectiveAt), [evening, newTime]);
      expect(doses.last.status, DoseStatus.upcoming);
      expect(doses.last.isRescheduled, isTrue);
    });

    test('nextDose skips doses already handled', () {
      final next = calc.nextDose(
        medications: [m],
        logs: [logFor(m, morning, DoseLogStatus.taken)],
        now: DateTime.utc(2026, 3, 1, 5, 10),
        location: riyadh,
      );
      expect(next?.scheduledAt, evening);
    });
  });

  test('evenlySpaced matches the original auto-fill', () {
    expect(DoseCalculator.evenlySpaced(8 * 60, 3), [480, 960, 0]);
    expect(DoseCalculator.evenlySpaced(9 * 60, 1), [540]);
  });
}
