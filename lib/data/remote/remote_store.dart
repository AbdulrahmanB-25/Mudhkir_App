import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/ids.dart';

/// Result of looking up a user by email to invite them as a companion.
class RemoteProfile {
  const RemoteProfile({required this.id, required this.name});

  final String id;
  final String name;
}

/// The cloud side of sync. An interface so tests can use an in-memory fake.
abstract interface class RemoteStore {
  /// Inserts or updates rows (matched by `id`).
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);

  /// Rows the server changed after [since] (its `synced_at`), oldest first.
  Future<List<Map<String, dynamic>>> changedSince(
    String table,
    DateTime? since, {
    int limit,
  });

  /// Uploads a medication photo and returns its storage path.
  Future<String> uploadImage({
    required String ownerId,
    required String medicationId,
    required String localPath,
  });

  Future<Uint8List> downloadImage(String remotePath);

  Future<RemoteProfile?> findProfileByEmail(String email);
}

class SupabaseRemoteStore implements RemoteStore {
  SupabaseRemoteStore(this._client);

  final SupabaseClient _client;

  static const imageBucket = 'medication-images';

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> changedSince(
    String table,
    DateTime? since, {
    int limit = 500,
  }) async {
    var query = _client.from(table).select();
    if (since != null) {
      query = query.gt('synced_at', since.toUtc().toIso8601String());
    }
    final rows = await query.order('synced_at').limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<String> uploadImage({
    required String ownerId,
    required String medicationId,
    required String localPath,
  }) async {
    final extension = p.extension(localPath).isEmpty
        ? '.jpg'
        : p.extension(localPath);
    final path = '$ownerId/$medicationId/${newId()}$extension';
    await _client.storage
        .from(imageBucket)
        .upload(
          path,
          File(localPath),
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  @override
  Future<Uint8List> downloadImage(String remotePath) =>
      _client.storage.from(imageBucket).download(remotePath);

  @override
  Future<RemoteProfile?> findProfileByEmail(String email) async {
    final result = await _client.rpc<List<dynamic>>(
      'find_profile_by_email',
      params: {'lookup_email': email.trim().toLowerCase()},
    );
    if (result.isEmpty) return null;
    final row = result.first as Map<String, dynamic>;
    return RemoteProfile(
      id: row['id'] as String,
      name: (row['name'] as String?) ?? '',
    );
  }
}
