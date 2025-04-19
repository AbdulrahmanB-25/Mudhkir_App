import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class TimeUtilities {
  // Format TimeOfDay for display in Arabic
  static String formatTimeOfDay(TimeOfDay time) {
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }

  // Helper method to determine if a time is in the future
  static bool isTimeInFuture(TimeOfDay time) {
    final now = TimeOfDay.now();
    return time.hour > now.hour ||
        (time.hour == now.hour && time.minute > now.minute);
  }

  // Helper method to convert TimeOfDay to DateTime for today
  static DateTime timeOfDayToDateTime(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, time.hour, time.minute);
  }

  // Helper method to convert TimeOfDay to TZDateTime for today
  static tz.TZDateTime timeOfDayToTZDateTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    return tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
  }

  // Helper method to add hours to a TimeOfDay
  static TimeOfDay addHoursToTime(TimeOfDay time, int hoursToAdd) {
    final totalMinutes = (time.hour * 60 + time.minute) + (hoursToAdd * 60);
    return TimeOfDay(
      hour: (totalMinutes ~/ 60) % 24,
      minute: totalMinutes % 60,
    );
  }

  // Compare two TimeOfDay objects
  static int compareTimeOfDay(TimeOfDay a, TimeOfDay b) {
    if (a.hour != b.hour) return a.hour - b.hour;
    return a.minute - b.minute;
  }

  // Get time difference in minutes between two TimeOfDay objects
  static int getTimeDifferenceInMinutes(TimeOfDay time1, TimeOfDay time2) {
    return (time1.hour * 60 + time1.minute) - (time2.hour * 60 + time2.minute);
  }

  // Check if a time is within a certain minute range of another time
  static bool isTimeCloseToOther(
      TimeOfDay time1, TimeOfDay time2, int minuteThreshold) {
    final diff = getTimeDifferenceInMinutes(time1, time2).abs();
    return diff < minuteThreshold;
  }

  // Format a date with Arabic locale
  static String formatDate(DateTime? date) {
    if (date == null) return "غير محدد";
    try {
      return DateFormat.yMMMd('ar_SA').format(date);
    } catch (e) {
      print("Error formatting date: $e");
      return "تاريخ غير صالح";
    }
  }
}
