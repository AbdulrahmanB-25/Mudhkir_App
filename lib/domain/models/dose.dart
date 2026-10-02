import 'package:flutter/foundation.dart';

import 'medication.dart';

/// What the user recorded for one scheduled dose.
enum DoseLogStatus {
  taken,
  skipped,

  /// Moved to another time today; see [DoseLog.rescheduledTo].
  rescheduled;

  static DoseLogStatus fromName(String? name) => DoseLogStatus.values
      .firstWhere((s) => s.name == name, orElse: () => taken);
}

/// A record for one scheduled dose. There is at most one log per
/// (medication, scheduled time); its id is derived from both, see [DoseLog.idFor].
@immutable
class DoseLog {
  const DoseLog({
    required this.id,
    required this.ownerId,
    required this.medicationId,
    required this.scheduledAt,
    required this.status,
    required this.actedAt,
    required this.updatedAt,
    this.rescheduledTo,
    this.actedBy,
  });

  static String idFor(String medicationId, DateTime scheduledAt) =>
      '${medicationId}_${scheduledAt.toUtc().millisecondsSinceEpoch}';

  final String id;
  final String ownerId;
  final String medicationId;

  /// The originally planned time, in UTC.
  final DateTime scheduledAt;
  final DoseLogStatus status;
  final DateTime actedAt;
  final DateTime? rescheduledTo;

  /// User id of whoever recorded it (the patient or a caregiver).
  final String? actedBy;
  final DateTime updatedAt;
}

/// Where a dose stands right now. Computed, never stored.
enum DoseStatus { upcoming, due, taken, skipped, missed }

/// One dose of one medication at one time, combined with its log, if any.
@immutable
class DoseInstance {
  const DoseInstance({
    required this.medication,
    required this.scheduledAt,
    required this.status,
    this.log,
  });

  final Medication medication;

  /// Original planned time (UTC). Identifies the dose.
  final DateTime scheduledAt;
  final DoseStatus status;
  final DoseLog? log;

  /// When the dose should actually be taken, after any rescheduling.
  DateTime get effectiveAt => log?.rescheduledTo ?? scheduledAt;

  bool get isRescheduled => log?.rescheduledTo != null;

  bool get isDone => status == DoseStatus.taken || status == DoseStatus.skipped;

  String get logId => DoseLog.idFor(medication.id, scheduledAt);
}
