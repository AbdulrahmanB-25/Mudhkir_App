import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/companion_link.dart';
import '../../domain/models/dose.dart';
import '../../domain/models/local_date.dart';
import '../../domain/models/medication.dart';
import '../../domain/models/profile.dart';
import 'app_database.dart';

List<DoseTime> decodeTimes(String json) {
  final list = jsonDecode(json) as List<dynamic>;
  return [
    for (final item in list) DoseTime.fromJson(item as Map<String, dynamic>),
  ]..sort();
}

String encodeTimes(List<DoseTime> times) => jsonEncode([
  for (final t in [...times]..sort()) t.toJson(),
]);

extension MedicationRowMapper on MedicationRow {
  Medication toDomain() => Medication(
    id: id,
    ownerId: ownerId,
    name: name,
    dosageAmount: dosageAmount,
    dosageUnit: DosageUnit.fromName(dosageUnit),
    frequency: Frequency.fromName(frequency),
    times: decodeTimes(timesJson),
    startDate: LocalDate.parse(startDate),
    endDate: LocalDate.tryParse(endDate),
    endedAt: endedAt,
    notes: notes,
    imagePath: imagePath,
    imageRemotePath: imageRemotePath,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

extension MedicationMapper on Medication {
  MedicationsCompanion toCompanion({bool dirty = true, DateTime? deletedAt}) =>
      MedicationsCompanion(
        id: Value(id),
        ownerId: Value(ownerId),
        name: Value(name),
        dosageAmount: Value(dosageAmount),
        dosageUnit: Value(dosageUnit.name),
        frequency: Value(frequency.name),
        timesJson: Value(encodeTimes(times)),
        startDate: Value(startDate.toString()),
        endDate: Value(endDate?.toString()),
        endedAt: Value(endedAt),
        notes: Value(notes),
        imagePath: Value(imagePath),
        imageRemotePath: Value(imageRemotePath),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        deletedAt: Value(deletedAt),
        dirty: Value(dirty),
      );
}

extension DoseLogRowMapper on DoseLogRow {
  DoseLog toDomain() => DoseLog(
    id: id,
    ownerId: ownerId,
    medicationId: medicationId,
    scheduledAt: scheduledAt.toUtc(),
    status: DoseLogStatus.fromName(status),
    actedAt: actedAt,
    rescheduledTo: rescheduledTo?.toUtc(),
    actedBy: actedBy,
    updatedAt: updatedAt,
  );
}

extension ProfileRowMapper on ProfileRow {
  Profile toDomain() =>
      Profile(id: id, name: name, email: email, updatedAt: updatedAt);
}

extension CompanionLinkRowMapper on CompanionLinkRow {
  CompanionLink toDomain() => CompanionLink(
    id: id,
    caregiverId: caregiverId,
    patientId: patientId,
    caregiverName: caregiverName,
    patientName: patientName,
    patientEmail: patientEmail,
    relationship: relationship,
    status: LinkStatus.fromName(status),
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
