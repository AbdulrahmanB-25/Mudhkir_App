import 'package:flutter/foundation.dart';

/// A calendar date without a time or time zone (for example a medication's
/// start or end date). Stored as `yyyy-MM-dd` locally and as `date` in Postgres,
/// so it means the same day on every device.
@immutable
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  factory LocalDate.fromDateTime(DateTime dateTime) =>
      LocalDate(dateTime.year, dateTime.month, dateTime.day);

  factory LocalDate.parse(String value) {
    final parts = value.split('-');
    if (parts.length != 3) {
      throw FormatException('Invalid date, expected yyyy-MM-dd', value);
    }
    return LocalDate(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static LocalDate? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return LocalDate.parse(value);
    } on FormatException {
      return null;
    }
  }

  final int year;
  final int month;
  final int day;

  /// Midnight of this date as a [DateTime] in the device's local zone.
  /// Only use this for display and for date pickers.
  DateTime toDateTime() => DateTime(year, month, day);

  LocalDate addDays(int days) =>
      LocalDate.fromDateTime(DateTime.utc(year, month, day + days));

  /// ISO weekday, 1 = Monday ... 7 = Sunday.
  int get weekday => DateTime.utc(year, month, day).weekday;

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
