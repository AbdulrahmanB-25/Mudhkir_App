import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mudhkir_app/core/utils/clock.dart';
import 'package:mudhkir_app/data/local/app_database.dart';
import 'package:mudhkir_app/data/repositories/dose_log_repository.dart';
import 'package:mudhkir_app/data/repositories/medication_repository.dart';
import 'package:mudhkir_app/data/services/image_store.dart';
import 'package:mudhkir_app/domain/models/dose.dart';
import 'package:mudhkir_app/domain/models/local_date.dart';
import 'package:mudhkir_app/domain/models/medication.dart';

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late MedicationRepository meds;
  late DoseLogRepository logs;

  Medication newMed({String id = 'm1', String owner = 'local'}) => Medication(
    id: id,
    ownerId: owner,
    name: 'Aspirin',
    dosageAmount: '100',
    dosageUnit: DosageUnit.mg,
    frequency: Frequency.daily,
    times: const [
      DoseTime(minutes: 20 * 60),
      DoseTime(minutes: 8 * 60),
    ],
    startDate: const LocalDate(2026, 3, 1),
    createdAt: DateTime.utc(2026, 3, 1),
    updatedAt: DateTime.utc(2026, 3, 1),
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 3, 1, 10));
    final images = ImageStore(baseDirectory: () async => Directory.systemTemp);
    meds = MedicationRepository(db, images, clock: clock);
    logs = DoseLogRepository(db, clock: clock);
  });

  tearDown(() => db.close());

  test('saves, reads back and sorts dose times', () async {
    await meds.save(newMed());
    final all = await meds.getAll('local');
    expect(all, hasLength(1));
    expect(all.single.times.map((t) => t.minutes), [480, 1200]);
    expect(all.single.updatedAt, clock.nowUtc());
    expect(await meds.getAll('someone-else'), isEmpty);
  });

  test('saving marks the row dirty for sync', () async {
    await meds.save(newMed());
    final row = await db.select(db.medications).getSingle();
    expect(row.dirty, isTrue);
  });

  test('delete is a soft delete that also removes dose logs', () async {
    await meds.save(newMed());
    await logs.record(
      ownerId: 'local',
      medicationId: 'm1',
      scheduledAt: DateTime.utc(2026, 3, 1, 5),
      status: DoseLogStatus.taken,
    );
    await meds.delete('m1');

    expect(await meds.get('m1'), isNull);
    final rows = await db.select(db.medications).get();
    expect(rows.single.deletedAt, isNotNull);
    expect(
      await logs.getRange(
        'local',
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 2),
      ),
      isEmpty,
    );
  });

  test('end stops a medication and resume restarts it', () async {
    await meds.save(newMed());
    await meds.end('m1');
    expect((await meds.get('m1'))!.isEnded, isTrue);
    await meds.resume('m1');
    expect((await meds.get('m1'))!.isEnded, isFalse);
  });

  test('one log per dose; rescheduled time is kept when taken', () async {
    final at = DateTime.utc(2026, 3, 1, 5);
    final later = DateTime.utc(2026, 3, 1, 7);
    await logs.record(
      ownerId: 'local',
      medicationId: 'm1',
      scheduledAt: at,
      status: DoseLogStatus.rescheduled,
      rescheduledTo: later,
    );
    await logs.record(
      ownerId: 'local',
      medicationId: 'm1',
      scheduledAt: at,
      status: DoseLogStatus.taken,
    );
    final all = await logs.getRange(
      'local',
      DateTime.utc(2026, 3, 1),
      DateTime.utc(2026, 3, 2),
    );
    expect(all, hasLength(1));
    expect(all.single.status, DoseLogStatus.taken);
    expect(all.single.rescheduledTo, later);

    await logs.clear(all.single.id);
    expect(
      await logs.getRange(
        'local',
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 3, 2),
      ),
      isEmpty,
    );
  });
}
