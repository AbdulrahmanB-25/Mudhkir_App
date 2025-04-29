import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'time_utilities.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

class MedicationDetailUIComponents {
  // Callbacks for state management and actions
  final Function updateState;
  final Function(bool) handleConfirmation;
  final Function() handleReschedule;
  final Function() showCustomTimePickerDialog;
  final Function() showManualTimePickerDialog;

  // Add these new callbacks
  final Function() setReschedulingModeTrue;
  final Function() setReschedulingModeFalse;
  final Function(TimeOfDay) selectSuggestedTime;

  MedicationDetailUIComponents({
    required this.updateState,
    required this.handleConfirmation,
    required this.handleReschedule,
    required this.showCustomTimePickerDialog,
    required this.showManualTimePickerDialog,
    required this.setReschedulingModeTrue,
    required this.setReschedulingModeFalse,
    required this.selectSuggestedTime,
  });

  // Error view when loading fails
  Widget buildErrorView(String errorMessage, Function retryAction) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(kSpacing * 2),
        margin: const EdgeInsets.all(kSpacing),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(kBorderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kErrorColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: kErrorColor,
                size: 48,
              ),
            ),
            SizedBox(height: kSpacing),
            Text(
              errorMessage,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 16,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: kSpacing * 1.5),
            ElevatedButton.icon(
              onPressed: () => retryAction(),
              icon: Icon(Icons.refresh),
              label: Text("حاول مجدداً"),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kBorderRadius / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Main action section with confirmation buttons
  Widget buildActionSection(Map<String, dynamic> medData,
      TimeOfDay? manualConfirmationTime,
      bool isProcessingConfirmation,) {
    final medName = medData['name'] ?? 'هذا الدواء';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: kPrimaryColor,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(kBorderRadius - 1),
              ),
            ),
            child: Center(
              child: Text(
                "الإجراءات",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(kSpacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.medication_liquid,
                        color: kPrimaryColor,
                        size: 30,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          if (manualConfirmationTime != null)
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_outlined,
                                  size: 14,
                                  color: kSecondaryColor,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  manualConfirmationTime != null
                                      ? TimeUtilities.formatTimeOfDay(
                                      manualConfirmationTime)
                                      : "الوقت الحالي",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                SizedBox(width: 8),
                                InkWell(
                                  onTap: showManualTimePickerDialog,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        vertical: 4, horizontal: 8),
                                    child: Text(
                                      "تغيير",
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: kSecondaryColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 20),

                // Confirmation button with improved feedback
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: isProcessingConfirmation
                            ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                        )
                            : Icon(Icons.check_circle),
                        label: Text(isProcessingConfirmation
                            ? "جاري التأكيد..."
                            : "تأكيد تناول الدواء"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shadowColor: Colors.green.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              kBorderRadius / 2,),
                          ),
                        ),
                        onPressed: isProcessingConfirmation ? null : () =>
                            handleConfirmation(true),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 10),

                // Secondary actions
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.schedule),
                        label: Text("إعادة جدولة الجرعة"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSecondaryColor,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shadowColor: kSecondaryColor.withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              kBorderRadius / 2,),
                          ),
                        ),
                        onPressed: isProcessingConfirmation ? null : () {
                          updateState(() {
                            // Replace with the new callback
                            setReschedulingModeTrue();
                          });
                        },
                      ),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.not_interested),
                        label: Text("تخطي الجرعة"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kErrorColor,
                          side: BorderSide(color: kErrorColor),
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              kBorderRadius / 2,),
                          ),
                        ),
                        onPressed: isProcessingConfirmation ? null : () =>
                            handleConfirmation(false),
                      ),
                    ),
                  ],
                ),

                // Show progress indicator when processing
                if (isProcessingConfirmation)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              kPrimaryColor),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Confirmation section for notification-driven confirmations
  Widget buildEnhancedConfirmationSection(Map<String, dynamic> medData,
      String timeFormatted,
      bool isProcessingConfirmation,) {
    final medName = medData['name'] ?? 'هذا الدواء';
    final dosage = medData['dosage'] ?? '';
    final dosageUnit = medData['dosageUnit'] ?? '';

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: kSpacing * 1.5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: kPrimaryColor,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(kBorderRadius - 1),
              ),
            ),
            child: Center(
              child: Text(
                "تأكيد تناول الجرعة",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(kSpacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Medication info row
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.medication_liquid,
                        color: kPrimaryColor,
                        size: 30,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          if (dosage.isNotEmpty)
                            Text(
                              "$dosage $dosageUnit",
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 16),

                // Time information
                if (timeFormatted.isNotEmpty && timeFormatted != "وقت غير صالح")
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                    decoration: BoxDecoration(
                      color: kSecondaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: kSecondaryColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_rounded, color: kSecondaryColor),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "موعد الجرعة",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                timeFormatted,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                SizedBox(height: 24),

                // Action buttons with improved feedback
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: isProcessingConfirmation
                            ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                        )
                            : Icon(Icons.check_circle_outline),
                        label: Text(isProcessingConfirmation
                            ? "جاري التأكيد..."
                            : "تم تناول الجرعة"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: Colors.green.shade300,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              kBorderRadius / 2,),
                          ),
                        ),
                        onPressed: isProcessingConfirmation ? null : () =>
                            handleConfirmation(true),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 10),

                // Secondary actions
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        icon: Icon(Icons.schedule, size: 18),
                        label: Text("إعادة جدولة الجرعة"),
                        style: TextButton.styleFrom(
                          foregroundColor: kSecondaryColor,
                          padding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: isProcessingConfirmation ? null : () {
                          updateState(() {
                            // Replace with the new callback
                            setReschedulingModeTrue();
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        icon: Icon(Icons.not_interested_outlined, size: 18),
                        label: Text("لم أتناول الجرعة"),
                        style: TextButton.styleFrom(
                          foregroundColor: kErrorColor,
                          padding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: isProcessingConfirmation ? null : () =>
                            handleConfirmation(false),
                      ),
                    ),
                  ],
                ),

                // Show progress indicator when processing
                if (isProcessingConfirmation)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              kPrimaryColor),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Rescheduling section for time selection
  Widget buildReschedulingSection(List<TimeOfDay> suggestedTimes,
      TimeOfDay? selectedSuggestedTime,
      TimeOfDay? customSelectedTime,
      bool isProcessingConfirmation,
      TextEditingController customTimeController,) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: kSecondaryColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: kSecondaryColor,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(kBorderRadius - 1),
              ),
            ),
            child: Center(
              child: Text(
                "إعادة جدولة الجرعة",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(kSpacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Smart scheduling info
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(kBorderRadius / 2),
                    border: Border.all(color: kSecondaryColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb,
                        color: Colors.amber.shade600,
                        size: 24,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "النظام الذكي اقترح أوقاتًا مناسبة لجدولة جرعتك بناءً على جدولك الدوائي الحالي.",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 20),

                Text(
                  "الأوقات المقترحة",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),

                SizedBox(height: 12),

                // Suggested times row
                Row(
                  children: suggestedTimes.map((time) {
                    final isSelected = selectedSuggestedTime == time;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: isProcessingConfirmation ? null : () {
                            updateState(() {
                              selectSuggestedTime(time);
                            });
                          },
                          borderRadius: BorderRadius.circular(
                            kBorderRadius / 2,),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? kPrimaryColor : kPrimaryColor
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(
                                kBorderRadius / 2,),
                              border: Border.all(
                                color: isSelected
                                    ? kPrimaryColor
                                    : kPrimaryColor.withOpacity(0.3),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  TimeUtilities.formatTimeOfDay(time),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : kPrimaryColor,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                SizedBox(height: 24),

                // Custom time section
                Text(
                  "أو حدد وقتًا مخصصًا",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),

                SizedBox(height: 12),

                // Custom time picker field
                InkWell(
                  onTap: isProcessingConfirmation
                      ? null
                      : showCustomTimePickerDialog,
                  borderRadius: BorderRadius.circular(kBorderRadius / 2),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: customSelectedTime != null
                          ? kSecondaryColor.withOpacity(0.1)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(kBorderRadius / 2),
                      border: Border.all(
                        color: customSelectedTime != null
                            ? kSecondaryColor
                            : Colors.grey.shade300,
                        width: customSelectedTime != null ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          color: customSelectedTime != null
                              ? kSecondaryColor
                              : Colors.grey.shade500,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            customSelectedTime != null
                                ? TimeUtilities.formatTimeOfDay(
                                customSelectedTime)
                                : "اضغط لتحديد وقت مخصص",
                            style: TextStyle(
                              fontSize: 15,
                              color: customSelectedTime != null
                                  ? Colors.black87
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: customSelectedTime != null
                              ? kSecondaryColor
                              : Colors.grey.shade500,
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        icon: Icon(Icons.arrow_back),
                        label: Text("العودة"),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                        ),
                        onPressed: isProcessingConfirmation ? null : () {
                          updateState(() {
                            // Replace with the new callback
                            setReschedulingModeFalse();
                          });
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: isProcessingConfirmation
                            ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                        )
                            : Icon(Icons.schedule),
                        label: Text(isProcessingConfirmation
                            ? "جاري الجدولة..."
                            : "إعادة الجدولة"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSecondaryColor,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: kSecondaryColor.withOpacity(0.4),
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              kBorderRadius / 2,),
                          ),
                        ),
                        onPressed: (selectedSuggestedTime != null ||
                            customSelectedTime != null) &&
                            !isProcessingConfirmation
                            ? handleReschedule
                            : null,
                      ),
                    ),
                  ],
                ),

                // Show progress indicator when processing
                if (isProcessingConfirmation)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              kSecondaryColor),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildMedicationInfoCard(Map<String, dynamic> medData) {
    final imageUrl = medData['imageUrl'] as String?;
    final medName = medData['name'] ?? 'دواء غير مسمى';
    final dosage = medData['dosage'] ?? 'غير محدد';
    final dosageUnit = medData['dosageUnit'] ?? '';
    final instructions = medData['instructions'] ?? 'لا توجد تعليمات.';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: kPrimaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(kBorderRadius),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.medication, color: kPrimaryColor),
                SizedBox(width: 10),
                Text(
                  "معلومات الدواء",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(kSpacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Optional Image
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: kSpacing),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(kBorderRadius / 2),
                        child: Image.network(
                          imageUrl,
                          height: 150,
                          width: 150,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(
                                height: 150,
                                width: 150,
                                color: Colors.grey.shade200,
                                child: Icon(
                                  Icons.medication_liquid_outlined,
                                  size: 50,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                          loadingBuilder: (_, child, loadingProgress) =>
                          loadingProgress == null
                              ? child
                              : Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                Center(
                  child: Text(
                    medName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                SizedBox(height: kSpacing),

                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kPrimaryColor.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.medical_services_outlined,
                        color: kPrimaryColor,
                      ),
                      SizedBox(width: 10),
                      Text(
                        "الجرعة:",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        "$dosage $dosageUnit",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                if (instructions.isNotEmpty &&
                    instructions != 'لا توجد تعليمات.') ...[
                  SizedBox(height: 16),
                  Text(
                    "تعليمات:",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      instructions,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildScheduleInfoCard(Map<String, dynamic> medData) {
    final startDate = (medData['startDate'] as Timestamp?)?.toDate();
    final endDate = (medData['endDate'] as Timestamp?)?.toDate();
    final days = (medData['days'] as List<dynamic>?) ?? [];
    final timeSlots = (medData['timeSlots'] as List<dynamic>?) ?? [];
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: kSecondaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(kBorderRadius),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_month, color: kSecondaryColor),
                SizedBox(width: 10),
                Text(
                  "جدول الجرعات",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(kSpacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date range
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kSecondaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kSecondaryColor.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "تاريخ البدء:",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            TimeUtilities.formatDate(startDate),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: kPrimaryColor,
                            ),
                          ),
                        ],
                      ),
                      Icon(
                        Icons.arrow_forward,
                        color: kSecondaryColor,
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "تاريخ الانتهاء:",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            TimeUtilities.formatDate(endDate),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: kPrimaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: kSpacing),

                // Days of week
                if (days.isNotEmpty) ...[
                  Text(
                    "أيام الأسبوع:",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 8),
                  _buildDaysOfWeekRow(days),
                  SizedBox(height: kSpacing),
                ],

                // Time slots
                if (timeSlots.isNotEmpty) ...[
                  Text(
                    "أوقات الجرعات:",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: 8),
                  _buildTimeSlotsGrid(timeSlots),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysOfWeekRow(List<dynamic> days) {
    final dayNames = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
    final dayIndices = days.map((day) => day is int ? day : int.tryParse(day.toString()) ?? 0).toList();
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(7, (index) {
        final isSelected = dayIndices.contains(index);
        return Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? kPrimaryColor : Colors.transparent,
            border: Border.all(
              color: isSelected ? kPrimaryColor : Colors.grey.shade300,
              width: isSelected ? 0 : 1,
            ),
          ),
          child: Center(
            child: Text(
              dayNames[index].substring(0, 1),
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTimeSlotsGrid(List<dynamic> timeSlots) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: timeSlots.map<Widget>((slot) {
        String timeText = "غير محدد";
        if (slot is Map && slot.containsKey('hour') && slot.containsKey('minute')) {
          final hour = int.tryParse(slot['hour'].toString()) ?? 0;
          final minute = int.tryParse(slot['minute'].toString()) ?? 0;
          timeText = TimeUtilities.formatTimeOfDay(TimeOfDay(hour: hour, minute: minute));
        }
        
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kSecondaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(kBorderRadius / 2),
            border: Border.all(color: kSecondaryColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 16,
                color: kSecondaryColor,
              ),
              SizedBox(width: 4),
              Text(
                timeText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: kSecondaryColor,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

