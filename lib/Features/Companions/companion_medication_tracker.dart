import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../Core/Services/AlarmNotificationHelper.dart';

class CompanionMedicationData {
  final String companionId;
  final String companionName;
  final List<MedicationData> medications;

  CompanionMedicationData({
    required this.companionId,
    required this.companionName,
    required this.medications,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CompanionMedicationData) return false;
    if (companionId != other.companionId || companionName != other.companionName) return false;
    if (medications.length != other.medications.length) return false;

    List<MedicationData> sortedMeds = List.from(medications)..sort((a, b) => a.id.compareTo(b.id));
    List<MedicationData> otherSortedMeds = List.from(other.medications)..sort((a, b) => a.id.compareTo(b.id));

    for (int i = 0; i < sortedMeds.length; i++) {
      if (sortedMeds[i] != otherSortedMeds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    List<MedicationData> sortedMeds = List.from(medications)..sort((a, b) => a.id.compareTo(b.id));
    return Object.hash(companionId, companionName, Object.hashAll(sortedMeds));
  }

}

class MedicationData {
  final String id;
  final String name;
  final String frequencyType;
  final List<dynamic> times;
  final DateTime startDate;
  final DateTime? endDate;

  MedicationData({
    required this.id,
    required this.name,
    required this.frequencyType,
    required this.times,
    required this.startDate,
    this.endDate,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MedicationData) return false;
    return id == other.id &&
        name == other.name &&
        frequencyType == other.frequencyType &&
        _areTimesEqual(times, other.times) &&
        startDate.isAtSameMomentAs(other.startDate) &&
        (endDate == other.endDate || (endDate != null && other.endDate != null && endDate!.isAtSameMomentAs(other.endDate!)));
  }

  @override
  int get hashCode {
    List<String> sortedTimes = List.from(times.map((t) => t.toString()))..sort();
    return Object.hash(id, name, frequencyType, Object.hashAll(sortedTimes), startDate.millisecondsSinceEpoch, endDate?.millisecondsSinceEpoch);
  }


  static bool _areTimesEqual(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;
    List<String> sortedA = List.from(a.map((t) => t.toString()))..sort();
    List<String> sortedB = List.from(b.map((t) => t.toString()))..sort();
    for (int i = 0; i < sortedA.length; i++) {
      if (sortedA[i] != sortedB[i]) return false;
    }
    return true;
  }
}

class CompanionMedicationTracker {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static List<CompanionMedicationData>? _lastFetchedCompanionData;

  static Future<void> scheduleCompanionDoseCheck({
    required String companionId,
    required String companionName,
    required String medicationId,
    required String medicationName,
    required DateTime scheduledTime,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      final int checkId = generateCompanionCheckId(companionId, medicationId, scheduledTime);

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('companion_dose_checks')
          .doc(checkId.toString())
          .set({
        'companionId': companionId,
        'companionName': companionName,
        'medicationId': medicationId,
        'medicationName': medicationName,
        'scheduledTime': Timestamp.fromDate(scheduledTime),
        'processed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("[CompanionMedicationTracker] Error storing companion dose check: $e");
    }
  }

  static Future<bool> performCompanionDoseCheck({
    required String companionId,
    required String medicationId,
    required DateTime scheduledTime,
  }) async {
    try {
      final startOfDay = DateTime(scheduledTime.year, scheduledTime.month, scheduledTime.day);

      final docRef = _firestore
          .collection('users')
          .doc(companionId)
          .collection('medicines')
          .doc(medicationId);

      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        return false;
      }

      final data = docSnapshot.data()!;
      final List<dynamic> missedDoses = data['missedDoses'] ?? [];

      for (final dose in missedDoses) {
        if (dose is Map<String, dynamic>) {
          final scheduled = dose['scheduled'] as Timestamp?;
          final status = dose['status'] as String?;

          if (scheduled != null && status == 'taken') {
            final doseTime = scheduled.toDate();
            final doseDate = DateTime(doseTime.year, doseTime.month, doseTime.day);

            if (doseDate.isAtSameMomentAs(startOfDay) &&
                (doseTime.hour == scheduledTime.hour &&
                    (doseTime.minute - scheduledTime.minute).abs() < 15)) {
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      print("[CompanionMedicationTracker] Error checking companion dose: $e");
      return false;
    }
  }

  static Future<void> sendCompanionMissedDoseNotification({
    required String companionName,
    required String medicationName,
    required DateTime scheduledTime,
  }) async {
    try {
      final formattedTime = _formatTimeOfDay(TimeOfDay.fromDateTime(scheduledTime));
      final int notificationId = DateTime.now().microsecondsSinceEpoch % 100000000;
      final payload = "companion_missed_${notificationId.toString()}";

      await AlarmNotificationHelper.scheduleAlarmNotification(
        id: notificationId,
        title: "تنبيه: $companionName لم يتناول الدواء",
        body: "يبدو أن $companionName لم يتناول $medicationName المُجدول في $formattedTime. تحقق من حالتهم.",
        scheduledTime: tz.TZDateTime.now(tz.local).add(const Duration(seconds: 2)),
        medicationId: payload,
        isCompanionCheck: true,
      );
    } catch (e) {
      print("[CompanionMedicationTracker] Error sending companion missed dose notification: $e");
    }
  }

  static Future<void> processCompanionDoseCheck(String payload) async {
    if (!payload.startsWith("companion_check_")) {
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    final medicationId = payload.replaceFirst("companion_check_", "");

    try {
      final checksQuery = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('companion_dose_checks')
          .where('medicationId', isEqualTo: medicationId)
          .where('processed', isEqualTo: false)
          .get();

      for (final doc in checksQuery.docs) {
        final data = doc.data();
        final companionId = data['companionId'] as String?;
        final companionName = data['companionName'] as String?;
        final medicationName = data['medicationName'] as String?;
        final scheduledTimeTs = data['scheduledTime'] as Timestamp?;

        if (companionId != null && companionName != null &&
            medicationName != null && scheduledTimeTs != null) {

          final scheduledTime = scheduledTimeTs.toDate();
          final wasTaken = await performCompanionDoseCheck(
            companionId: companionId,
            medicationId: medicationId,
            scheduledTime: scheduledTime,
          );

          await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('companion_dose_checks')
              .doc(doc.id)
              .update({'processed': true});
        }
      }
    } catch (e) {
      print("[CompanionMedicationTracker] Error processing companion dose check: $e");
    }
  }

  static Future<void> runPendingChecks() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      final now = DateTime.now();
      final checkTime = Timestamp.fromDate(now);

      final pendingChecksQuery = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('companion_dose_checks')
          .where('processed', isEqualTo: false)
          .where('scheduledTime', isLessThan: checkTime)
          .get();

      for (final doc in pendingChecksQuery.docs) {
        final data = doc.data();
        final companionId = data['companionId'] as String?;
        final companionName = data['companionName'] as String?;
        final medicationId = data['medicationId'] as String?;
        final medicationName = data['medicationName'] as String?;
        final scheduledTimeTs = data['scheduledTime'] as Timestamp?;

        if (companionId != null && companionName != null && medicationId != null &&
            medicationName != null && scheduledTimeTs != null) {

          final scheduledTime = scheduledTimeTs.toDate();

          final wasTaken = await performCompanionDoseCheck(
            companionId: companionId,
            medicationId: medicationId,
            scheduledTime: scheduledTime,
          );

          if (!wasTaken) {
            await sendCompanionMissedDoseNotification(
              companionName: companionName,
              medicationName: medicationName,
              scheduledTime: scheduledTime,
            );
          }
          await doc.reference.update({'processed': true});
        }
      }
    } catch (e) {
      print("[CompanionMedicationTracker] Error running pending companion dose checks: $e");
    }
  }

  static int generateCompanionCheckId(String companionId, String medicationId, DateTime time) {
    final timeHash = time.millisecondsSinceEpoch ~/ 60000;
    final combHash = '${companionId}_${medicationId}_$timeHash'.hashCode;
    final result = 0x3C000000 + (combHash & 0x0FFFFFFF);
    return result;
  }

  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'مساءً' : 'صباحاً';
    return '$hour:$minute $period';
  }

  static Future<void> fetchAndScheduleCompanionMedications() async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      final List<CompanionMedicationData> newCompanionData = [];
      final companionsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('companions')
          .get();

      final tz.Location local = tz.local;
      final now = tz.TZDateTime.now(local);
      final todayStart = tz.TZDateTime(local, now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final DateFormat logTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss ZZZZ', 'en_US');


      for (final companionDoc in companionsSnapshot.docs) {
        final companionData = companionDoc.data();
        final companionName = companionData['name'] ?? '';
        final companionEmail = companionData['email'] ?? '';

        String? companionUserId;
        if (companionEmail is String && companionEmail.isNotEmpty) {
          final query = await _firestore
              .collection('users')
              .where('email', isEqualTo: companionEmail)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            companionUserId = query.docs.first.id;
          } else {
            continue;
          }
        } else {
          continue;
        }

        final medsSnapshot = await _firestore
            .collection('users')
            .doc(companionUserId)
            .collection('medicines')
            .get();

        final List<MedicationData> medications = [];

        for (final medDoc in medsSnapshot.docs) {
          final medData = medDoc.data();
          final medicationId = medDoc.id;
          final medicationName = medData['name'] ?? '';
          final timesRaw = medData['times'] ?? [];
          final frequencyType = medData['frequencyType'] ?? 'يومي';
          final startTimestamp = medData['startDate'] as Timestamp?;
          final endTimestamp = medData['endDate'] as Timestamp?;

          if (startTimestamp == null) {
            continue;
          }

          final startDate = startTimestamp.toDate();
          final endDate = endTimestamp?.toDate();

          medications.add(MedicationData(
            id: medicationId,
            name: medicationName,
            frequencyType: frequencyType,
            times: List.from(timesRaw),
            startDate: startDate,
            endDate: endDate,
          ));
        }

        newCompanionData.add(CompanionMedicationData(
          companionId: companionUserId!,
          companionName: companionName,
          medications: medications,
        ));
      }

      bool hasChanges = true;
      if (_lastFetchedCompanionData != null) {
        if (_lastFetchedCompanionData!.length == newCompanionData.length) {
          hasChanges = false;
          List<CompanionMedicationData> sortedOld = List.from(_lastFetchedCompanionData!)..sort((a, b) => a.companionId.compareTo(b.companionId));
          List<CompanionMedicationData> sortedNew = List.from(newCompanionData)..sort((a, b) => a.companionId.compareTo(b.companionId));

          for (int i = 0; i < sortedNew.length; i++) {
            if (sortedNew[i] != sortedOld[i]) {
              hasChanges = true;
              break;
            }
          }
        }
      }


      if (!hasChanges) {
        print("[CompanionMedicationTracker] No changes detected in companion medications. Skipping update.");
        return;
      }
      print("[CompanionMedicationTracker] Changes detected in companion medications. Updating notifications...");


      _lastFetchedCompanionData = newCompanionData;

      await _scheduleCompanionNotifications(newCompanionData, now, todayStart, todayEnd, logTimeFormat);
      print("[CompanionMedicationTracker] Companion medications for today fetched and notifications scheduled.");


    } catch (e, stackTrace) {
      print("[CompanionMedicationTracker] Error fetching/scheduling companion medications: $e\n$stackTrace");
    }
  }

  static Future<void> _scheduleCompanionNotifications(
      List<CompanionMedicationData> companionData,
      tz.TZDateTime now,
      tz.TZDateTime todayStart,
      tz.TZDateTime todayEnd,
      DateFormat logTimeFormat
      ) async {
    final tz.Location local = tz.local;

    try {
      final pendingNotifications = await AlarmNotificationHelper.getPendingNotifications();
      for (final notification in pendingNotifications) {
        final payload = notification.payload ?? '';
        // Cancel all companion notifications (both reminder and check types)
        if (payload.startsWith('companion_reminder_') || payload.startsWith('companion_check_') || 
            (payload.isNotEmpty && !payload.startsWith('companion_missed_') && notification.title?.contains('جرعة مرافق') == true)) {
          print("[Companion Schedule] Canceling existing companion notification ID: ${notification.id}");
          await AlarmNotificationHelper.cancelNotification(notification.id);
        }
      }
    } catch (e) {
      print("[CompanionMedicationTracker] Error canceling existing notifications: $e");
    }

    for (final companion in companionData) {
      for (final medication in companion.medications) {
        final tzStartDate = tz.TZDateTime.from(medication.startDate, local);
        final tzEndDate = medication.endDate != null ? tz.TZDateTime.from(medication.endDate!, local) : null;

        if (now.isBefore(tzStartDate) || (tzEndDate != null && now.isAfter(tzEndDate))) {
          continue;
        }

        List<TimeOfDay> parsedTimes = [];
        if (medication.frequencyType == 'يومي') {
          for (var t in medication.times) {
            if (t is String) {
              final parsed = _parseTime(t);
              if (parsed != null) parsedTimes.add(parsed);
            } else if (t is Map && t['time'] is String) {
              final parsed = _parseTime(t['time']);
              if (parsed != null) parsedTimes.add(parsed);
            }
          }
        } else if (medication.frequencyType == 'اسبوعي') {
          for (var t in medication.times) {
            if (t is Map && t['time'] is String && t['day'] != null) {
              final parsed = _parseTime(t['time']);
              if (parsed != null) {
                int day = t['day'] is int ? t['day'] : int.tryParse(t['day'].toString()) ?? 0;
                // Ensure day matches Flutter's weekday (Mon=1, Sun=7)
                int flutterWeekday = (day == 0) ? 7 : day; // Assuming 0 was Sunday from JS? Adjust if needed.
                if (flutterWeekday == now.weekday) parsedTimes.add(parsed);
              }
            }
          }
        }

        for (final tod in parsedTimes) {
          // Calculate potential dose time for today
          tz.TZDateTime doseTime = tz.TZDateTime(local, now.year, now.month, now.day, tod.hour, tod.minute);

          // If the calculated dose time for today is in the past, calculate it for the next valid day (tomorrow or next week day)
          if (doseTime.isBefore(now)) {
            if (medication.frequencyType == 'اسبوعي') {
              tz.TZDateTime nextDay = now.add(Duration(days:1));
              while(nextDay.weekday != doseTime.weekday) { // Find the next occurrence of that weekday
                nextDay = nextDay.add(Duration(days:1));
              }
              doseTime = tz.TZDateTime(local, nextDay.year, nextDay.month, nextDay.day, tod.hour, tod.minute);
            } else { // Daily
              doseTime = doseTime.add(Duration(days:1));
            }
            print("[Companion Schedule Check] Original dose time ${logTimeFormat.format(tz.TZDateTime(local, now.year, now.month, now.day, tod.hour, tod.minute))} was in the past. Adjusted to next occurrence: ${logTimeFormat.format(doseTime)}");
          }


          print("[Companion Schedule Check] Considering Dose Time: ${logTimeFormat.format(doseTime)} (Now: ${logTimeFormat.format(now)})");

          if (doseTime.isAfter(now)) {
            if (tzEndDate == null || doseTime.isBefore(tzEndDate)) {
              print("[Companion Schedule Check] Scheduling reminder for ${medication.name} at ${logTimeFormat.format(doseTime)}");
              
              // Register the check in Firestore for background processing
              await scheduleCompanionDoseCheck(
                companionId: companion.companionId,
                companionName: companion.companionName,
                medicationId: medication.id,
                medicationName: medication.name,
                scheduledTime: doseTime,
              );
              print("[Companion Schedule] Added companion dose check to Firestore queue");
              
              // Schedule a single notification that serves both as reminder and check
              final reminderPayload = "companion_reminder_${medication.id}";
              final notificationId = AlarmNotificationHelper.generateNotificationId(reminderPayload, doseTime);

              try {
                await AlarmNotificationHelper.scheduleAlarmNotification(
                  id: notificationId,
                  title: "⏰ تذكير للمرافق: ${companion.companionName}",
                  body: "حان الآن موعد جرعة ${medication.name} للمرافق ${companion.companionName}.",
                  scheduledTime: doseTime,
                  medicationId: reminderPayload,
                  isCompanionCheck: true, // Mark as companion notification
                );
                print("[Companion Schedule] Successfully scheduled companion notification ID $notificationId");
              } catch (e) {
                print("[CompanionMedicationTracker] ERROR scheduling companion notification ID $notificationId: $e");
              }
              
            } else {
              print("[Companion Schedule Check] Skipping dose for ${medication.name} at ${logTimeFormat.format(doseTime)} (After End Date: ${logTimeFormat.format(tzEndDate!)})");
            }
          } else {
            print("[Companion Schedule Check] Skipping dose for ${medication.name} at ${logTimeFormat.format(doseTime)} (Is NOT After Now)");
          }
        }
      }
    }
  }

  static TimeOfDay? _parseTime(String timeStr) {
    try {
      String normalized = timeStr.trim();
      bool isPM = false;
      bool isAM = false;

      if (normalized.contains('مساء')) {
        isPM = true;
        normalized = normalized.replaceAll('مساءً', '').replaceAll('مساء', '').trim();
      } else if (normalized.contains('صباح')) {
        isAM = true;
        normalized = normalized.replaceAll('صباحاً', '').replaceAll('صباح', '').trim();
      }

      final parts = normalized.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));

        if (isPM && hour < 12) hour += 12;
        if (isAM && hour == 12) hour = 0; // 12 AM is 00:00

        // Handle 12 PM (remains 12)
        if(!isPM && !isAM && hour == 12) {
          // Could be 12 noon (12:xx) or 12 midnight (00:xx) - ambiguous without AM/PM
          // Assuming 24h format if AM/PM isn't present, so 12 is noon.
          // If it's guaranteed to be 12h format string, this needs adjustment.
        }


        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (e) {
      print("[CompanionMedicationTracker] _parseTime error parsing '$timeStr': $e");
    }
    print("[CompanionMedicationTracker] _parseTime failed to parse '$timeStr'");
    return null;
  }
}

