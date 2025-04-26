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

  DoseScheduleServices({this.user});

  Future<Map<DateTime, List<Map<String, dynamic>>>> fetchDoses(BuildContext context) async {
    if (user == null) return {};

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

        if (startTimestamp == null) {
          print('Document ${doc.id} missing start date. Skipping.');
          continue;
        }

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

        print('Processing medication ${doc.id}: $medicationName, frequency type: $resolvedFrequencyType');

        final List<dynamic> timesRaw = data['times'] ?? [];
        final String imageUrl = data['imageUrl'] as String? ?? '';
        final String imgbbDeleteHash = data['imgbbDeleteHash'] as String? ?? '';

        final DateTime startDate = startTimestamp.toDate();
        final DateTime? endDate = endTimestamp?.toDate();

        if (resolvedFrequencyType == 'يومي') {
          DateTime currentDate = startDate;
          while (endDate == null || !currentDate.isAfter(endDate)) {
            final DateTime normalizedDate = DateTime(currentDate.year, currentDate.month, currentDate.day);

            List<TimeOfDay> timesParsed = timesRaw
                .map((t) => TimeUtils.parseTime(t))
                .whereType<TimeOfDay>()
                .toList();

            if (timesParsed.isNotEmpty) {
              doses.putIfAbsent(normalizedDate, () => []);
              for (var time in timesParsed) {
                doses[normalizedDate]!.add({
                  'medicationName': medicationName,
                  'dosage': dosage,
                  'timeOfDay': time,
                  'timeString': TimeUtils.formatTimeOfDay(context, time),
                  'docId': doc.id,
                  'imageUrl': imageUrl,
                  'imgbbDeleteHash': imgbbDeleteHash,
                });
              }
            }

            currentDate = currentDate.add(const Duration(days: 1));
            if (endDate != null && currentDate.isAfter(endDate)) break;
            if (endDate == null && currentDate.difference(startDate).inDays > (365 * 5)) {
              print("Warning: Daily Medication ${doc.id} has long duration; stopping iteration after 5 years.");
              break;
            }
          }
        } else if (resolvedFrequencyType == 'اسبوعي') {
          print('Weekly medication found: $medicationName');
          print('Times raw data: $timesRaw');

          final Map<int, List<TimeOfDay>> weeklySchedule = {};

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
                  print("Scheduled for weekday $dayValue at $parsedTime");
                } else {
                  print("Could not parse time '$timeValue' for day $dayValue");
                }
              } else {
                print("Invalid or missing day value in weekly schedule item: $item");
              }
            }
          }

          if (data.containsKey('selectedWeekdays') && data['selectedWeekdays'] is List) {
            List<int> selectedDays = List<int>.from(
                (data['selectedWeekdays'] as List)
                    .map((day) => day is int ? day : int.tryParse(day.toString()))
                    .where((day) => day != null && day >= 1 && day <= 7)
            );
            print("Found selectedWeekdays: $selectedDays");

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
                print("Scheduled for weekday $dayValue (from selectedWeekdays) at times: $timesForSelectedDays");
              }
            } else {
              print("Warning: selectedWeekdays found but no valid times could be parsed from timesRaw: $timesRaw");
            }
          }

          if (weeklySchedule.isNotEmpty) {
            DateTime currentDate = startDate;
            while (endDate == null || !currentDate.isAfter(endDate)) {
              final DateTime normalizedDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
              final int currentWeekday = normalizedDate.weekday;

              if (weeklySchedule.containsKey(currentWeekday)) {
                final List<TimeOfDay> timesForThisDay = weeklySchedule[currentWeekday]!;
                print("Match found! Adding doses for ${normalizedDate.toIso8601String()} (weekday $currentWeekday)");

                doses.putIfAbsent(normalizedDate, () => []);
                for (var time in timesForThisDay) {
                  doses[normalizedDate]!.add({
                    'medicationName': medicationName,
                    'dosage': dosage,
                    'timeOfDay': time,
                    'timeString': TimeUtils.formatTimeOfDay(context, time),
                    'docId': doc.id,
                    'imageUrl': imageUrl,
                    'imgbbDeleteHash': imgbbDeleteHash,
                  });
                }
              }

              currentDate = currentDate.add(const Duration(days: 1));
              if (endDate != null && currentDate.isAfter(endDate)) break;
              if (endDate == null && currentDate.difference(startDate).inDays > (365 * 5)) {
                print("Warning: Weekly Medication ${doc.id} has long duration; stopping iteration after 5 years.");
                break;
              }
            }
          } else {
            print("Warning: No valid weekly schedule found for medication ${doc.id}. Check 'times' or 'selectedWeekdays' data.");
          }
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

      return doses;
    } catch (e, stackTrace) {
      print('Error fetching doses: $e');
      print(stackTrace);
      return {};
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