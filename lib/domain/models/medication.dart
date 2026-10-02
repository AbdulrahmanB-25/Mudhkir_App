import 'package:flutter/foundation.dart';

import 'local_date.dart';

enum Frequency {
  daily,
  weekly;

  static Frequency fromName(String? name) =>
      Frequency.values.firstWhere((f) => f.name == name, orElse: () => daily);
}

enum DosageUnit {
  mg,
  g,
  ml,
  tablet,
  unit;

  static DosageUnit fromName(String? name) =>
      DosageUnit.values.firstWhere((u) => u.name == name, orElse: () => mg);
}

/// One reminder time in a medication schedule.
///
/// [minutes] is minutes after local midnight. [weekday] is null for daily
/// schedules and 1 (Monday) to 7 (Sunday) for weekly ones.
@immutable
class DoseTime implements Comparable<DoseTime> {
  const DoseTime({required this.minutes, this.weekday})
    : assert(minutes >= 0 && minutes < 24 * 60),
      assert(weekday == null || (weekday >= 1 && weekday <= 7));

  factory DoseTime.fromJson(Map<String, dynamic> json) => DoseTime(
    minutes: (json['minutes'] as num).toInt(),
    weekday: (json['weekday'] as num?)?.toInt(),
  );

  final int minutes;
  final int? weekday;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  Map<String, dynamic> toJson() => {
    'minutes': minutes,
    if (weekday != null) 'weekday': weekday,
  };

  @override
  int compareTo(DoseTime other) {
    final byDay = (weekday ?? 0).compareTo(other.weekday ?? 0);
    return byDay != 0 ? byDay : minutes.compareTo(other.minutes);
  }

  @override
  bool operator ==(Object other) =>
      other is DoseTime && other.minutes == minutes && other.weekday == weekday;

  @override
  int get hashCode => Object.hash(minutes, weekday);

  @override
  String toString() => 'DoseTime(${weekday ?? '*'} $hour:$minute)';
}

@immutable
class Medication {
  const Medication({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.dosageAmount,
    required this.dosageUnit,
    required this.frequency,
    required this.times,
    required this.startDate,
    required this.createdAt,
    required this.updatedAt,
    this.endDate,
    this.endedAt,
    this.notes,
    this.imagePath,
    this.imageRemotePath,
  });

  final String id;

  /// The user who takes this medication. For a caregiver this can be the
  /// person they look after.
  final String ownerId;
  final String name;
  final String dosageAmount;
  final DosageUnit dosageUnit;
  final Frequency frequency;
  final List<DoseTime> times;
  final LocalDate startDate;
  final LocalDate? endDate;

  /// Set when the user stops the medication early ("end medication").
  final DateTime? endedAt;
  final String? notes;

  /// Absolute path of the photo on this device, if any.
  final String? imagePath;

  /// Path of the photo in Supabase Storage, once uploaded.
  final String? imageRemotePath;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isEnded => endedAt != null;

  /// Whether reminders should still be scheduled on [today].
  bool isActiveOn(LocalDate today) =>
      !isEnded &&
      !today.isBefore(startDate) &&
      !(endDate?.isBefore(today) ?? false);

  /// Whether the medication has finished or was stopped.
  bool isFinishedOn(LocalDate today) =>
      isEnded || (endDate?.isBefore(today) ?? false);

  Medication copyWith({
    String? name,
    String? dosageAmount,
    DosageUnit? dosageUnit,
    Frequency? frequency,
    List<DoseTime>? times,
    LocalDate? startDate,
    LocalDate? Function()? endDate,
    DateTime? Function()? endedAt,
    String? Function()? notes,
    String? Function()? imagePath,
    String? Function()? imageRemotePath,
    DateTime? updatedAt,
  }) {
    return Medication(
      id: id,
      ownerId: ownerId,
      name: name ?? this.name,
      dosageAmount: dosageAmount ?? this.dosageAmount,
      dosageUnit: dosageUnit ?? this.dosageUnit,
      frequency: frequency ?? this.frequency,
      times: times ?? this.times,
      startDate: startDate ?? this.startDate,
      endDate: endDate != null ? endDate() : this.endDate,
      endedAt: endedAt != null ? endedAt() : this.endedAt,
      notes: notes != null ? notes() : this.notes,
      imagePath: imagePath != null ? imagePath() : this.imagePath,
      imageRemotePath: imageRemotePath != null
          ? imageRemotePath()
          : this.imageRemotePath,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
