import 'dart:io';
import 'dart:typed_data';

import 'package:mudhkir_app/data/remote/remote_store.dart';
import 'package:mudhkir_app/data/repositories/auth_repository.dart';

/// Signed-in (or guest) user without Supabase.
class FakeAuth extends AuthRepository {
  FakeAuth({this._userId, this.userEmail}) : super(null);

  String? _userId;
  final String? userEmail;

  @override
  bool get isSignedIn => _userId != null;

  @override
  bool get cloudAvailable => true;

  @override
  String get ownerId => _userId ?? AuthRepository.guestId;

  @override
  String? get email => userEmail;

  void signInAs(String id) {
    _userId = id;
    notifyListeners();
  }

  void signOutNow() {
    _userId = null;
    notifyListeners();
  }
}

/// In-memory stand-in for the Supabase tables. Every write gets a
/// increasing `synced_at`, like the server trigger.
class FakeRemoteStore implements RemoteStore {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  final profilesByEmail = <String, RemoteProfile>{};
  final images = <String, Uint8List>{};
  var _tick = 0;
  bool offline = false;

  DateTime _nextSyncedAt() =>
      DateTime.utc(2026, 1, 1).add(Duration(seconds: ++_tick));

  void _checkOnline() {
    if (offline) throw const SocketException('offline');
  }

  /// Simulates another device writing directly to the server.
  void serverWrite(String table, Map<String, dynamic> row) {
    tables.putIfAbsent(table, () => {})[row['id'] as String] = {
      ...row,
      'synced_at': _nextSyncedAt().toIso8601String(),
    };
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    _checkOnline();
    for (final row in rows) {
      final existing = tables[table]?[row['id']];
      // Mirrors the `keep_newest` trigger: an older update is ignored.
      if (existing != null &&
          row['updated_at'] != null &&
          existing['updated_at'] != null &&
          DateTime.parse(row['updated_at'] as String)
              .isBefore(DateTime.parse(existing['updated_at'] as String))) {
        continue;
      }
      serverWrite(table, {...?existing, ...row});
    }
  }

  @override
  Future<List<Map<String, dynamic>>> changedSince(
    String table,
    DateTime? since, {
    int limit = 500,
  }) async {
    _checkOnline();
    final rows =
        (tables[table]?.values ?? const <Map<String, dynamic>>[])
            .where(
              (r) =>
                  since == null ||
                  DateTime.parse(r['synced_at'] as String).isAfter(since),
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['synced_at'] as String).compareTo(b['synced_at'] as String),
          );
    return rows.take(limit).toList();
  }

  @override
  Future<String> uploadImage({
    required String ownerId,
    required String medicationId,
    required String localPath,
  }) async {
    _checkOnline();
    final path = '$ownerId/$medicationId/photo.jpg';
    images[path] = await File(localPath).readAsBytes();
    return path;
  }

  @override
  Future<Uint8List> downloadImage(String remotePath) async {
    _checkOnline();
    return images[remotePath]!;
  }

  @override
  Future<RemoteProfile?> findProfileByEmail(String email) async {
    _checkOnline();
    return profilesByEmail[email.toLowerCase()];
  }
}
