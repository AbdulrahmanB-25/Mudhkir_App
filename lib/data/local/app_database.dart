import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Medications,
    DoseLogs,
    Profiles,
    CompanionLinks,
    CompanionAlerts,
    KeyValues,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  /// An in-memory database for tests.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX idx_medications_owner ON medications (owner_id)',
      );
      await customStatement(
        'CREATE INDEX idx_dose_logs_owner_time ON dose_logs (owner_id, scheduled_at)',
      );
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'mudhkir',
      // Notification actions and background tasks run in other isolates.
      // Sharing one connection keeps their writes visible to the UI.
      native: const DriftNativeOptions(shareAcrossIsolates: true),
    );
  }

  Future<String?> readValue(String key) async {
    final row = await (select(
      keyValues,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeValue(String key, String value) => into(
    keyValues,
  ).insertOnConflictUpdate(KeyValuesCompanion.insert(key: key, value: value));

  Future<void> deleteValue(String key) =>
      (delete(keyValues)..where((t) => t.key.equals(key))).go();
}
