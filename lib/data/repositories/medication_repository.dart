import 'package:drift/drift.dart';

import '../../core/utils/clock.dart';
import '../../domain/models/medication.dart';
import '../local/app_database.dart';
import '../local/mappers.dart';
import '../services/image_store.dart';

/// Medications on this device. Every write is local first and marked dirty;
/// the sync service uploads it later when online.
class MedicationRepository {
  MedicationRepository(this._db, this._images, {this._clock = const Clock()});

  final AppDatabase _db;
  final ImageStore _images;
  final Clock _clock;

  SimpleSelectStatement<$MedicationsTable, MedicationRow> _owned(
    String ownerId,
  ) => _db.select(_db.medications)
    ..where((t) => t.ownerId.equals(ownerId) & t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm.asc(t.name)]);

  Stream<List<Medication>> watchAll(String ownerId) =>
      _owned(ownerId)
          .watch()
          .map((rows) => [for (final r in rows) r.toDomain()]);

  Future<List<Medication>> getAll(String ownerId) async => [
    for (final r in await _owned(ownerId).get()) r.toDomain(),
  ];

  Stream<Medication?> watch(String id) =>
      (_db.select(_db.medications)
            ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .watchSingleOrNull()
          .map((r) => r?.toDomain());

  Future<Medication?> get(String id) async {
    final row = await (_db.select(
      _db.medications,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    return row?.toDomain();
  }

  /// Inserts or updates [medication], stamping a new `updatedAt`.
  Future<Medication> save(Medication medication) async {
    final saved = medication.copyWith(updatedAt: _clock.nowUtc());
    await _db.into(_db.medications).insertOnConflictUpdate(saved.toCompanion());
    return saved;
  }

  /// Stops a medication now. Its history stays; no more reminders.
  Future<void> end(String id) async {
    final medication = await get(id);
    if (medication == null) return;
    await save(medication.copyWith(endedAt: () => _clock.nowUtc()));
  }

  /// Reverses [end].
  Future<void> resume(String id) async {
    final medication = await get(id);
    if (medication == null) return;
    await save(medication.copyWith(endedAt: () => null));
  }

  /// Soft-deletes the medication and its dose logs and removes the photo.
  Future<void> delete(String id) async {
    final medication = await get(id);
    if (medication == null) return;
    final now = _clock.nowUtc();
    await _db.transaction(() async {
      await (_db.update(_db.medications)..where((t) => t.id.equals(id))).write(
        MedicationsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await (_db.update(
        _db.doseLogs,
      )..where((t) => t.medicationId.equals(id) & t.deletedAt.isNull())).write(
        DoseLogsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
    });
    await _images.deleteLocal(medication.imagePath);
  }
}
