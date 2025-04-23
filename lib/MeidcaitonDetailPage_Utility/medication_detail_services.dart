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

      // Update missedDoses array for compatibility with dose_schedule
      await _updateMissedDosesField(user.uid, docId, confirmationTime, taken ? 'taken' : 'skipped');

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

      // Get original scheduled time
      DateTime? originalTime;
      if (originalTimeIso != null && originalTimeIso.isNotEmpty) {
        try {
          originalTime = DateTime.parse(originalTimeIso);
        } catch (e) {
          print("[MedicationDetailService] Error parsing originalTimeIso: $e");
          // Continue with null originalTime
        }
      }

      // Use server timestamp for accurate timing
      final reschedulingData = {
        'timestamp': FieldValue.serverTimestamp(),
        'scheduledTime': originalTime != null
            ? Timestamp.fromDate(originalTime)
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
      
      // Update the medication schedule if it's a daily medication
      await _updateRescheduledTime(user.uid, docId, originalTime, newScheduledTime);
      
      // Mark original time as skipped and add new scheduled time
      if (originalTime != null) {
        // Mark the original time as skipped in missedDoses
        await _updateMissedDosesField(user.uid, docId, originalTime, 'skipped');
      }
      
      return ServiceResult.succeeded(true);
    } catch (e) {
      print("[MedicationDetailService] Error recording rescheduling: $e");
      return ServiceResult.failed("خطأ في إعادة جدولة الدواء: $e");
    }
  }

  // Helper method to update missedDoses field for dose_schedule compatibility
  Future<void> _updateMissedDosesField(String userId, String docId, DateTime scheduledTime, String status) async {
    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .doc(docId);
          
      // Use transaction to safely update the missedDoses array
      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(docRef);
        
        if (!snapshot.exists) {
          throw Exception("Document does not exist!");
        }
        
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        List<dynamic> missedDoses = List.from(data['missedDoses'] ?? []);
        
        // Check if this time already exists in the array
        int existingIndex = -1;
        for (int i = 0; i < missedDoses.length; i++) {
          if (missedDoses[i] is Map && missedDoses[i].containsKey('scheduled')) {
            Timestamp timestamp = missedDoses[i]['scheduled'] as Timestamp;
            DateTime storedTime = timestamp.toDate();
            if (storedTime.year == scheduledTime.year && 
                storedTime.month == scheduledTime.month && 
                storedTime.day == scheduledTime.day &&
                storedTime.hour == scheduledTime.hour && 
                storedTime.minute == scheduledTime.minute) {
              existingIndex = i;
              break;
            }
          }
        }
        
        if (existingIndex >= 0) {
          // Update existing entry
          missedDoses[existingIndex]['status'] = status;
          missedDoses[existingIndex]['updatedAt'] = Timestamp.now();
        } else {
          // Add new entry
          missedDoses.add({
            'scheduled': Timestamp.fromDate(scheduledTime),
            'status': status,
            'createdAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });
        }
        
        transaction.update(docRef, {'missedDoses': missedDoses});
      });
      
      print("[MedicationDetailService] Updated missedDoses for $docId at ${scheduledTime.toString()} to $status");
      
    } catch (e) {
      print("[MedicationDetailService] Error updating missedDoses: $e");
      // Don't rethrow - we don't want this to break the main flow if it fails
    }
  }
  
  // Helper method to update medication times for rescheduled doses
  Future<void> _updateRescheduledTime(String userId, String docId, DateTime? originalTime, DateTime newScheduledTime) async {
    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .doc(docId);
          
      DocumentSnapshot snapshot = await docRef.get();
      if (!snapshot.exists) {
        print("[MedicationDetailService] Document not found for updating times");
        return;
      }
      
      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      
      // Check if this is a daily medication with simple time format
      if (data.containsKey('times') && data['times'] is List) {
        List<dynamic> times = List.from(data['times']);
        
        // Format the new time as a string in the format the app expects (e.g. "8:00 صباحاً")
        final int hour = newScheduledTime.hour;
        final int minute = newScheduledTime.minute;
        final bool isAM = hour < 12;
        final int hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        final String minuteStr = minute.toString().padLeft(2, '0');
        final String period = isAM ? 'صباحاً' : 'مساءً';
        final String formattedTime = '$hour12:$minuteStr $period';
        
        // First, check if we're trying to reschedule from a notification (no originalTime)
        // In this case, we should update an existing time rather than add a new one
        if (originalTime == null && times.isNotEmpty) {
          // Just update the first time in the list if no original time specified
          print("[MedicationDetailService] No original time provided, updating first time entry");
          if (times[0] is String) {
            times[0] = formattedTime;
          } else if (times[0] is Map && times[0].containsKey('time')) {
            times[0]['time'] = formattedTime;
          }
          
          await docRef.update({'times': times});
          
          // Update timeSlots too
          if (data.containsKey('timeSlots') && data['timeSlots'] is List) {
            List<dynamic> timeSlots = List.from(data['timeSlots']);
            if (timeSlots.isNotEmpty && timeSlots[0] is Map &&
                timeSlots[0].containsKey('hour') && timeSlots[0].containsKey('minute')) {
              timeSlots[0] = {
                'hour': newScheduledTime.hour,
                'minute': newScheduledTime.minute
              };
              await docRef.update({'timeSlots': timeSlots});
            }
          }
          return;
        }
        
        bool timeUpdated = false;
        
        // If we have an original time to replace
        if (originalTime != null) {
          // Try to find and replace the original time
          for (int i = 0; i < times.length; i++) {
            if (times[i] is String) {
              // Simple time format
              String timeStr = times[i] as String;
              // Improved time comparison
              if (_isTimeApproximatelyEqual(timeStr, originalTime)) {
                print("[MedicationDetailService] Replacing time entry: '${times[i]}' with '$formattedTime'");
                times[i] = formattedTime;
                timeUpdated = true;
                break;
              }
            } else if (times[i] is Map) {
              // Complex time format
              var timeMap = times[i] as Map;
              if (timeMap.containsKey('time') && timeMap['time'] is String) {
                String timeStr = timeMap['time'] as String;
                if (_isTimeApproximatelyEqual(timeStr, originalTime)) {
                  print("[MedicationDetailService] Replacing complex time entry: '${timeMap['time']}' with '$formattedTime'");
                  timeMap['time'] = formattedTime;
                  timeUpdated = true;
                  break;
                }
              }
            }
          }
        }

        if (!timeUpdated && times.isNotEmpty) {
          print("[MedicationDetailService] No matching time found, modifying the first time entry");
          
          if (times[0] is String) {
            times[0] = formattedTime;
          } else if (times[0] is Map && times[0].containsKey('time')) {
            times[0]['time'] = formattedTime;
          }
          timeUpdated = true;
        }
        else if (!timeUpdated && times.isEmpty) {
          print("[MedicationDetailService] Times array is empty, adding new time entry");
          times.add(formattedTime);
        }
        
        print("[MedicationDetailService] Updating document with times: $times");
        // Update the document with the new times array
        await docRef.update({'times': times});
        
        // Also update timeSlots for UI consistency
        if (data.containsKey('timeSlots') && data['timeSlots'] is List) {
          List<dynamic> timeSlots = List.from(data['timeSlots']);
          
          bool slotUpdated = false;
          // Try to update an existing slot
          if (originalTime != null) {
            for (int i = 0; i < timeSlots.length; i++) {
              if (timeSlots[i] is Map && 
                  timeSlots[i].containsKey('hour') && 
                  timeSlots[i].containsKey('minute')) {
                
                int slotHour = timeSlots[i]['hour'];
                int slotMinute = timeSlots[i]['minute'];
                
                if (slotHour == originalTime.hour && slotMinute == originalTime.minute) {
                  timeSlots[i] = {
                    'hour': newScheduledTime.hour,
                    'minute': newScheduledTime.minute
                  };
                  slotUpdated = true;
                  break;
                }
              }
            }
          }
          
          // If we didn't update any existing slot but there are slots available
          if (!slotUpdated && timeSlots.isNotEmpty) {
            // Update the first slot instead of adding a new one
            timeSlots[0] = {
              'hour': newScheduledTime.hour,
              'minute': newScheduledTime.minute
            };
            slotUpdated = true;
          }
          // Only if the timeSlots array is completely empty, add a new slot
          else if (!slotUpdated && timeSlots.isEmpty) {
            timeSlots.add({
              'hour': newScheduledTime.hour,
              'minute': newScheduledTime.minute
            });
          }
          
          await docRef.update({'timeSlots': timeSlots});
        }
      } else {
        print("[MedicationDetailService] Document does not have 'times' array or it's not a list");
      }
      
    } catch (e) {
      print("[MedicationDetailService] Error updating medication times: $e");
      // Don't rethrow
    }
  }

  // Add this improved method to check if a time string approximately equals a DateTime
  bool _isTimeApproximatelyEqual(String timeStr, DateTime dateTime) {
    // Parse the time string to TimeOfDay
    TimeOfDay? parsedTime = _parseTime(timeStr);
    if (parsedTime == null) return false;
    
    // Compare hour and minute components
    return parsedTime.hour == dateTime.hour && parsedTime.minute == dateTime.minute;
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

