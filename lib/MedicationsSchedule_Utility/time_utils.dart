import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimeUtils {
  static TimeOfDay? parseTime(dynamic timeInput) {
    if (timeInput is Map) {
      if (timeInput.containsKey('time')) {
        return parseTime(timeInput['time']);
      }
      print("Failed to parse time from map: $timeInput");
      return null;
    }

    final String? timeStr = timeInput?.toString();
    if (timeStr == null || timeStr.isEmpty) {
      print("Empty or null time string");
      return null;
    }

    // Enhanced Arabic AM/PM normalization for more robust handling
    String normalizedTimeStr = timeStr;
    
    // Handle Arabic PM indicators
    if (timeStr.contains('م') || 
        timeStr.contains('مساءً') || 
        timeStr.contains('مساء')) {
      normalizedTimeStr = normalizedTimeStr
          .replaceAll('مساءً', 'PM')
          .replaceAll('مساء', 'PM')
          .replaceAll('م', 'PM');
          
      // Ensure we're actually handling a PM time correctly
      try {
        final parts = normalizedTimeStr.split(':');
        if (parts.length == 2) {
          String hourPart = parts[0].trim();
          int hour = int.parse(hourPart);
          
          // PM time special handling - if it's not stored as 24-hour format
          if (hour < 12 && normalizedTimeStr.contains('PM')) {
            // Convert to 24-hour format
            hour += 12;
            normalizedTimeStr = '$hour:${parts[1]}';
          }
        }
      } catch (e) {
        print("Error during PM time adjustment: $e");
      }
    }
    // Handle Arabic AM indicators
    else if (timeStr.contains('ص') || 
             timeStr.contains('صباحاً') || 
             timeStr.contains('صباحا')) {
      normalizedTimeStr = normalizedTimeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('صباحا', 'AM')
          .replaceAll('ص', 'AM');
          
      // Special handling for 12 AM (midnight)
      try {
        final parts = normalizedTimeStr.split(':');
        if (parts.length == 2) {
          String hourPart = parts[0].trim();
          int hour = int.parse(hourPart);
          
          if (hour == 12 && normalizedTimeStr.contains('AM')) {
            hour = 0; // 12 AM is 00:00 in 24-hour
            normalizedTimeStr = '$hour:${parts[1]}';
          }
        }
      } catch (e) {
        print("Error during AM time adjustment: $e");
      }
    }
    
    // Try different parsing strategies
    try {
      final DateFormat ampmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(normalizedTimeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    
    try {
      final parts = normalizedTimeStr.split(':');
      if (parts.length == 2) {
        String hourPart = parts[0].trim();
        String minutePart = parts[1].replaceAll(RegExp(r'[^0-9]'), '');
        
        int hour = int.parse(hourPart);
        int minute = int.parse(minutePart);
        
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (_) {}
    
    print("Failed to parse time string: $timeStr (normalized: $normalizedTimeStr)");
    return null;
  }

  static String formatTimeOfDay(BuildContext context, TimeOfDay time) {
    // Use actual time period from TimeOfDay
    final bool isPM = time.period == DayPeriod.pm;
    
    // Format hour correctly for 12-hour format (12-hour cycle)
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    
    // Use correct Arabic period indicator
    final String period = isPM ? 'مساءً' : 'صباحاً';
    
    return '$hour:$minute $period';
  }
}
