import 'package:drift/drift.dart';

import '../../core/utils/clock.dart';
import '../../domain/models/dose.dart';
import '../local/app_database.dart';
import '../local/mappers.dart';

/// Taken / skipped / rescheduled records for doses.
class DoseLogRepository {
  DoseLogRepository(this._db, {this._clock = const Clock()});

  final AppDatabase _db;
  final Clock _clock;

  /// Logs of [ownerId] whose planned time is within a day of `[from, to)`
  /// (rescheduled doses can move up to a day).
  Stream<List<DoseLog>> watchRange(String ownerId, DateTime from, DateTime to) {
    final query = _db.select(_db.doseLogs)
      ..where(
        (t) =>
            t.ownerId.equals(ownerId) &
            t.deletedAt.isNull() &
            t.scheduledAt.isBiggerOrEqualValue(
              from.subtract(const Duration(days: 1)),
            ) &
            t.scheduledAt.isSmallerThanValue(to.add(const Duration(days: 1))),
      );
    return query.watch().map((rows) => [for (final r in rows) r.toDomain()]);
  }

  Future<List<DoseLog>> getRange(String ownerId, DateTime from, DateTime to) =>
      watchRange(ownerId, from, to).first;

  /// Newest first.
  Stream<List<DoseLog>> watchForMedication(
    String medicationId, {
    int limit = 50,
  }) {
    final query = _db.select(_db.doseLogs)
      ..where((t) => t.medicationId.equals(medicationId) & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.scheduledAt)])
      ..limit(limit);
    return query.watch().map((rows) => [for (final r in rows) r.toDomain()]);
  }

  Future<DoseLog> record({
    required String ownerId,
    required String medicationId,
    required DateTime scheduledAt,
    required DoseLogStatus status,
    String? actedBy,
    DateTime? rescheduledTo,
  }) async {
    final now = _clock.nowUtc();
    final id = DoseLog.idFor(medicationId, scheduledAt);
    // Keep the new time when a rescheduled dose is later taken or skipped.
    final existing = await (_db.select(
      _db.doseLogs,
    )..where((t) => t.id.equals(id) & t.deletedAt.isNull())).getSingleOrNull();
    final newTime = rescheduledTo?.toUtc() ?? existing?.rescheduledTo?.toUtc();
    await _db
        .into(_db.doseLogs)
        .insertOnConflictUpdate(
          DoseLogsCompanion.insert(
            id: id,
            ownerId: ownerId,
            medicationId: medicationId,
            scheduledAt: scheduledAt.toUtc(),
            status: status.name,
            actedAt: now,
            rescheduledTo: Value(newTime),
            actedBy: Value(actedBy),
            updatedAt: now,
            deletedAt: const Value(null),
            dirty: const Value(true),
          ),
        );
    return DoseLog(
      id: id,
      ownerId: ownerId,
      medicationId: medicationId,
      scheduledAt: scheduledAt.toUtc(),
      status: status,
      actedAt: now,
      rescheduledTo: newTime,
      actedBy: actedBy,
      updatedAt: now,
    );
  }

  /// Clears what was recorded for a dose so it is pending again.
  Future<void> clear(String logId) async {
    final now = _clock.nowUtc();
    await (_db.update(_db.doseLogs)..where((t) => t.id.equals(logId))).write(
      DoseLogsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        dirty: const Value(true),
      ),
    );
  }
}
