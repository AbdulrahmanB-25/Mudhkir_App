import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimeUtils {
  // Cache for parsed times to avoid repeated parsing
  static final Map<String, TimeOfDay?> _parsedTimeCache = {};
  
  static TimeOfDay? parseTime(dynamic timeInput) {
    // Fast path for null or empty inputs
    if (timeInput == null) return null;
    
    // Handle map input
    if (timeInput is Map) {
      if (timeInput.containsKey('time')) {
        return parseTime(timeInput['time']);
      }
      return null;
    }
    
    // Convert to string and check cache
    final String timeStr = timeInput.toString();
    if (timeStr.isEmpty) return null;
    
    if (_parsedTimeCache.containsKey(timeStr)) {
      return _parsedTimeCache[timeStr];
    }
    
    TimeOfDay? result;
    
    // Try parsing with various formats
    try {
      final DateFormat ampmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      result = TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {
      try {
        String normalizedTime = timeStr
            .replaceAll('صباحاً', 'AM')
            .replaceAll('مساءً', 'PM')
            .trim();
        final DateFormat arabicAmpmFormat = DateFormat('h:mm a', 'en_US');
        DateTime parsedDt = arabicAmpmFormat.parseStrict(normalizedTime);
        result = TimeOfDay.fromDateTime(parsedDt);
      } catch (_) {
        try {
          final parts = timeStr.split(':');
          if (parts.length == 2) {
            int hour = int.parse(parts[0]);
            int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
            if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
              result = TimeOfDay(hour: hour, minute: minute);
            }
          }
        } catch (_) {}
      }
    }
    
    // Store in cache (even null results to avoid repeated parsing attempts)
    _parsedTimeCache[timeStr] = result;
    return result;
  }

  // Cache for formatted times
  static final Map<String, String> _formattedTimeCache = {};
  
  static String formatTimeOfDay(BuildContext context, TimeOfDay time) {
    final String cacheKey = '${time.hour}:${time.minute}';
    if (_formattedTimeCache.containsKey(cacheKey)) {
      return _formattedTimeCache[cacheKey]!;
    }
    
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    final String formatted = '$hour:$minute $period';
    
    _formattedTimeCache[cacheKey] = formatted;
    return formatted;
  }
}
