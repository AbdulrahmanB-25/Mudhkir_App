import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
// ignore: unused_import
import 'time_utilities.dart';

// Service result class for handling operation results
class ServiceResult<T> {
  final bool success;
  final T? data;
  final String? error;

  ServiceResult({required this.success, this.data, this.error});

  static ServiceResult<T> succeeded<T>(T data) {
    return ServiceResult(success: true, data: data);
  }

  static ServiceResult<T> failed<T>(String error) {
    return ServiceResult(success: false, error: error);
  }
}

class MedicationDetailService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Load medication data
  Future<ServiceResult<Map<String, dynamic>>> loadMedicationData(String docId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return ServiceResult.failed("مستخدم غير مسجل.");
      }

      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(docId)
          .get();

      if (!doc.exists) {
        return ServiceResult.failed("لم يتم العثور على بيانات الدواء.");
      }

      return ServiceResult.succeeded(doc.data() as Map<String, dynamic>);
    } catch (e) {
      print("[MedicationDetailService] Error loading medication data: $e");
      return ServiceResult.failed("خطأ في تحميل البيانات: $e");
    }
  }

  // Record medication confirmation (taken or skipped)
  Future<ServiceResult<bool>> recordMedicationConfirmation(
      String docId,
      TimeOfDay timeToConfirm,
      bool taken,
      String confirmationSource
      ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return ServiceResult.failed("مستخدم غير مسجل.");
      }

      // Convert TimeOfDay to DateTime for the current day
      final now = DateTime.now();
      DateTime confirmationTime = DateTime(
        now.year,
        now.month,
        now.day,
        timeToConfirm.hour,
        timeToConfirm.minute,
      );

      // Ensure we're working with server timestamps for consistency
      final confirmationData = {
        'timestamp': FieldValue.serverTimestamp(),
        'scheduledTime': Timestamp.fromDate(confirmationTime),
        'status': taken ? 'taken' : 'skipped',
        'confirmedVia': confirmationSource,
      };

      // Add to dose history
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(docId)
          .collection('dose_history')
          .add(confirmationData);

      // Also update the main medication document with last status
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(docId)
          .update({
        'lastDoseStatus': taken ? 'taken' : 'skipped',
        'lastDoseTimestamp': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp()
      });

      return ServiceResult.succeeded(true);
    } catch (e) {
      print("[MedicationDetailService] Error recording confirmation: $e");
      return ServiceResult.failed("خطأ في تسجيل تأكيد الجرعة: $e");
    }
  }

  // Record medication rescheduling
  Future<ServiceResult<bool>> recordMedicationRescheduling(
      String docId,
      DateTime newScheduledTime,
      String? originalTimeIso,
      String reschedulingSource
      ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return ServiceResult.failed("مستخدم غير مسجل.");
      }

      // Use server timestamp for accurate timing
      final reschedulingData = {
        'timestamp': FieldValue.serverTimestamp(),
        'scheduledTime': originalTimeIso != null
            ? Timestamp.fromDate(DateTime.parse(originalTimeIso))
            : FieldValue.serverTimestamp(),
        'status': 'rescheduled',
        'newScheduledTime': Timestamp.fromDate(newScheduledTime),
        'confirmedVia': reschedulingSource,
      };

      // Log the rescheduling action
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(docId)
          .collection('dose_history')
          .add(reschedulingData);

      // Update medication next time in main document (add this to track reschedules)
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(docId)
          .update({
        'lastRescheduledTime': Timestamp.fromDate(newScheduledTime),
        'lastUpdated': FieldValue.serverTimestamp()
      });

      return ServiceResult.succeeded(true);
    } catch (e) {
      print("[MedicationDetailService] Error recording rescheduling: $e");
      return ServiceResult.failed("خطأ في إعادة جدولة الدواء: $e");
    }
  }

  // Generate smart rescheduling suggestions
  Future<List<TimeOfDay>> generateSmartReschedulingSuggestions(
      String userId,
      String currentMedicationId
      ) async {
    try {
      // Generate 3 smart suggested times
      final now = tz.TZDateTime.now(tz.local);
      final currentHour = now.hour;
      final currentMinute = now.minute;

      // 1. Fetch all user's medication times to avoid conflicts
      List<TimeOfDay> existingTimes = [];
      final medsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .where(
        FieldPath.documentId,
        isNotEqualTo: currentMedicationId,
      ) // Exclude current medication
          .get();

      for (var doc in medsSnapshot.docs) {
        final data = doc.data();
        final List<dynamic> times = data['times'] ?? [];

        for (var timeData in times) {
          String? timeStr;
          if (timeData is String) {
            timeStr = timeData;
          } else if (timeData is Map<String, dynamic> &&
              timeData['time'] is String) {
            timeStr = timeData['time'];
          }

          if (timeStr != null) {
            final tod = _parseTime(timeStr);
            if (tod != null) {
              existingTimes.add(tod);
            }
          }
        }
      }

      // 2. Find optimal times based on current time and existing medication schedule
      List<TimeOfDay> candidateTimes = [];

      // Suggestion 1: Next full hour (if it's in the future)
      final nextHour = TimeOfDay(hour: (currentHour + 1) % 24, minute: 0);
      if (_isTimeInFuture(nextHour)) {
        candidateTimes.add(nextHour);
      }

      // Suggestion 2: Add 2 hours from now
      final twoHoursLater = _addHoursToTime(currentHour, currentMinute, 2);
      candidateTimes.add(twoHoursLater);

      // Suggestion 3: Add 4 hours from now
      final fourHoursLater = _addHoursToTime(currentHour, currentMinute, 4);
      candidateTimes.add(fourHoursLater);

      // Additional suggestions based on common medication times
      final List<TimeOfDay> commonTimes = [
        const TimeOfDay(hour: 8, minute: 0), // Morning
        const TimeOfDay(hour: 12, minute: 0), // Noon
        const TimeOfDay(hour: 18, minute: 0), // Evening
        const TimeOfDay(hour: 21, minute: 0), // Night
      ];

      for (var time in commonTimes) {
        if (_isTimeInFuture(time) &&
            !_isTimeCloseToAny(time, candidateTimes) &&
            !_isTimeCloseToAny(time, existingTimes)) {
          candidateTimes.add(time);
        }
      }

      // Sort times chronologically and take the first 3 unique times
      candidateTimes.sort((a, b) => _compareTimeOfDay(a, b));

      final uniqueTimes = <TimeOfDay>[];
      for (var time in candidateTimes) {
        if (!_isTimeCloseToAny(time, uniqueTimes)) {
          uniqueTimes.add(time);
          if (uniqueTimes.length >= 3) break;
        }
      }

      // If we still need more suggestions, add some spaced apart
      while (uniqueTimes.length < 3) {
        final lastTime =
        uniqueTimes.isNotEmpty
            ? uniqueTimes.last
            : TimeOfDay(hour: currentHour, minute: currentMinute);
        final nextTime = _addHoursToTime(lastTime.hour, lastTime.minute, 2);
        uniqueTimes.add(nextTime);
      }

      return uniqueTimes;
    } catch (e) {
      print("[MedicationDetailService] Error generating rescheduling suggestions: $e");
      // Return some basic suggestions in case of error
      final now = DateTime.now();
      return [
        TimeOfDay(hour: (now.hour + 2) % 24, minute: 0),
        TimeOfDay(hour: (now.hour + 4) % 24, minute: 0),
        TimeOfDay(hour: (now.hour + 6) % 24, minute: 0),
      ];
    }
  }

  // Get medication dose history
  Future<ServiceResult<List<Map<String, dynamic>>>> getDoseHistory(String docId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return ServiceResult.failed("مستخدم غير مسجل.");
      }

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(docId)
          .collection('dose_history')
          .orderBy('timestamp', descending: true)
          .limit(30) // Recent history
          .get();

      final List<Map<String, dynamic>> historyList = snapshot.docs
          .map((doc) => {
        'id': doc.id,
        ...doc.data(),
      })
          .toList();

      return ServiceResult.succeeded(historyList);
    } catch (e) {
      print("[MedicationDetailService] Error fetching dose history: $e");
      return ServiceResult.failed("خطأ في تحميل سجل الجرعات: $e");
    }
  }

  // Update medication information
  Future<ServiceResult<bool>> updateMedicationInfo(String docId, Map<String, dynamic> updateData) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return ServiceResult.failed("مستخدم غير مسجل.");
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(docId)
          .update({
        ...updateData,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      return ServiceResult.succeeded(true);
    } catch (e) {
      print("[MedicationDetailService] Error updating medication: $e");
      return ServiceResult.failed("خطأ في تحديث بيانات الدواء: $e");
    }
  }

  // Helper methods for time operations
  TimeOfDay? _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (_) {}

    // Try parsing AM/PM format
    try {
      final amPmPattern = RegExp(r'(\d+):(\d+)\s*(AM|PM|صباحاً|مساءً)', caseSensitive: false);
      final match = amPmPattern.firstMatch(timeStr);

      if (match != null) {
        int hour = int.parse(match.group(1)!);
        int minute = int.parse(match.group(2)!);
        String period = match.group(3)!.toLowerCase();

        if (period == "pm" || period == "مساءً") {
          if (hour < 12) hour += 12;
        } else if (period == "am" || period == "صباحاً") {
          if (hour == 12) hour = 0;
        }

        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (_) {}

    return null;
  }

  bool _isTimeInFuture(TimeOfDay time) {
    final now = TimeOfDay.now();
    return time.hour > now.hour ||
        (time.hour == now.hour && time.minute > now.minute);
  }

  bool _isTimeCloseToAny(TimeOfDay time, List<TimeOfDay> times) {
    const int minimumMinutesBetween = 60; // 1 hour minimum between doses

    for (var existingTime in times) {
      final diff = _getTimeDifferenceInMinutes(time, existingTime).abs();
      if (diff < minimumMinutesBetween) {
        return true;
      }
    }
    return false;
  }

  int _getTimeDifferenceInMinutes(TimeOfDay time1, TimeOfDay time2) {
    return (time1.hour * 60 + time1.minute) - (time2.hour * 60 + time2.minute);
  }

  TimeOfDay _addHoursToTime(int hour, int minute, int hoursToAdd) {
    int totalMinutes = hour * 60 + minute + hoursToAdd * 60;
    return TimeOfDay(
      hour: (totalMinutes ~/ 60) % 24,
      minute: totalMinutes % 60,
    );
  }

  int _compareTimeOfDay(TimeOfDay a, TimeOfDay b) {
    if (a.hour != b.hour) return a.hour - b.hour;
    return a.minute - b.minute;
  }
}