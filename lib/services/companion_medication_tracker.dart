import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'AlarmNotificationHelper.dart';

// Class to store companion medication data for comparison
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

    // Compare each medication
    for (int i = 0; i < medications.length; i++) {
      if (medications[i] != other.medications[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(companionId, companionName, Object.hashAll(medications));
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
  int get hashCode => Object.hash(id, name, frequencyType, Object.hashAll(times), startDate, endDate);

  static bool _areTimesEqual(List<dynamic> a, List<dynamic> b) {
    if (a.length != b.length) return false;

    for (int i = 0; i < a.length; i++) {
      if (a[i].toString() != b[i].toString()) return false;
    }
    return true;
  }
}

class CompanionMedicationTracker {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Store last fetched data
  static List<CompanionMedicationData>? _lastFetchedCompanionData;

  /// Schedule a check for this medication dose at the given time
  static Future<void> scheduleCompanionDoseCheck({
    required String companionId,
    required String companionName,
    required String medicationId,
    required String medicationName,
    required DateTime scheduledTime,
  }) async {
    print("[CompanionMedicationTracker] scheduleCompanionDoseCheck called with companionId=$companionId, companionName=$companionName, medicationId=$medicationId, medicationName=$medicationName, scheduledTime=$scheduledTime");
    final user = _auth.currentUser;
    if (user == null) {
      print("[CompanionMedicationTracker] No authenticated user found. Cannot schedule companion dose check.");
      debugPrint("No authenticated user found. Cannot schedule companion dose check.");
      return;
    }

    try {
      final int checkId = generateCompanionCheckId(companionId, medicationId, scheduledTime);

      print("[CompanionMedicationTracker] Storing companion dose check: companionId=$companionId, medicationId=$medicationId, checkId=$checkId");

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

      print("[CompanionMedicationTracker] Successfully stored companion dose check with ID $checkId");
    } catch (e) {
      print("[CompanionMedicationTracker] Error storing companion dose check: $e");
      debugPrint("Error storing companion dose check: $e");
    }
  }

  /// Check if a companion has taken their medication
  static Future<bool> performCompanionDoseCheck({
    required String companionId,
    required String medicationId,
    required DateTime scheduledTime,
  }) async {
    print("[CompanionMedicationTracker] performCompanionDoseCheck called with companionId=$companionId, medicationId=$medicationId, scheduledTime=$scheduledTime");
    try {
      final startOfDay = DateTime(scheduledTime.year, scheduledTime.month, scheduledTime.day);

      final docRef = _firestore
          .collection('users')
          .doc(companionId)
          .collection('medicines')
          .doc(medicationId);

      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        print("[CompanionMedicationTracker] Medication $medicationId not found for companion $companionId");
        debugPrint("Medication $medicationId not found for companion $companionId");
        return false;
      }

      final data = docSnapshot.data()!;
      final List<dynamic> missedDoses = data['missedDoses'] ?? [];

      print("[CompanionMedicationTracker] Checking missedDoses: $missedDoses");

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
              print("[CompanionMedicationTracker] Found confirmation for dose at $scheduledTime, status: taken");
              debugPrint("Found confirmation for dose at $scheduledTime, status: taken");
              return true;
            }
          }
        }
      }

      print("[CompanionMedicationTracker] No confirmation found for dose at $scheduledTime");
      debugPrint("No confirmation found for dose at $scheduledTime");
      return false;
    } catch (e) {
      print("[CompanionMedicationTracker] Error checking companion dose: $e");
      debugPrint("Error checking companion dose: $e");
      return false;
    }
  }

  /// Send a notification to the user that the companion hasn't taken their medication
  static Future<void> sendCompanionMissedDoseNotification({
    required String companionName,
    required String medicationName,
    required DateTime scheduledTime,
  }) async {
    print("[CompanionMedicationTracker] sendCompanionMissedDoseNotification called with companionName=$companionName, medicationName=$medicationName, scheduledTime=$scheduledTime");
    try {
      final formattedTime = _formatTimeOfDay(TimeOfDay.fromDateTime(scheduledTime));

      final int notificationId = DateTime.now().microsecondsSinceEpoch % 100000000;
      final payload = "companion_missed_${notificationId.toString()}";

      print("[CompanionMedicationTracker] Sending companion missed dose notification: $companionName missed $medicationName at $formattedTime");

      await AlarmNotificationHelper.scheduleAlarmNotification(
        id: notificationId,
        title: "تنبيه: $companionName لم يتناول الدواء",
        body: "يبدو أن $companionName لم يتناول $medicationName المُجدول في $formattedTime. تحقق من حالتهم.",
        scheduledTime: DateTime.now().add(const Duration(seconds: 2)),
        medicationId: payload,
        isCompanionCheck: true,
      );

      print("[CompanionMedicationTracker] Successfully sent companion missed dose notification");
    } catch (e) {
      print("[CompanionMedicationTracker] Error sending companion missed dose notification: $e");
      debugPrint("Error sending companion missed dose notification: $e");
    }
  }

  /// Process background notification to check companion doses
  static Future<void> processCompanionDoseCheck(String payload) async {
    print("[CompanionMedicationTracker] processCompanionDoseCheck called with payload=$payload");
    if (!payload.startsWith("companion_check_")) {
      print("[CompanionMedicationTracker] Invalid payload for companion dose check: $payload");
      debugPrint("Invalid payload for companion dose check: $payload");
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      print("[CompanionMedicationTracker] No authenticated user found. Cannot process companion dose check.");
      debugPrint("No authenticated user found. Cannot process companion dose check.");
      return;
    }

    final medicationId = payload.replaceFirst("companion_check_", "");
    print("[CompanionMedicationTracker] Processing companion dose check for medication ID: $medicationId");

    try {
      final checksQuery = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('companion_dose_checks')
          .where('medicationId', isEqualTo: medicationId)
          .where('processed', isEqualTo: false)
          .get();

      print("[CompanionMedicationTracker] Found ${checksQuery.docs.length} unprocessed companion dose checks for medication ID: $medicationId");

      for (final doc in checksQuery.docs) {
        final data = doc.data();
        final companionId = data['companionId'] as String?;
        final companionName = data['companionName'] as String?;
        final medicationName = data['medicationName'] as String?;
        final scheduledTimeTs = data['scheduledTime'] as Timestamp?;

        print("[CompanionMedicationTracker] Processing doc: $data");

        if (companionId != null && companionName != null &&
            medicationName != null && scheduledTimeTs != null) {

          final scheduledTime = scheduledTimeTs.toDate();
          print("[CompanionMedicationTracker] Checking if $companionName took $medicationName at $scheduledTime");

          final wasTaken = await performCompanionDoseCheck(
            companionId: companionId,
            medicationId: medicationId,
            scheduledTime: scheduledTime,
          );

          if (!wasTaken) {
            print("[CompanionMedicationTracker] $companionName did not take $medicationName.");
          } else {
            print("[CompanionMedicationTracker] $companionName has taken the medication.");
          }

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
      debugPrint("Error processing companion dose check: $e");
    }
  }

  /// Run a background check for all pending companion doses
  static Future<void> runPendingChecks() async {
    print("[CompanionMedicationTracker] runPendingChecks called");
    final user = _auth.currentUser;
    if (user == null) {
      print("[CompanionMedicationTracker] No authenticated user found.");
      return;
    }

    try {
      debugPrint("Running pending companion dose checks");
      final now = DateTime.now();
      final checkTime = Timestamp.fromDate(now);

      final pendingChecksQuery = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('companion_dose_checks')
          .where('processed', isEqualTo: false)
          .where('scheduledTime', isLessThan: checkTime)
          .get();

      print("[CompanionMedicationTracker] Found ${pendingChecksQuery.docs.length} pending checks to process");

      for (final doc in pendingChecksQuery.docs) {
        final data = doc.data();
        print("[CompanionMedicationTracker] Processing pending check: $data");
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
            print("[CompanionMedicationTracker] Sending missed dose notification for $companionName, $medicationName at $scheduledTime");
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
      debugPrint("Error running pending companion dose checks: $e");
    }
  }

  /// Generate a unique ID for companion check notifications
  static int generateCompanionCheckId(String companionId, String medicationId, DateTime time) {
    print("[CompanionMedicationTracker] generateCompanionCheckId called with companionId=$companionId, medicationId=$medicationId, time=$time");
    final timeHash = time.millisecondsSinceEpoch ~/ 60000;
    final combHash = '${companionId}_${medicationId}_$timeHash'.hashCode;
    final result = 0x3C000000 + (combHash & 0x0FFFFFFF);
    print("[CompanionMedicationTracker] Generated checkId: $result");
    return result;
  }

  /// Format a time for display in notifications
  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'مساءً' : 'صباحاً';
    final formatted = '$hour:$minute $period';
    print("[CompanionMedicationTracker] _formatTimeOfDay: $formatted");
    return formatted;
  }

  /// Fetch all companion medications and schedule notifications for their upcoming doses (today only)
  static Future<void> fetchAndScheduleCompanionMedications() async {
    print("[CompanionMedicationTracker] fetchAndScheduleCompanionMedications called");
    final user = _auth.currentUser;
    if (user == null) {
      print("[CompanionMedicationTracker] No authenticated user found. Cannot fetch companion medications.");
      debugPrint("No authenticated user found. Cannot fetch companion medications.");
      return;
    }

    try {
      final List<CompanionMedicationData> newCompanionData = [];
      final companionsSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('companions')
          .get();

      print("[CompanionMedicationTracker] Found ${companionsSnapshot.docs.length} companions.");

      final tz.Location local = tz.local;
      final now = tz.TZDateTime.now(local);
      final todayStart = tz.TZDateTime(local, now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      for (final companionDoc in companionsSnapshot.docs) {
        final companionData = companionDoc.data();
        final companionName = companionData['name'] ?? '';
        final companionEmail = companionData['email'] ?? '';
        print("[CompanionMedicationTracker] Processing companion: ${companionDoc.id}, name: $companionName, email: $companionEmail");

        String? companionUserId;
        if (companionEmail is String && companionEmail.isNotEmpty) {
          final query = await _firestore
              .collection('users')
              .where('email', isEqualTo: companionEmail)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            companionUserId = query.docs.first.id;
            print("[CompanionMedicationTracker] Found companion userId by email: $companionUserId");
          } else {
            print("[CompanionMedicationTracker] No user found for companion email: $companionEmail");
            continue;
          }
        } else {
          print("[CompanionMedicationTracker] Companion email missing or invalid.");
          continue;
        }

        final medsSnapshot = await _firestore
            .collection('users')
            .doc(companionUserId)
            .collection('medicines')
            .get();

        print("[CompanionMedicationTracker] Found ${medsSnapshot.docs.length} medicines for companion $companionUserId");

        // Store medications for this companion
        final List<MedicationData> medications = [];

        for (final medDoc in medsSnapshot.docs) {
          final medData = medDoc.data();
          final medicationId = medDoc.id;
          final medicationName = medData['name'] ?? '';
          final timesRaw = medData['times'] ?? [];
          final frequencyType = medData['frequencyType'] ?? 'يومي';
          final startTimestamp = medData['startDate'] as Timestamp?;
          final endTimestamp = medData['endDate'] as Timestamp?;

          print("[CompanionMedicationTracker] Processing medication: $medicationId, name: $medicationName, frequencyType: $frequencyType");

          if (startTimestamp == null) {
            print("[CompanionMedicationTracker] Skipping medication $medicationId: startTimestamp is null");
            continue;
          }

          final startDate = startTimestamp.toDate();
          final endDate = endTimestamp?.toDate();

          // Add medication to the list
          medications.add(MedicationData(
            id: medicationId,
            name: medicationName,
            frequencyType: frequencyType,
            times: List.from(timesRaw), // Create a copy to ensure consistency
            startDate: startDate,
            endDate: endDate,
          ));
        }

        // Add companion with medications to our data list
        newCompanionData.add(CompanionMedicationData(
          companionId: companionUserId!,
          companionName: companionName,
          medications: medications,
        ));
      }

      // Compare with last fetched data
      bool hasChanges = true;
      if (_lastFetchedCompanionData != null) {
        // Simple comparison based on length first
        if (_lastFetchedCompanionData!.length == newCompanionData.length) {
          // Deeper comparison using our equality operators
          hasChanges = false;
          for (int i = 0; i < newCompanionData.length; i++) {
            bool foundMatch = false;
            for (int j = 0; j < _lastFetchedCompanionData!.length; j++) {
              if (newCompanionData[i].companionId == _lastFetchedCompanionData![j].companionId) {
                foundMatch = true;
                if (newCompanionData[i] != _lastFetchedCompanionData![j]) {
                  hasChanges = true;
                  break;
                }
              }
            }
            if (!foundMatch || hasChanges) {
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

      // Save the new data for next comparison
      _lastFetchedCompanionData = newCompanionData;

      // Schedule notifications for updated data
      await _scheduleCompanionNotifications(newCompanionData, now, todayStart, todayEnd);

      print("[CompanionMedicationTracker] Companion medications for today fetched and notifications scheduled.");
      debugPrint("Companion medications for today fetched and notifications scheduled.");
    } catch (e) {
      print("[CompanionMedicationTracker] Error fetching/scheduling companion medications: $e");
      debugPrint("Error fetching/scheduling companion medications: $e");
    }
  }

  static Future<void> _scheduleCompanionNotifications(
    List<CompanionMedicationData> companionData,
    tz.TZDateTime now,
    tz.TZDateTime todayStart,
    tz.TZDateTime todayEnd
  ) async {
    final tz.Location local = tz.local;

    // Cancel existing companion notifications if needed
    // This is optional but helps ensure we don't have duplicates
    try {
      final pendingNotifications = await AlarmNotificationHelper.getPendingNotifications();
      for (final notification in pendingNotifications) {
        if (notification.payload?.startsWith('companion_') ?? false) {
          await AlarmNotificationHelper.cancelNotification(notification.id);
        }
      }
    } catch (e) {
      print("[CompanionMedicationTracker] Error canceling existing notifications: $e");
    }

    // Schedule new notifications
    for (final companion in companionData) {
      for (final medication in companion.medications) {
        // Skip medications that are outside the valid date range
        if (now.isBefore(tz.TZDateTime.from(medication.startDate, local)) || 
            (medication.endDate != null && now.isAfter(tz.TZDateTime.from(medication.endDate!, local)))) {
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
                if (day == now.weekday) parsedTimes.add(parsed);
              }
            }
          }
        }

        for (final tod in parsedTimes) {
          final doseTime = tz.TZDateTime(local, now.year, now.month, now.day, tod.hour, tod.minute);
          print("[CompanionMedicationTracker] Considering doseTime: $doseTime (current time: $now)");
          
          // Check if the dose is for today and *strictly* in the future
          if (doseTime.isAfter(now) && doseTime.isBefore(todayEnd)) {
            final notificationId = AlarmNotificationHelper.generateNotificationId(medication.id, doseTime.toUtc());
            print("[CompanionMedicationTracker] Dose time $doseTime is valid for scheduling (ID: $notificationId)");
            
            try {
              await AlarmNotificationHelper.scheduleAlarmNotification(
                id: notificationId,
                title: "💊 تذكير جرعة مرافق",
                body: "حان موعد جرعة ${medication.name} للمرافق ${companion.companionName}.",
                scheduledTime: doseTime.toLocal(), // Pass local DateTime
                medicationId: medication.id,
                isCompanionCheck: true,
              );
              print("[CompanionMedicationTracker] Successfully requested scheduling for companion dose ID $notificationId");
            } catch (e) {
              print("[CompanionMedicationTracker] ERROR requesting scheduling for companion notification ID $notificationId: $e");
            }
          } else {
            if (doseTime.isBefore(now)) {
              print("[CompanionMedicationTracker] Skipping doseTime $doseTime - it's in the past.");
            } else if (!doseTime.isBefore(todayEnd)) {
              print("[CompanionMedicationTracker] Skipping doseTime $doseTime - it's after today's end.");
            } else {
              print("[CompanionMedicationTracker] Skipping doseTime $doseTime - unknown reason (should be future and before todayEnd).");
            }
          }
        }
      }
    }
  }

  static TimeOfDay? _parseTime(String timeStr) {
    print("[CompanionMedicationTracker] _parseTime called with timeStr=$timeStr");
    try {
      // Handle Arabic AM/PM
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

        // Apply AM/PM logic
        if (isPM && hour < 12) hour += 12;
        if (isAM && hour == 12) hour = 0;

        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          final result = TimeOfDay(hour: hour, minute: minute);
          print("[CompanionMedicationTracker] _parseTime result: $result");
          return result;
        }
      }
    } catch (e) {
      print("[CompanionMedicationTracker] _parseTime error: $e");
    }
    return null;
  }
}

