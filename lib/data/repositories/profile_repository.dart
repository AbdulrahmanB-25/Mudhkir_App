import 'package:drift/drift.dart';

import '../../core/utils/clock.dart';
import '../../domain/models/profile.dart';
import '../local/app_database.dart';
import '../local/mappers.dart';

/// The user's display name (also shown to their caregivers).
class ProfileRepository {
  ProfileRepository(this._db, {this._clock = const Clock()});

  final AppDatabase _db;
  final Clock _clock;

  Stream<Profile?> watch(String ownerId) =>
      (_db.select(_db.profiles)..where((t) => t.id.equals(ownerId)))
          .watchSingleOrNull()
          .map((r) => r?.toDomain());

  Future<Profile?> get(String ownerId) => watch(ownerId).first;

  Future<void> saveName(String ownerId, String name, {String? email}) async {
    final existing = await get(ownerId);
    await _db
        .into(_db.profiles)
        .insertOnConflictUpdate(
          ProfilesCompanion.insert(
            id: ownerId,
            name: name.trim(),
            email: Value(email ?? existing?.email),
            updatedAt: _clock.nowUtc(),
            dirty: const Value(true),
          ),
        );
  }
}
