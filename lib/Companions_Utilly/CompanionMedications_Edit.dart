import 'package:flutter/material.dart';
import '../Pages/EditMedication_Page.dart';

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

  @override
  Widget build(BuildContext context) {
    return EditMedicationScreen(
      docId: medicationId,
      companionId: companionId,
    );
  }
}
