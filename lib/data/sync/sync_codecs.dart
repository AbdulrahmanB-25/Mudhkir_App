import 'dart:convert';

import 'package:drift/drift.dart';

import '../local/app_database.dart';

/// Converts rows between the local SQLite tables and the Supabase tables
/// (snake_case columns, ISO-8601 UTC timestamps, `date` as yyyy-MM-dd).

String? _ts(DateTime? value) => value?.toUtc().toIso8601String();

DateTime _parseTs(Object? value) => DateTime.parse(value! as String).toUtc();

DateTime? _parseTsOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toUtc();

DateTime remoteUpdatedAt(Map<String, dynamic> row) =>
    _parseTs(row['updated_at']);

DateTime? remoteSyncedAt(Map<String, dynamic> row) =>
    _parseTsOrNull(row['synced_at']);

// ---------------------------------------------------------------- medications

Map<String, dynamic> medicationToRemote(MedicationRow r) => {
  'id': r.id,
  'owner_id': r.ownerId,
  'name': r.name,
  'dosage_amount': r.dosageAmount,
  'dosage_unit': r.dosageUnit,
  'frequency': r.frequency,
  'times': jsonDecode(r.timesJson),
  'start_date': r.startDate,
  'end_date': r.endDate,
  'ended_at': _ts(r.endedAt),
  'notes': r.notes,
  'image_remote_path': r.imageRemotePath,
  'created_at': _ts(r.createdAt),
  'updated_at': _ts(r.updatedAt),
  'deleted_at': _ts(r.deletedAt),
};

/// [localImagePath] is kept when the photo did not change remotely.
MedicationsCompanion medicationFromRemote(
  Map<String, dynamic> m, {
  String? localImagePath,
}) => MedicationsCompanion(
  id: Value(m['id'] as String),
  ownerId: Value(m['owner_id'] as String),
  name: Value(m['name'] as String),
  dosageAmount: Value(m['dosage_amount'] as String),
  dosageUnit: Value(m['dosage_unit'] as String),
  frequency: Value(m['frequency'] as String),
  timesJson: Value(jsonEncode(m['times'] ?? const <dynamic>[])),
  startDate: Value(m['start_date'] as String),
  endDate: Value(m['end_date'] as String?),
  endedAt: Value(_parseTsOrNull(m['ended_at'])),
  notes: Value(m['notes'] as String?),
  imagePath: Value(localImagePath),
  imageRemotePath: Value(m['image_remote_path'] as String?),
  createdAt: Value(_parseTs(m['created_at'])),
  updatedAt: Value(_parseTs(m['updated_at'])),
  deletedAt: Value(_parseTsOrNull(m['deleted_at'])),
  dirty: const Value(false),
);

// ------------------------------------------------------------------ dose logs

Map<String, dynamic> doseLogToRemote(DoseLogRow r) => {
  'id': r.id,
  'owner_id': r.ownerId,
  'medication_id': r.medicationId,
  'scheduled_at': _ts(r.scheduledAt),
  'status': r.status,
  'acted_at': _ts(r.actedAt),
  'rescheduled_to': _ts(r.rescheduledTo),
  'acted_by': r.actedBy,
  'updated_at': _ts(r.updatedAt),
  'deleted_at': _ts(r.deletedAt),
};

DoseLogsCompanion doseLogFromRemote(Map<String, dynamic> m) =>
    DoseLogsCompanion(
      id: Value(m['id'] as String),
      ownerId: Value(m['owner_id'] as String),
      medicationId: Value(m['medication_id'] as String),
      scheduledAt: Value(_parseTs(m['scheduled_at'])),
      status: Value(m['status'] as String),
      actedAt: Value(_parseTs(m['acted_at'])),
      rescheduledTo: Value(_parseTsOrNull(m['rescheduled_to'])),
      actedBy: Value(m['acted_by'] as String?),
      updatedAt: Value(_parseTs(m['updated_at'])),
      deletedAt: Value(_parseTsOrNull(m['deleted_at'])),
      dirty: const Value(false),
    );

// ------------------------------------------------------------------- profiles

Map<String, dynamic> profileToRemote(ProfileRow r) => {
  'id': r.id,
  'name': r.name,
  'updated_at': _ts(r.updatedAt),
};

ProfilesCompanion profileFromRemote(Map<String, dynamic> m) =>
    ProfilesCompanion(
      id: Value(m['id'] as String),
      name: Value((m['name'] as String?) ?? ''),
      email: Value(m['email'] as String?),
      updatedAt: Value(_parseTs(m['updated_at'])),
      deletedAt: const Value(null),
      dirty: const Value(false),
    );

// ------------------------------------------------------------ companion links

Map<String, dynamic> companionLinkToRemote(CompanionLinkRow r) => {
  'id': r.id,
  'caregiver_id': r.caregiverId,
  'patient_id': r.patientId,
  'caregiver_name': r.caregiverName,
  'patient_name': r.patientName,
  'patient_email': r.patientEmail,
  'relationship': r.relationship,
  'status': r.status,
  'created_at': _ts(r.createdAt),
  'updated_at': _ts(r.updatedAt),
  'deleted_at': _ts(r.deletedAt),
};

CompanionLinksCompanion companionLinkFromRemote(Map<String, dynamic> m) =>
    CompanionLinksCompanion(
      id: Value(m['id'] as String),
      caregiverId: Value(m['caregiver_id'] as String),
      patientId: Value(m['patient_id'] as String),
      caregiverName: Value(m['caregiver_name'] as String?),
      patientName: Value(m['patient_name'] as String?),
      patientEmail: Value(m['patient_email'] as String?),
      relationship: Value(m['relationship'] as String?),
      status: Value(m['status'] as String),
      createdAt: Value(_parseTs(m['created_at'])),
      updatedAt: Value(_parseTs(m['updated_at'])),
      deletedAt: Value(_parseTsOrNull(m['deleted_at'])),
      dirty: const Value(false),
    );
