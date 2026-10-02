import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mudhkir_app/core/utils/clock.dart';
import 'package:mudhkir_app/data/local/app_database.dart';
import 'package:mudhkir_app/data/repositories/medication_repository.dart';
import 'package:mudhkir_app/data/services/image_store.dart';
import 'package:mudhkir_app/domain/models/local_date.dart';
import 'package:mudhkir_app/domain/models/medication.dart';
import 'package:mudhkir_app/features/medication_form/medication_form_view_model.dart';

void main() {
  late AppDatabase db;
  late MedicationRepository repo;
  late ImageStore images;
  final clock = FixedClock(DateTime(2026, 3, 1, 10));

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    images = ImageStore(baseDirectory: () async => Directory.systemTemp);
    repo = MedicationRepository(db, images, clock: clock);
  });

  tearDown(() => db.close());

  MedicationFormViewModel newForm({String? id}) => MedicationFormViewModel(
    ownerId: 'local',
    repository: repo,
    images: images,
    medicationId: id,
    clock: clock,
  );

  test('blocks each step until it is complete', () {
    final vm = newForm();
    expect(vm.next(), FormIssue.nameRequired);
    vm.setName('Panadol');
    expect(vm.next(), isNull);
    expect(vm.step, 1);

    expect(vm.next(), FormIssue.dosageRequired);
    vm.setDosageAmount('500');
    expect(vm.next(), FormIssue.timesRequired);
    vm.setDailyTime(0, 8 * 60);
    expect(vm.next(), isNull);
    expect(vm.step, 2);

    vm.setEndDate(const LocalDate(2026, 2, 1));
    expect(vm.issueForStep(2), FormIssue.endBeforeStart);
    vm.dispose();
  });

  test('first daily time spreads the others; manual times are kept', () {
    final vm = newForm()..setTimesPerDay(3);
    vm.setDailyTime(0, 8 * 60);
    expect(vm.dailyTimes, [480, 960, 0]);
    expect(vm.isDailyAuto(1), isTrue);

    vm.setDailyTime(2, 22 * 60);
    vm.setDailyTime(0, 7 * 60);
    expect(vm.dailyTimes, [420, 900, 1320]);
    expect(vm.isDailyAuto(2), isFalse);
    vm.dispose();
  });

  test('weekly: limits days and copies the first time', () {
    final vm = newForm()..setFrequency(Frequency.weekly);
    for (final day in [1, 2, 3, 4, 5, 6]) {
      expect(vm.toggleWeekday(day), isTrue);
    }
    expect(vm.toggleWeekday(7), isFalse);
    expect(vm.applyFirstTimeToAll(), isFalse);
    vm.setWeeklyTime(1, 9 * 60);
    expect(vm.applyFirstTimeToAll(), isTrue);
    expect(vm.doseTimes.map((t) => (t.weekday, t.minutes)), [
      for (final d in [1, 2, 3, 4, 5, 6]) (d, 540),
    ]);
    vm.dispose();
  });

  test('saves a new medication and edits it', () async {
    final vm = newForm()
      ..setName(' Augmentin ')
      ..setDosageAmount('1')
      ..setUnit(DosageUnit.tablet)
      ..setTimesPerDay(2)
      ..setDailyTime(0, 9 * 60);
    final (saved, issue) = await vm.save();
    expect(issue, isNull);
    expect(saved!.name, 'Augmentin');
    expect(saved.times.map((t) => t.minutes), [540, 1260]);
    expect(saved.startDate, const LocalDate(2026, 3, 1));
    vm.dispose();

    final edit = newForm(id: saved.id);
    await pumpEventQueue();
    expect(edit.isEditing, isTrue);
    expect(edit.name, 'Augmentin');
    expect(edit.timesPerDay, 2);
    edit.setName('Augmentin 1g');
    await edit.save();
    expect((await repo.get(saved.id))!.name, 'Augmentin 1g');
    expect(await repo.getAll('local'), hasLength(1));
    edit.dispose();
  });
}
