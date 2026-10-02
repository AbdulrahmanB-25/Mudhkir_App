import 'dart:convert';

import '../../domain/models/dose.dart';

/// Data carried inside a notification, so a tap or an action button knows
/// which dose (or which companion) it is about.
sealed class NotificationPayload {
  const NotificationPayload();

  static NotificationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      switch (map['t']) {
        case 'dose':
          return DosePayload(
            medicationId: map['m'] as String,
            ownerId: map['o'] as String,
            scheduledAt: DateTime.fromMillisecondsSinceEpoch(
              (map['s'] as num).toInt(),
              isUtc: true,
            ),
            isSnooze: map['z'] == 1,
          );
        case 'companion':
          return CompanionPayload(patientId: map['p'] as String);
      }
    } on Object {
      // Payloads from the old app version or malformed data are ignored.
    }
    return null;
  }

  String encode();
}

final class DosePayload extends NotificationPayload {
  const DosePayload({
    required this.medicationId,
    required this.ownerId,
    required this.scheduledAt,
    this.isSnooze = false,
  });

  factory DosePayload.fromDose(DoseInstance dose) => DosePayload(
    medicationId: dose.medication.id,
    ownerId: dose.medication.ownerId,
    scheduledAt: dose.scheduledAt,
  );

  final String medicationId;
  final String ownerId;
  final DateTime scheduledAt;
  final bool isSnooze;

  String get logId => DoseLog.idFor(medicationId, scheduledAt);

  DosePayload asSnooze() => DosePayload(
    medicationId: medicationId,
    ownerId: ownerId,
    scheduledAt: scheduledAt,
    isSnooze: true,
  );

  @override
  String encode() => jsonEncode({
    't': 'dose',
    'm': medicationId,
    'o': ownerId,
    's': scheduledAt.toUtc().millisecondsSinceEpoch,
    if (isSnooze) 'z': 1,
  });
}

final class CompanionPayload extends NotificationPayload {
  const CompanionPayload({required this.patientId});

  final String patientId;

  @override
  String encode() => jsonEncode({'t': 'companion', 'p': patientId});
}

/// Stable 31-bit notification id (FNV-1a). `String.hashCode` is not
/// guaranteed to be the same across app runs, which would orphan reminders.
int notificationIdFor(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
