import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'time_utils.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);

class DoseScheduleServices {
  final User? user;
  // Cache to avoid repeated calculations
  Map<String, Map<DateTime, List<Map<String, dynamic>>>> _doseCache = {};
  
  DoseScheduleServices({this.user});

  // Add this public method to clear the cache
  void clearCache() {
    _doseCache.clear();
    print("Dose cache cleared."); // Optional: for debugging
  }

  Future<Map<DateTime, List<Map<String, dynamic>>>> fetchDoses(
      BuildContext context, {DateTime? startRangeDate, DateTime? endRangeDate}) async {
    if (user == null) return {};

    // Default to current month +/- 1 month if not specified
    final now = DateTime.now();
    startRangeDate ??= DateTime(now.year, now.month - 1, 1);
    endRangeDate ??= DateTime(now.year, now.month + 1, 0);
    
    final String cacheKey = '${startRangeDate.toIso8601String()}_${endRangeDate.toIso8601String()}';
    
    // Return cached data if available
    if (_doseCache.containsKey(cacheKey)) {
      return _doseCache[cacheKey]!;
    }

    final Map<DateTime, List<Map<String, dynamic>>> doses = {};
    final String userId = user!.uid;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String medicationName = data['name'] as String? ?? 'دواء غير مسمى';
        final String dosage = data['dosage'] as String? ?? 'غير محددة';
        final Timestamp? startTimestamp = data['startDate'] as Timestamp?;
        final Timestamp? endTimestamp = data['endDate'] as Timestamp?;

        if (startTimestamp == null) continue;

        String resolvedFrequencyType = 'يومي';
        if (data.containsKey('frequencyType') && data['frequencyType'] == 'اسبوعي') {
          resolvedFrequencyType = 'اسبوعي';
        } else if (data.containsKey('frequency')) {
          final String frequencyRaw = data['frequency'] as String? ?? '';
          final List<String> frequencyParts = frequencyRaw.split(" ");
          if (frequencyParts.length > 1 && frequencyParts[1] == 'اسبوعي') {
            resolvedFrequencyType = 'اسبوعي';
          }
        }

        final List<dynamic> timesRaw = data['times'] ?? [];
        final String imageUrl = data['imageUrl'] as String? ?? '';
        final String imgbbDeleteHash = data['imgbbDeleteHash'] as String? ?? '';

        final DateTime startDate = startTimestamp.toDate();
        final DateTime? endDate = endTimestamp?.toDate();
        
        // Only process dates within the specified range
        final DateTime effectiveStartDate = startDate.isAfter(startRangeDate) ? startDate : startRangeDate;
        final DateTime effectiveEndDate = endDate != null && endDate.isBefore(endRangeDate) ? endDate : endRangeDate;

        if (resolvedFrequencyType == 'يومي') {
          _processDailyMedication(doses, effectiveStartDate, effectiveEndDate, timesRaw, medicationName, dosage, doc.id, imageUrl, imgbbDeleteHash, context);
        } else if (resolvedFrequencyType == 'اسبوعي') {
          _processWeeklyMedication(doses, effectiveStartDate, effectiveEndDate, timesRaw, data, medicationName, dosage, doc.id, imageUrl, imgbbDeleteHash, context);
        }
      }

      doses.forEach((date, meds) {
        meds.sort((a, b) {
          final TimeOfDay timeA = a['timeOfDay'];
          final TimeOfDay timeB = b['timeOfDay'];
          final int cmp = timeA.hour != timeB.hour
              ? timeA.hour.compareTo(timeB.hour)
              : timeA.minute.compareTo(timeB.minute);
          if (cmp != 0) return cmp;
          return (a['medicationName'] as String).compareTo(b['medicationName'] as String);
        });
      });
      
      // Cache the result
      _doseCache[cacheKey] = doses;
      return doses;
    } catch (e, stackTrace) {
      print('Error fetching doses: $e');
      return {};
    }
  }
  
  void _processDailyMedication(
      Map<DateTime, List<Map<String, dynamic>>> doses,
      DateTime startDate,
      DateTime endDate,
      List<dynamic> timesRaw,
      String medicationName,
      String dosage,
      String docId,
      String imageUrl,
      String imgbbDeleteHash,
      BuildContext context) {

    // Pre-parse all times for better performance
    List<TimeOfDay> timesParsed = timesRaw
        .map((t) => TimeUtils.parseTime(t))
        .whereType<TimeOfDay>()
        .toList();
        
    if (timesParsed.isEmpty) return;

    // More efficient calculation of days between dates
    int dayDifference = endDate.difference(startDate).inDays;
    
    for (int i = 0; i <= dayDifference; i++) {
      final DateTime currentDate = startDate.add(Duration(days: i));
      final DateTime normalizedDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
      
      doses.putIfAbsent(normalizedDate, () => []);
      for (var time in timesParsed) {
        doses[normalizedDate]!.add({
          'medicationName': medicationName,
          'dosage': dosage,
          'timeOfDay': time,
          'timeString': TimeUtils.formatTimeOfDay(context, time),
          'docId': docId,
          'imageUrl': imageUrl,
          'imgbbDeleteHash': imgbbDeleteHash,
        });
      }
    }
  }
  
  void _processWeeklyMedication(
      Map<DateTime, List<Map<String, dynamic>>> doses,
      DateTime startDate,
      DateTime endDate,
      List<dynamic> timesRaw,
      Map<String, dynamic> data,
      String medicationName,
      String dosage,
      String docId,
      String imageUrl,
      String imgbbDeleteHash,
      BuildContext context) {

    final Map<int, List<TimeOfDay>> weeklySchedule = {};

    // Process day-specific times
    for (var item in timesRaw) {
      if (item is Map) {
        int? dayValue;
        dynamic timeValue;

        if (item.containsKey('day')) {
          var day = item['day'];
          if (day is int) dayValue = day;
          else if (day is String) dayValue = int.tryParse(day);
          else if (day is double) dayValue = day.toInt();
        }

        timeValue = item['time'];
        if (timeValue is Map && timeValue.containsKey('time')) {
          timeValue = timeValue['time'];
        }

        if (dayValue != null && dayValue >= 1 && dayValue <= 7) {
          final parsedTime = TimeUtils.parseTime(timeValue);
          if (parsedTime != null) {
            weeklySchedule.putIfAbsent(dayValue, () => []).add(parsedTime);
          }
        }
      }
    }

    // Process selectedWeekdays
    if (data.containsKey('selectedWeekdays') && data['selectedWeekdays'] is List) {
      List<int> selectedDays = List<int>.from(
          (data['selectedWeekdays'] as List)
              .map((day) => day is int ? day : int.tryParse(day.toString()))
              .where((day) => day != null && day >= 1 && day <= 7)
      );

      List<TimeOfDay> timesForSelectedDays = timesRaw
          .whereType<String>()
          .map((t) => TimeUtils.parseTime(t))
          .whereType<TimeOfDay>()
          .toList();

      if(timesForSelectedDays.isEmpty && timesRaw.isNotEmpty && timesRaw.first is Map && timesRaw.first.containsKey('time')) {
        final firstTime = TimeUtils.parseTime(timesRaw.first['time']);
        if (firstTime != null) timesForSelectedDays.add(firstTime);
      }

      if (timesForSelectedDays.isNotEmpty) {
        for (int dayValue in selectedDays) {
          weeklySchedule.putIfAbsent(dayValue, () => []).addAll(timesForSelectedDays);
        }
      }
    }

    if (weeklySchedule.isEmpty) return;
    
    // More efficient date iteration
    int dayDifference = endDate.difference(startDate).inDays;
    
    for (int i = 0; i <= dayDifference; i++) {
      final DateTime currentDate = startDate.add(Duration(days: i));
      final int currentWeekday = currentDate.weekday;
      
      if (weeklySchedule.containsKey(currentWeekday)) {
        final List<TimeOfDay> timesForThisDay = weeklySchedule[currentWeekday]!;
        final DateTime normalizedDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
        
        doses.putIfAbsent(normalizedDate, () => []);
        for (var time in timesForThisDay) {
          doses[normalizedDate]!.add({
            'medicationName': medicationName,
            'dosage': dosage,
            'timeOfDay': time,
            'timeString': TimeUtils.formatTimeOfDay(context, time),
            'docId': docId,
            'imageUrl': imageUrl,
            'imgbbDeleteHash': imgbbDeleteHash,
          });
        }
      }
    }
  }

  Future<String> checkDoseStatus(String docId, String timeString, DateTime selectedDay) async {
    if (user == null) return 'pending';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('medicines')
          .doc(docId)
          .get();

      if (!doc.exists) return 'pending';

      final data = doc.data()!;
      final missedDoses = data['missedDoses'] as List<dynamic>? ?? [];
      final normalizedSelectedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);

      final doseTime = TimeUtils.parseTime(timeString);
      if (doseTime == null) return 'pending';

      String currentStatus = 'pending';
      for (var dose in missedDoses) {
        if (dose is Map<String, dynamic> && dose.containsKey('scheduled') && dose.containsKey('status')) {
          final scheduledTimestamp = dose['scheduled'] as Timestamp?;
          if (scheduledTimestamp != null) {
            final scheduledDate = scheduledTimestamp.toDate();
            final normalizedScheduledDate = DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day);

            if (scheduledDate.hour == doseTime.hour &&
                scheduledDate.minute == doseTime.minute &&
                isSameDay(normalizedScheduledDate, normalizedSelectedDay)) {
              currentStatus = dose['status'] as String? ?? 'pending';
              break;
            }
          }
        }
      }

      return currentStatus;
    } catch (e) {
      print('Error checking dose status for $docId: $e');
      return 'pending';
    }
  }

  Future<bool> toggleDoseStatus(String docId, String timeString, DateTime selectedDay, String currentStatus) async {
    if (user == null) return false;

    final normalizedSelectedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final doseTime = TimeUtils.parseTime(timeString);

    if (doseTime == null) {
      print("Error: Could not parse dose time for toggling status.");
      return false;
    }

    final targetDateTime = DateTime(
      normalizedSelectedDay.year,
      normalizedSelectedDay.month,
      normalizedSelectedDay.day,
      doseTime.hour,
      doseTime.minute,
    );
    final targetTimestamp = Timestamp.fromDate(targetDateTime);
    final newStatus = currentStatus == 'taken' ? 'pending' : 'taken';

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('medicines')
          .doc(docId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception("Medication document does not exist!");
        }

        final data = snapshot.data()!;
        final missedDosesRaw = data['missedDoses'] as List<dynamic>? ?? [];
        final List<Map<String, dynamic>> missedDoses = List<Map<String, dynamic>>.from(
            missedDosesRaw.whereType<Map<String, dynamic>>()
        );

        int foundIndex = -1;
        for (int i = 0; i < missedDoses.length; i++) {
          final dose = missedDoses[i];
          final scheduledTimestamp = dose['scheduled'] as Timestamp?;
          if (scheduledTimestamp != null && scheduledTimestamp == targetTimestamp) {
            foundIndex = i;
            break;
          }
        }

        if (foundIndex != -1) {
          missedDoses[foundIndex]['status'] = newStatus;
          missedDoses[foundIndex]['updatedAt'] = Timestamp.now();
        } else {
          missedDoses.add({
            'scheduled': targetTimestamp,
            'status': newStatus,
            'createdAt': Timestamp.now(),
          });
        }

        transaction.update(docRef, {
          'missedDoses': missedDoses,
          'lastUpdated': Timestamp.now(),
        });
      });

      return true;
    } catch (e) {
      print('Error toggling dose status: $e');
      return false;
    }
  }

  Future<bool> finishMedication(String docId, DateTime endDate) async {
    if (user == null) return false;

    try {
      final DateTime endOfSelectedDay = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('medicines')
          .doc(docId)
          .update({'endDate': Timestamp.fromDate(endOfSelectedDay)});

      return true;
    } catch (e) {
      print('Error finishing medication: $e');
      return false;
    }
  }

  Future<bool> deleteMedication(String docId, String imgbbDeleteHash) async {
    if (user == null) return false;

    try {
      if (imgbbDeleteHash.isNotEmpty) {
        await _deleteImgBBImage(imgbbDeleteHash);
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('medicines')
          .doc(docId)
          .delete();
          
      // Clear the cache after successful deletion to force a fresh fetch
      _doseCache.clear();

      return true;
    } catch (e) {
      print('Error deleting medication: $e');
      return false;
    }
  }

  Future<void> _deleteImgBBImage(String deleteHash) async {
    const String imgbbApiKey = 'YOUR_IMGBB_API_KEY';

    if (imgbbApiKey == 'YOUR_IMGBB_API_KEY' || imgbbApiKey.isEmpty) {
      print("WARNING: ImgBB API Key not configured. Skipping image deletion.");
      return;
    }

    final url = Uri.parse('https://api.imgbb.com/1/image/$deleteHash');

    try {
      final response = await http.post(
        url,
        body: {'key': imgbbApiKey, 'action': 'delete'},
      );

      if (response.statusCode == 200) {
        print("ImgBB image deletion successful: $deleteHash");
      } else {
        print("Failed to delete ImgBB image: ${response.statusCode}, ${response.body}");
      }
    } catch (e) {
      print("Error deleting ImgBB image: $e");
    }
  }

  bool isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month && date1.day == date2.day;
  }
}

