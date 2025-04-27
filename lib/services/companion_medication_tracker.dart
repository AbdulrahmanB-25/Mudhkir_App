import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'AlarmNotificationHelper.dart';

class CompanionMedicationTracker {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Schedule a check for this medication dose at the given time + 5 minutes
  static Future<void> scheduleCompanionDoseCheck({
    required String companionId,
    required String companionName,
    required String medicationId,
    required String medicationName,
    required DateTime scheduledTime,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Schedule a check 5 minutes after the medication time
      final checkTime = scheduledTime.add(const Duration(minutes: 5));

      // Generate a unique ID for this check notification
      final int checkId = generateCompanionCheckId(companionId, medicationId, scheduledTime);

      debugPrint("Scheduling companion dose check: $medicationName for $companionName at $checkTime (ID: $checkId)");

      // Store this scheduled check in Firestore for tracking
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
        'checkTime': Timestamp.fromDate(checkTime),
        'processed': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Schedule the actual notification using AlarmNotificationHelper
      final payload = "companion_check_$medicationId";
      await AlarmNotificationHelper.scheduleAlarmNotification(
        id: checkId,
        title: "التحقق من دواء المرافق",
        body: "تحقق ما إذا كان $companionName قد تناول جرعة $medicationName",
        scheduledTime: checkTime,
        medicationId: payload,
        isCompanionCheck: true,
      );

      debugPrint("Successfully scheduled companion dose check with ID $checkId");
    } catch (e) {
      debugPrint("Error scheduling companion dose check: $e");
    }
  }

  /// Check if a companion has taken their medication
  static Future<bool> performCompanionDoseCheck({
    required String companionId,
    required String medicationId,
    required DateTime scheduledTime,
  }) async {
    try {
      // Normalize the time to check just hour and minute
      final startOfDay = DateTime(scheduledTime.year, scheduledTime.month, scheduledTime.day);

      // Get medication dose history
      final docRef = _firestore
          .collection('users')
          .doc(companionId)
          .collection('medicines')
          .doc(medicationId);

      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        debugPrint("Medication $medicationId not found for companion $companionId");
        return false;
      }

      final data = docSnapshot.data()!;
      final List<dynamic> missedDoses = data['missedDoses'] ?? [];

      // Check if this dose is marked as taken
      for (final dose in missedDoses) {
        if (dose is Map<String, dynamic>) {
          final scheduled = dose['scheduled'] as Timestamp?;
          final status = dose['status'] as String?;

          if (scheduled != null && status == 'taken') {
            final doseTime = scheduled.toDate();
            final doseDate = DateTime(doseTime.year, doseTime.month, doseTime.day);

            // If the date is the same and the hour and minute match (within 15 minutes tolerance)
            if (doseDate.isAtSameMomentAs(startOfDay) &&
                (doseTime.hour == scheduledTime.hour &&
                    (doseTime.minute - scheduledTime.minute).abs() < 15)) {
              debugPrint("Found confirmation for dose at $scheduledTime, status: taken");
              return true; // Dose was taken
            }
          }
        }
      }

      debugPrint("No confirmation found for dose at $scheduledTime");
      return false; // Dose was not taken
    } catch (e) {
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
    try {
      final formattedTime = _formatTimeOfDay(TimeOfDay.fromDateTime(scheduledTime));

      // Generate a unique ID for this notification
      final int notificationId = DateTime.now().microsecondsSinceEpoch % 100000000;
      final payload = "companion_missed_${notificationId.toString()}";

      debugPrint("Sending companion missed dose notification: $companionName missed $medicationName at $formattedTime");

      await AlarmNotificationHelper.scheduleAlarmNotification(
        id: notificationId,
        title: "تنبيه: $companionName لم يتناول الدواء",
        body: "يبدو أن $companionName لم يتناول $medicationName المُجدول في $formattedTime. تحقق من حالتهم.",
        scheduledTime: DateTime.now().add(const Duration(seconds: 2)),
        medicationId: payload,
      );

      debugPrint("Successfully sent companion missed dose notification");
    } catch (e) {
      debugPrint("Error sending companion missed dose notification: $e");
    }
  }

  /// Process background notification to check companion doses
  static Future<void> processCompanionDoseCheck(String payload) async {
    if (!payload.startsWith("companion_check_")) return;

    final user = _auth.currentUser;
    if (user == null) {
      debugPrint("No authenticated user to process companion dose check");
      return;
    }

    final medicationId = payload.replaceFirst("companion_check_", "");
    debugPrint("Processing companion dose check for medication ID: $medicationId");

    try {
      // Get all scheduled checks
      final checksQuery = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('companion_dose_checks')
          .where('medicationId', isEqualTo: medicationId)
          .where('processed', isEqualTo: false)
          .get();

      debugPrint("Found ${checksQuery.docs.length} unprocessed companion dose checks");

      for (final doc in checksQuery.docs) {
        final data = doc.data();
        final companionId = data['companionId'] as String?;
        final companionName = data['companionName'] as String?;
        final medicationName = data['medicationName'] as String?;
        final scheduledTimeTs = data['scheduledTime'] as Timestamp?;

        if (companionId != null && companionName != null &&
            medicationName != null && scheduledTimeTs != null) {

          final scheduledTime = scheduledTimeTs.toDate();
          debugPrint("Checking if $companionName took $medicationName at $scheduledTime");

          // Check if the companion took the dose
          final wasTaken = await performCompanionDoseCheck(
            companionId: companionId,
            medicationId: medicationId,
            scheduledTime: scheduledTime,
          );

          // If not taken, send a notification to the user
          if (!wasTaken) {
            debugPrint("$companionName did not take $medicationName, sending notification");
            await sendCompanionMissedDoseNotification(
              companionName: companionName,
              medicationName: medicationName,
              scheduledTime: scheduledTime,
            );
          } else {
            debugPrint("$companionName has taken the medication, no notification needed");
          }

          // Mark this check as processed
          await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('companion_dose_checks')
              .doc(doc.id)
              .update({'processed': true});
        }
      }
    } catch (e) {
      debugPrint("Error processing companion dose check: $e");
    }
  }

  /// Generate a unique ID for companion check notifications
  static int generateCompanionCheckId(String companionId, String medicationId, DateTime time) {
    final timeHash = time.millisecondsSinceEpoch ~/ 60000; // Minutes precision
    final combHash = '${companionId}_${medicationId}_$timeHash'.hashCode;
    return 0x3C000000 + (combHash & 0x0FFFFFFF); // Range 0x3C000000 to 0x3CFFFFFF
  }

  /// Format a time for display in notifications
  static String _formatTimeOfDay(TimeOfDay time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'مساءً' : 'صباحاً';
    return '$hour:$minute $period';
  }

  /// Run a background check for all pending companion doses
  static Future<void> runPendingChecks() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      debugPrint("Running pending companion dose checks");
      final now = DateTime.now();
      final checkTime = Timestamp.fromDate(now);

      // Find all pending checks that should have run by now
      final pendingChecksQuery = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('companion_dose_checks')
          .where('processed', isEqualTo: false)
          .where('checkTime', isLessThan: checkTime)
          .get();

      debugPrint("Found ${pendingChecksQuery.docs.length} pending checks to process");

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

          // Check if the companion took the dose
          final wasTaken = await performCompanionDoseCheck(
            companionId: companionId,
            medicationId: medicationId,
            scheduledTime: scheduledTime,
          );

          // If not taken, send a notification to the user
          if (!wasTaken) {
            await sendCompanionMissedDoseNotification(
              companionName: companionName,
              medicationName: medicationName,
              scheduledTime: scheduledTime,
            );
          }

          // Mark this check as processed
          await doc.reference.update({'processed': true});
        }
      }
    } catch (e) {
      debugPrint("Error running pending companion dose checks: $e");
    }
  }
}
