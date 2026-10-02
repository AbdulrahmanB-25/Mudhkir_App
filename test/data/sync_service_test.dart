import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mudhkir_app/core/utils/clock.dart';
import 'package:mudhkir_app/data/local/app_database.dart';
import 'package:mudhkir_app/data/repositories/auth_repository.dart';
import 'package:mudhkir_app/data/repositories/companion_repository.dart';
import 'package:mudhkir_app/data/repositories/dose_log_repository.dart';
import 'package:mudhkir_app/data/repositories/medication_repository.dart';
import 'package:mudhkir_app/data/services/image_store.dart';
import 'package:mudhkir_app/data/sync/sync_service.dart';
import 'package:mudhkir_app/domain/models/dose.dart';
import 'package:mudhkir_app/domain/models/local_date.dart';
import 'package:mudhkir_app/domain/models/medication.dart';
import 'package:mudhkir_app/data/remote/remote_store.dart';

import '../helpers/fakes.dart';

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late FakeAuth auth;
  late FakeRemoteStore remote;
  late ImageStore images;
  late MedicationRepository meds;
  late DoseLogRepository logs;
  late SyncService sync;
  late Directory tempDir;

  Medication med(String id, String owner) => Medication(
    id: id,
    ownerId: owner,
    name: 'Metformin',
    dosageAmount: '500',
    dosageUnit: DosageUnit.mg,
    frequency: Frequency.daily,
    times: const [DoseTime(minutes: 9 * 60)],
    startDate: const LocalDate(2026, 3, 1),
    createdAt: DateTime.utc(2026, 3, 1),
    updatedAt: DateTime.utc(2026, 3, 1),
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mudhkir_test');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    clock = FixedClock(DateTime.utc(2026, 3, 1, 10));
    auth = FakeAuth();
    remote = FakeRemoteStore();
    images = ImageStore(baseDirectory: () async => tempDir);
    meds = MedicationRepository(db, images, clock: clock);
    logs = DoseLogRepository(db, clock: clock);
    sync = SyncService(
      db: db,
      auth: auth,
      images: images,
      remote: remote,
      clock: clock,
      debounce: const Duration(hours: 1), // tests call syncNow directly
    );
    await sync.start();
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('does nothing for guests', () async {
    await meds.save(med('m1', AuthRepository.guestId));
    await sync.syncNow();
    expect(remote.tables, isEmpty);
    expect(sync.state, SyncState.disabled);
  });

  test('guest data moves into the account on sign-in and is pushed', () async {
    await meds.save(med('m1', AuthRepository.guestId));
    await logs.record(
      ownerId: AuthRepository.guestId,
      medicationId: 'm1',
      scheduledAt: DateTime.utc(2026, 3, 1, 6),
      status: DoseLogStatus.taken,
    );

    auth.signInAs('user-1');
    await pumpEventQueue();
    await sync.syncNow();

    expect(await meds.getAll('user-1'), hasLength(1));
    expect(remote.tables['medications']!['m1']!['owner_id'], 'user-1');
    final remoteLog = remote.tables['dose_logs']!.values.single;
    expect(remoteLog['owner_id'], 'user-1');
    expect(remoteLog['acted_by'], 'user-1');
    expect(await sync.pendingCount(), 0);
    expect(sync.state, SyncState.idle);
  });

  test('pulls rows written on another device', () async {
    auth.signInAs('user-1');
    await pumpEventQueue();
    remote.serverWrite('medications', {
      'id': 'remote-med',
      'owner_id': 'user-1',
      'name': 'Lipitor',
      'dosage_amount': '20',
      'dosage_unit': 'mg',
      'frequency': 'daily',
      'times': [
        {'minutes': 1260},
      ],
      'start_date': '2026-02-01',
      'end_date': null,
      'ended_at': null,
      'notes': null,
      'image_remote_path': null,
      'created_at': '2026-02-01T00:00:00.000Z',
      'updated_at': '2026-02-01T00:00:00.000Z',
      'deleted_at': null,
    });

    await sync.syncNow();
    final pulled = await meds.get('remote-med');
    expect(pulled?.name, 'Lipitor');
    expect(pulled?.times.single.minutes, 1260);
    expect(await sync.pendingCount(), 0);
  });

  test('newest change wins on conflict', () async {
    auth.signInAs('user-1');
    await pumpEventQueue();
    await meds.save(med('m1', 'user-1'));
    await sync.syncNow();

    // Server copy changed later than the local edit below.
    clock.current = DateTime.utc(2026, 3, 1, 11);
    await meds.save((await meds.get('m1'))!.copyWith(name: 'Local edit'));
    remote.serverWrite('medications', {
      ...remote.tables['medications']!['m1']!,
      'name': 'Server edit',
      'updated_at': '2026-03-01T12:00:00.000Z',
    });
    await sync.syncNow();
    // The local change was pushed first, then the newer server row won.
    expect((await meds.get('m1'))!.name, 'Server edit');

    // A newer local change beats an older server row.
    clock.current = DateTime.utc(2026, 3, 1, 13);
    await meds.save((await meds.get('m1'))!.copyWith(name: 'Newest local'));
    remote.serverWrite('medications', {
      ...remote.tables['medications']!['m1']!,
      'name': 'Stale server',
      'updated_at': '2026-03-01T12:30:00.000Z',
    });
    await sync.syncNow();
    expect((await meds.get('m1'))!.name, 'Newest local');
    expect(remote.tables['medications']!['m1']!['name'], 'Newest local');
  });

  test('offline keeps changes pending and reports offline', () async {
    auth.signInAs('user-1');
    await pumpEventQueue();
    remote.offline = true;
    await meds.save(med('m1', 'user-1'));
    await sync.syncNow();
    expect(sync.state, SyncState.offline);
    expect(await sync.pendingCount(), 1);

    remote.offline = false;
    await sync.syncNow();
    expect(await sync.pendingCount(), 0);
    expect(remote.tables['medications'], contains('m1'));
  });

  test('photos are uploaded and downloaded', () async {
    auth.signInAs('user-1');
    await pumpEventQueue();
    final source = File('${tempDir.path}/pill.jpg')
      ..writeAsBytesSync([1, 2, 3]);
    final local = await images.saveCopy(source.path);
    await meds.save(med('m1', 'user-1').copyWith(imagePath: () => local));
    await sync.syncNow();
    final remotePath =
        remote.tables['medications']!['m1']!['image_remote_path'] as String;
    expect(remote.images[remotePath], [1, 2, 3]);

    // Another device without the file downloads it.
    await sync.clearAccountData();
    await sync.syncNow();
    final downloaded = (await meds.get('m1'))!.imagePath;
    expect(downloaded, isNotNull);
    expect(File(downloaded!).readAsBytesSync(), [1, 2, 3]);
  });

  test('signing out clears account data but keeps guest data', () async {
    await meds.save(med('guest-med', AuthRepository.guestId));
    auth.signInAs('user-1');
    await pumpEventQueue();
    await sync.syncNow();
    await meds.save(med('new-guest-med', AuthRepository.guestId));

    auth.signOutNow();
    await pumpEventQueue();
    expect(await meds.getAll('user-1'), isEmpty);
    expect(await meds.getAll(AuthRepository.guestId), hasLength(1));
  });

  test('caregiver receives the patient data only after accepting', () async {
    final companions = CompanionRepository(db, remote, clock: clock);
    remote.profilesByEmail['mom@example.com'] = const RemoteProfile(
      id: 'mom',
      name: 'Mom',
    );
    // Mom's medication already on the server (RLS lets the caregiver see it
    // once the link is accepted; the fake returns it either way, so this test
    // checks the local pruning).
    remote.serverWrite('medications', {
      'id': 'mom-med',
      'owner_id': 'mom',
      'name': 'Insulin',
      'dosage_amount': '10',
      'dosage_unit': 'unit',
      'frequency': 'daily',
      'times': [
        {'minutes': 480},
      ],
      'start_date': '2026-01-01',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });

    auth.signInAs('me');
    await pumpEventQueue();
    final result = await companions.invite(
      caregiverId: 'me',
      caregiverName: 'Son',
      email: 'Mom@Example.com',
      displayName: '',
    );
    expect(result, InviteResult.sent);
    await sync.syncNow();
    expect(await meds.getAll('mom'), isEmpty); // pending: pruned

    final link = remote.tables['companion_links']!.values.single;
    expect(link['patient_name'], 'Mom');
    remote.serverWrite('companion_links', {
      ...link,
      'status': 'accepted',
      'updated_at': '2026-03-01T10:30:00.000Z',
    });
    remote.serverWrite('medications', {
      ...remote.tables['medications']!['mom-med']!,
    });
    await sync.syncNow();
    expect((await meds.getAll('mom')).single.name, 'Insulin');
    expect(await companions.acceptedPatients('me'), hasLength(1));
  });
}
