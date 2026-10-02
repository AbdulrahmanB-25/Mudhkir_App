import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/local_date.dart';
import '../../domain/models/medication.dart';
import '../../l10n/app_localizations.dart';

/// Locale-aware formatting helpers (Arabic digits/AM-PM follow the locale).
extension Formatters on BuildContext {
  String get _locale => Localizations.localeOf(this).toLanguageTag();

  String formatTime(DateTime instant) =>
      MaterialLocalizations.of(this)
          .formatTimeOfDay(TimeOfDay.fromDateTime(instant.toLocal()));

  String formatTimeOfDay(TimeOfDay time) =>
      MaterialLocalizations.of(this).formatTimeOfDay(time);

  String formatDoseTime(DoseTime time) =>
      formatTimeOfDay(TimeOfDay(hour: time.hour, minute: time.minute));

  String formatDate(DateTime date) =>
      DateFormat.yMMMMd(_locale).format(date.toLocal());

  String formatLocalDate(LocalDate date) =>
      DateFormat.yMMMMd(_locale).format(date.toDateTime());

  String formatDayHeader(DateTime date) =>
      DateFormat.MMMMEEEEd(_locale).format(date);

  String formatDateTime(DateTime instant) =>
      '${formatDate(instant)} • ${formatTime(instant)}';

  /// ISO weekday (1 = Monday) to its localized name.
  String weekdayName(int weekday, {bool short = false}) {
    // 2024-01-01 was a Monday.
    final date = DateTime(2024, 1, weekday);
    return (short ? DateFormat.E(_locale) : DateFormat.EEEE(_locale)).format(
      date,
    );
  }

  String dosageText(Medication medication) {
    final l10n = AppLocalizations.of(this);
    return '${medication.dosageAmount} ${l10n.dosageUnitName(medication.dosageUnit.name)}';
  }

  /// e.g. "3 times a day" or "Mon, Wed".
  String scheduleSummary(Medication medication) {
    final l10n = AppLocalizations.of(this);
    if (medication.frequency == Frequency.daily) {
      return l10n.timesPerDay(medication.times.length);
    }
    final days = {for (final t in medication.times) t.weekday!}.toList()
      ..sort();
    return days
        .map((d) => weekdayName(d, short: true))
        .join(l10n.listSeparator);
  }
}
