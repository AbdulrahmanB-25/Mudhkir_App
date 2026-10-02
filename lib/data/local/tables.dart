import 'package:drift/drift.dart';

/// Columns shared by every table that is synced to Supabase.
///
/// * [updatedAt]: client time of the last change. The newest wins on conflict.
/// * [deletedAt]: soft delete, so deletions also sync.
/// * [dirty]: changed locally and not yet pushed.
mixin SyncedColumns on Table {
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(true))();
}

@DataClassName('MedicationRow')
class Medications extends Table with SyncedColumns {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get name => text()();
  TextColumn get dosageAmount => text()();
  TextColumn get dosageUnit => text()();
  TextColumn get frequency => text()();

  /// JSON list of `{"minutes": int, "weekday": int?}`.
  TextColumn get timesJson => text()();

  /// `yyyy-MM-dd`.
  TextColumn get startDate => text()();
  TextColumn get endDate => text().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get imageRemotePath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('DoseLogRow')
class DoseLogs extends Table with SyncedColumns {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get medicationId => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get status => text()();
  DateTimeColumn get actedAt => dateTime()();
  DateTimeColumn get rescheduledTo => dateTime().nullable()();
  TextColumn get actedBy => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ProfileRow')
class Profiles extends Table with SyncedColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get email => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CompanionLinkRow')
class CompanionLinks extends Table with SyncedColumns {
  TextColumn get id => text()();
  TextColumn get caregiverId => text()();
  TextColumn get patientId => text()();
  TextColumn get caregiverName => text().nullable()();
  TextColumn get patientName => text().nullable()();
  TextColumn get patientEmail => text().nullable()();
  TextColumn get relationship => text().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local only: missed-dose alerts already shown to a caregiver, so each
/// missed dose is announced once.
@DataClassName('CompanionAlertRow')
class CompanionAlerts extends Table {
  TextColumn get doseLogId => text()();
  DateTimeColumn get notifiedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {doseLogId};
}

/// Local only: small key/value settings such as sync checkpoints.
@DataClassName('KeyValueRow')
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
