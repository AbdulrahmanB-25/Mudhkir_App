import 'package:drift/drift.dart';

import '../../core/utils/clock.dart';
import '../../core/utils/ids.dart';
import '../../domain/models/companion_link.dart';
import '../local/app_database.dart';
import '../local/mappers.dart';
import '../remote/remote_store.dart';

enum InviteResult { sent, notFound, isSelf, alreadyLinked }

/// Caregiver links. Inviting needs the internet (to find the person by
/// email); everything else works on local data and syncs later.
class CompanionRepository {
  CompanionRepository(this._db, this._remote, {this._clock = const Clock()});

  final AppDatabase _db;
  final RemoteStore? _remote;
  final Clock _clock;

  Stream<List<CompanionLink>> watchLinks(String userId) {
    final query = _db.select(_db.companionLinks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            (t.caregiverId.equals(userId) | t.patientId.equals(userId)),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch().map((rows) => [for (final r in rows) r.toDomain()]);
  }

  /// People [caregiverId] looks after (accepted links only).
  Future<List<CompanionLink>> acceptedPatients(String caregiverId) async {
    final rows =
        await (_db.select(_db.companionLinks)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.caregiverId.equals(caregiverId) &
                  t.status.equals(LinkStatus.accepted.name),
            ))
            .get();
    return [for (final r in rows) r.toDomain()];
  }

  Stream<CompanionLink?> watchLink(String id) =>
      (_db.select(_db.companionLinks)
            ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
          .watchSingleOrNull()
          .map((r) => r?.toDomain());

  Future<InviteResult> invite({
    required String caregiverId,
    required String caregiverName,
    required String email,
    required String displayName,
    String? relationship,
  }) async {
    final remote = _remote;
    if (remote == null) throw StateError('Cloud is not configured');
    final profile = await remote.findProfileByEmail(email);
    if (profile == null) return InviteResult.notFound;
    if (profile.id == caregiverId) return InviteResult.isSelf;

    final existing =
        await (_db.select(_db.companionLinks)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.caregiverId.equals(caregiverId) &
                  t.patientId.equals(profile.id),
            ))
            .getSingleOrNull();
    if (existing != null) return InviteResult.alreadyLinked;

    final now = _clock.nowUtc();
    await _db
        .into(_db.companionLinks)
        .insert(
          CompanionLinksCompanion.insert(
            id: newId(),
            caregiverId: caregiverId,
            patientId: profile.id,
            caregiverName: Value(caregiverName),
            patientName: Value(
              displayName.trim().isEmpty ? profile.name : displayName.trim(),
            ),
            patientEmail: Value(email.trim().toLowerCase()),
            relationship: Value(relationship?.trim()),
            status: LinkStatus.pending.name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return InviteResult.sent;
  }

  Future<void> accept(String linkId) => _update(
    linkId,
    CompanionLinksCompanion(status: Value(LinkStatus.accepted.name)),
  );

  Future<void> rename(String linkId, String name, String? relationship) =>
      _update(
        linkId,
        CompanionLinksCompanion(
          patientName: Value(name.trim()),
          relationship: Value(relationship?.trim()),
        ),
      );

  /// Declines an invite or stops sharing (either side can do this).
  Future<void> remove(String linkId) => _update(
    linkId,
    CompanionLinksCompanion(deletedAt: Value(_clock.nowUtc())),
  );

  Future<void> _update(String linkId, CompanionLinksCompanion changes) async {
    await (_db.update(
      _db.companionLinks,
    )..where((t) => t.id.equals(linkId))).write(
      changes.copyWith(
        updatedAt: Value(_clock.nowUtc()),
        dirty: const Value(true),
      ),
    );
  }

  /// Remembers that a missed-dose alert was shown. Returns false if it was
  /// already shown before.
  Future<bool> markAlerted(String doseLogId) async {
    return _db.transaction(() async {
      final existing = await (_db.select(
        _db.companionAlerts,
      )..where((t) => t.doseLogId.equals(doseLogId))).getSingleOrNull();
      if (existing != null) return false;
      await _db
          .into(_db.companionAlerts)
          .insert(
            CompanionAlertsCompanion.insert(
              doseLogId: doseLogId,
              notifiedAt: _clock.nowUtc(),
            ),
          );
      return true;
    });
  }
}
