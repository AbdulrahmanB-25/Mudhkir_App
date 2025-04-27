import 'package:flutter/material.dart';
import '../Pages/EditMedication_Page.dart';
import '../services/AlarmNotificationHelper.dart';

class CompanionMedicationsEditPage extends StatelessWidget {
  final String companionId;
  final String medicationId;
  final String companionName;

  const CompanionMedicationsEditPage({
    Key? key,
    required this.companionId,
    required this.medicationId,
    required this.companionName,
  }) : super(key: key);

  Future<void> _rescheduleNotifications(BuildContext context) async {
    try {
      await AlarmNotificationHelper.cancelAllNotifications();
      await AlarmNotificationHelper.scheduleAlarmNotification(
        id: AlarmNotificationHelper.generateNotificationId(medicationId, DateTime.now()),
        title: "💊 تذكير بجرعة دواء",
        body: "تم تحديث الدواء. تأكد من الجرعات الجديدة.",
        scheduledTime: DateTime.now().add(const Duration(seconds: 5)), // Example time
        medicationId: medicationId,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("تم إعادة جدولة الإشعارات بنجاح"),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("حدث خطأ أثناء إعادة جدولة الإشعارات: $e"),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return EditMedicationScreen(
      docId: medicationId,
      companionId: companionId,
      onSave: () => _rescheduleNotifications(context), // Call reschedule logic after saving
    );
  }
}
