import 'package:flutter/foundation.dart';

enum LinkStatus {
  pending,
  accepted;

  static LinkStatus fromName(String? name) => LinkStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => pending,
  );
}

/// A caregiver ([caregiverId]) following another user's medications
/// ([patientId]). The caregiver sends the invite and the patient must accept
/// it before any data is shared.
@immutable
class CompanionLink {
  const CompanionLink({
    required this.id,
    required this.caregiverId,
    required this.patientId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.caregiverName,
    this.patientName,
    this.patientEmail,
    this.relationship,
  });

  final String id;
  final String caregiverId;
  final String patientId;
  final String? caregiverName;
  final String? patientName;
  final String? patientEmail;
  final String? relationship;
  final LinkStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isAccepted => status == LinkStatus.accepted;
}
