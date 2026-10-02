import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../core/utils/log.dart';
import '../local/app_database.dart';
import '../remote/remote_store.dart';
import '../repositories/auth_repository.dart';
import '../services/image_store.dart';
import 'sync_codecs.dart';

enum SyncState { disabled, idle, syncing, offline, error }

/// Keeps the local database and Supabase in step.
///
/// The phone is the source of truth: every change is written locally first
/// and flagged `dirty`. When signed in and online this service
///  1. uploads new photos, then pushes dirty rows (upsert);
///  2. pulls rows changed on the server since the last checkpoint;
///  3. resolves conflicts by keeping the newest `updated_at`.
///
/// It also moves guest data into the account on first sign-in and clears
/// account data from the phone on sign-out.
class SyncService extends ChangeNotifier {
  SyncService({
    required this._db,
    required this._auth,
    required this._images,
    this._remote,
    this._connectivity,
    this._clock = const Clock(),
    this.debounce = const Duration(seconds: 3),
  });

  final AppDatabase _db;
  final AuthRepository _auth;
  final ImageStore _images;
  final RemoteStore? _remote;
  final Stream<List<ConnectivityResult>>? _connectivity;
  final Clock _clock;
  final Duration debounce;

  static const _ownerKey = 'sync.owner';
  static const _lastSyncKey = 'sync.last';
  static String _checkpointKey(String table) => 'sync.checkpoint.$table';

  /// Pull again a little before the checkpoint, in case transactions
  /// committed out of order on the server. Applying a row twice is harmless.
  static const _checkpointOverlap = Duration(minutes: 2);
  static const _batchSize = 200;

  SyncState _state = SyncState.disabled;
  DateTime? _lastSyncedAt;
  Object? _lastError;
  bool _running = false;
  bool _again = false;
  String? _knownOwner;
  Timer? _debounceTimer;
  final _subscriptions = <StreamSubscription<Object?>>[];

  SyncState get state => _state;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  Object? get lastError => _lastError;
  bool get enabled => _remote != null && _auth.isSignedIn;

  Future<void> start() async {
    _lastSyncedAt = DateTime.tryParse(await _db.readValue(_lastSyncKey) ?? '');
    _knownOwner = await _db.readValue(_ownerKey);
    _auth.addListener(_onAuthChanged);
    await _onAuthChanged();

    final connectivity = _connectivity;
    if (connectivity != null) {
      _subscriptions.add(
        connectivity.listen((results) {
          if (results.any((r) => r != ConnectivityResult.none)) {
            schedule();
          } else if (enabled) {
            _setState(SyncState.offline);
          }
        }),
      );
    }
    _subscriptions.add(
      watchPendingCount().listen((count) {
        if (count > 0) schedule();
      }),
    );
  }

  /// Number of local changes not yet uploaded.
  Stream<int> watchPendingCount() => _db
      .customSelect(
        'SELECT '
        '(SELECT COUNT(*) FROM medications WHERE dirty = 1 AND owner_id <> ?1) + '
        '(SELECT COUNT(*) FROM dose_logs WHERE dirty = 1 AND owner_id <> ?1) + '
        '(SELECT COUNT(*) FROM companion_links WHERE dirty = 1) + '
        '(SELECT COUNT(*) FROM profiles WHERE dirty = 1 AND id <> ?1) AS pending',
        variables: [Variable.withString(AuthRepository.guestId)],
        readsFrom: {
          _db.medications,
          _db.doseLogs,
          _db.companionLinks,
          _db.profiles,
        },
      )
      .watchSingle()
      .map((row) => row.read<int>('pending'));

  Future<int> pendingCount() => watchPendingCount().first;

  /// Requests a sync soon, merging bursts of changes into one run.
  void schedule() {
    if (!enabled) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
  }

  /// Runs a full push + pull now. Safe to call repeatedly.
  Future<void> syncNow() async {
    if (!enabled) {
      _setState(SyncState.disabled);
      return;
    }
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _setState(SyncState.syncing);
    try {
      do {
        _again = false;
        await _push();
        await _pull();
        await _downloadMissingImages();
      } while (_again);
      _lastSyncedAt = _clock.nowUtc();
      _lastError = null;
      await _db.writeValue(_lastSyncKey, _lastSyncedAt!.toIso8601String());
      _setState(SyncState.idle);
    } catch (e, s) {
      _lastError = e;
      final offline = _looksOffline(e);
      log('Sync', offline ? 'Offline, will retry later' : 'Sync failed', e, s);
      _setState(offline ? SyncState.offline : SyncState.error);
    } finally {
      _running = false;
    }
  }

  // ------------------------------------------------------------------ push

  Future<void> _push() async {
    final remote = _remote!;
    final owner = _auth.ownerId;

    final profiles = await (_db.select(
      _db.profiles,
    )..where((t) => t.dirty & t.id.equals(owner))).get();
    if (profiles.isNotEmpty) {
      await remote.upsert('profiles', [
        for (final r in profiles) profileToRemote(r),
      ]);
      for (final r in profiles) {
        await (_db.update(_db.profiles)..where(
              (t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt),
            ))
            .write(const ProfilesCompanion(dirty: Value(false)));
      }
    }

    final links = await (_db.select(
      _db.companionLinks,
    )..where((t) => t.dirty)).get();
    if (links.isNotEmpty) {
      await remote.upsert('companion_links', [
        for (final r in links) companionLinkToRemote(r),
      ]);
      for (final r in links) {
        await (_db.update(_db.companionLinks)..where(
              (t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt),
            ))
            .write(const CompanionLinksCompanion(dirty: Value(false)));
      }
    }

    while (true) {
      final meds =
          await (_db.select(_db.medications)
                ..where(
                  (t) =>
                      t.dirty & t.ownerId.equals(AuthRepository.guestId).not(),
                )
                ..limit(_batchSize))
              .get();
      if (meds.isEmpty) break;
      final ready = <MedicationRow>[];
      for (final row in meds) {
        ready.add(await _uploadImageIfNeeded(row));
      }
      await remote.upsert('medications', [
        for (final r in ready) medicationToRemote(r),
      ]);
      for (final r in ready) {
        await (_db.update(_db.medications)..where(
              (t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt),
            ))
            .write(const MedicationsCompanion(dirty: Value(false)));
      }
      if (meds.length < _batchSize) break;
    }

    while (true) {
      final logs =
          await (_db.select(_db.doseLogs)
                ..where(
                  (t) =>
                      t.dirty & t.ownerId.equals(AuthRepository.guestId).not(),
                )
                ..limit(_batchSize))
              .get();
      if (logs.isEmpty) break;
      await remote.upsert('dose_logs', [
        for (final r in logs) doseLogToRemote(r),
      ]);
      for (final r in logs) {
        await (_db.update(_db.doseLogs)..where(
              (t) => t.id.equals(r.id) & t.updatedAt.equals(r.updatedAt),
            ))
            .write(const DoseLogsCompanion(dirty: Value(false)));
      }
      if (logs.length < _batchSize) break;
    }
  }

  Future<MedicationRow> _uploadImageIfNeeded(MedicationRow row) async {
    if (row.deletedAt != null ||
        row.imageRemotePath != null ||
        !ImageStore.exists(row.imagePath)) {
      return row;
    }
    try {
      final path = await _remote!.uploadImage(
        ownerId: row.ownerId,
        medicationId: row.id,
        localPath: row.imagePath!,
      );
      await (_db.update(_db.medications)..where((t) => t.id.equals(row.id)))
          .write(MedicationsCompanion(imageRemotePath: Value(path)));
      return row.copyWith(imageRemotePath: Value(path));
    } catch (e) {
      // The medication still syncs; the photo is retried next time.
      log('Sync', 'Photo upload failed for ${row.id}', e);
      if (_looksOffline(e)) rethrow;
      return row;
    }
  }

  // ------------------------------------------------------------------ pull

  Future<void> _pull() async {
    await _pullTable('profiles', (row) async {
      final id = row['id'] as String;
      final local = await (_db.select(
        _db.profiles,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (_localWins(local?.dirty, local?.updatedAt, row)) return;
      await _db
          .into(_db.profiles)
          .insertOnConflictUpdate(profileFromRemote(row));
    });
    await _pullTable('companion_links', (row) async {
      final id = row['id'] as String;
      final local = await (_db.select(
        _db.companionLinks,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (_localWins(local?.dirty, local?.updatedAt, row)) return;
      await _db
          .into(_db.companionLinks)
          .insertOnConflictUpdate(companionLinkFromRemote(row));
    });
    await _pullTable('medications', (row) async {
      final id = row['id'] as String;
      final local = await (_db.select(
        _db.medications,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (_localWins(local?.dirty, local?.updatedAt, row)) return;
      final samePhoto =
          local != null && local.imageRemotePath == row['image_remote_path'];
      await _db
          .into(_db.medications)
          .insertOnConflictUpdate(
            medicationFromRemote(
              row,
              localImagePath: samePhoto ? local.imagePath : null,
            ),
          );
      if (!samePhoto) await _images.deleteLocal(local?.imagePath);
    });
    await _pullTable('dose_logs', (row) async {
      final id = row['id'] as String;
      final local = await (_db.select(
        _db.doseLogs,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (_localWins(local?.dirty, local?.updatedAt, row)) return;
      await _db
          .into(_db.doseLogs)
          .insertOnConflictUpdate(doseLogFromRemote(row));
    });
    await _pruneUnsharedData();
  }

  /// Last-write-wins: a local change that is at least as new as the server's
  /// is kept (and will be pushed); otherwise the server row replaces it.
  static bool _localWins(
    bool? dirty,
    DateTime? localUpdatedAt,
    Map<String, dynamic> remote,
  ) =>
      (dirty ?? false) &&
      localUpdatedAt != null &&
      !remoteUpdatedAt(remote).isAfter(localUpdatedAt);

  Future<void> _pullTable(
    String table,
    Future<void> Function(Map<String, dynamic> row) apply,
  ) async {
    final key = _checkpointKey(table);
    var checkpoint = DateTime.tryParse(await _db.readValue(key) ?? '');
    while (true) {
      final since = checkpoint?.subtract(_checkpointOverlap);
      final rows = await _remote!.changedSince(table, since, limit: 500);
      var newest = checkpoint;
      await _db.transaction(() async {
        for (final row in rows) {
          await apply(row);
          final synced = remoteSyncedAt(row);
          if (synced != null && (newest == null || synced.isAfter(newest!))) {
            newest = synced;
          }
        }
      });
      if (newest != null && newest != checkpoint) {
        await _db.writeValue(key, newest!.toIso8601String());
      }
      // Stop when a page made no progress (only overlap rows) or was short.
      if (rows.length < 500 || newest == checkpoint) break;
      checkpoint = newest;
    }
  }

  /// Removes data of people the user no longer looks after.
  Future<void> _pruneUnsharedData() async {
    final me = _auth.ownerId;
    final patients =
        await (_db.select(_db.companionLinks)..where(
              (t) =>
                  t.caregiverId.equals(me) &
                  t.status.equals('accepted') &
                  t.deletedAt.isNull(),
            ))
            .map((r) => r.patientId)
            .get();
    final keep = {me, AuthRepository.guestId, ...patients};
    await (_db.delete(
      _db.medications,
    )..where((t) => t.ownerId.isNotIn(keep) & t.dirty.not())).go();
    await (_db.delete(
      _db.doseLogs,
    )..where((t) => t.ownerId.isNotIn(keep) & t.dirty.not())).go();
  }

  Future<void> _downloadMissingImages() async {
    final rows =
        await (_db.select(_db.medications)..where(
              (t) =>
                  t.imageRemotePath.isNotNull() &
                  t.imagePath.isNull() &
                  t.deletedAt.isNull(),
            ))
            .get();
    for (final row in rows.take(20)) {
      try {
        final bytes = await _remote!.downloadImage(row.imageRemotePath!);
        final path = await _images.saveBytes(bytes);
        await (_db.update(_db.medications)..where((t) => t.id.equals(row.id)))
            .write(MedicationsCompanion(imagePath: Value(path)));
      } catch (e) {
        log('Sync', 'Photo download failed for ${row.id}', e);
        if (_looksOffline(e)) return;
      }
    }
  }

  // ------------------------------------------------------ account changes

  Future<void> _onAuthChanged() async {
    final owner = _auth.isSignedIn ? _auth.ownerId : null;
    if (owner == _knownOwner) {
      _setState(enabled ? _state : SyncState.disabled);
      return;
    }
    if (_knownOwner != null) {
      // Signed out, or another account signed in on this phone.
      await clearAccountData();
    }
    _knownOwner = owner;
    if (owner == null) {
      await _db.deleteValue(_ownerKey);
      _setState(SyncState.disabled);
      return;
    }
    await _db.writeValue(_ownerKey, owner);
    await adoptGuestData(owner);
    _setState(SyncState.idle);
    schedule();
  }

  /// Moves everything created as a guest into [ownerId]'s account.
  Future<void> adoptGuestData(String ownerId) async {
    const guest = AuthRepository.guestId;
    final now = _clock.nowUtc();
    await _db.transaction(() async {
      await (_db.update(
        _db.medications,
      )..where((t) => t.ownerId.equals(guest))).write(
        MedicationsCompanion(
          ownerId: Value(ownerId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await (_db.update(
        _db.doseLogs,
      )..where((t) => t.ownerId.equals(guest))).write(
        DoseLogsCompanion(
          ownerId: Value(ownerId),
          actedBy: Value(ownerId),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      final guestProfile = await (_db.select(
        _db.profiles,
      )..where((t) => t.id.equals(guest))).getSingleOrNull();
      if (guestProfile != null) {
        await (_db.delete(_db.profiles)..where((t) => t.id.equals(guest))).go();
        final existing = await (_db.select(
          _db.profiles,
        )..where((t) => t.id.equals(ownerId))).getSingleOrNull();
        if (existing == null && guestProfile.name.isNotEmpty) {
          await _db
              .into(_db.profiles)
              .insert(
                ProfilesCompanion.insert(
                  id: ownerId,
                  name: guestProfile.name,
                  email: Value(_auth.email),
                  updatedAt: now,
                ),
              );
        }
      }
    });
  }

  /// Deletes all account data from the phone (keeps guest data, if any).
  Future<void> clearAccountData() async {
    const guest = AuthRepository.guestId;
    final photos =
        await (_db.select(_db.medications)
              ..where((t) => t.ownerId.equals(guest).not()))
            .map((r) => r.imagePath)
            .get();
    await _db.transaction(() async {
      await (_db.delete(
        _db.medications,
      )..where((t) => t.ownerId.equals(guest).not())).go();
      await (_db.delete(
        _db.doseLogs,
      )..where((t) => t.ownerId.equals(guest).not())).go();
      await (_db.delete(
        _db.profiles,
      )..where((t) => t.id.equals(guest).not())).go();
      await _db.delete(_db.companionLinks).go();
      await _db.delete(_db.companionAlerts).go();
      await (_db.delete(
        _db.keyValues,
      )..where((t) => t.key.like('sync.%'))).go();
    });
    for (final path in photos) {
      await _images.deleteLocal(path);
    }
    _lastSyncedAt = null;
  }

  void _setState(SyncState state) {
    if (_state == state) return;
    _state = state;
    notifyListeners();
  }

  static bool _looksOffline(Object e) {
    final text = e.toString();
    return text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('ClientException') ||
        text.contains('Connection refused') ||
        text.contains('Network is unreachable') ||
        text.contains('TimeoutException');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _auth.removeListener(_onAuthChanged);
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}
