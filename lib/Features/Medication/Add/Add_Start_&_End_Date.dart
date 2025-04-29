import 'package:flutter/material.dart';


const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

class AddStartEndDatePage extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback onSelectStartDate;
  final VoidCallback onSelectEndDate;
  final VoidCallback onSubmit;
  final VoidCallback onBack;
  final VoidCallback? onClearEndDate;
  final String? submitButtonText;

  const AddStartEndDatePage({
    Key? key,
    required this.formKey,
    required this.startDate,
    required this.endDate,
    required this.onSelectStartDate,
    required this.onSelectEndDate,
    required this.onSubmit,
    required this.onBack,
    this.onClearEndDate,
    this.submitButtonText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0;

    return Form(
      key: formKey,
      child: Container(
        decoration: const BoxDecoration(
          color: kBackgroundColor,
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            // Wrap the Column with SingleChildScrollView
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [kPrimaryColor, Color(0xFF4E7BFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        "تاريخ البدء والانتهاء",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: screenWidth * 0.07,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      "حدد متى تبدأ ومتى تنتهي من تناول الدواء",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.normal,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),

                  const SizedBox(height: 25.0),

                  // Card with date selection
                  Container(
                    padding: const EdgeInsets.all(20),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_month, color: kPrimaryColor),
                            const SizedBox(width: 10),
                            Text(
                              "جدول تناول الدواء",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),

                        const Divider(height: 24),

                        Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kSecondaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(kBorderRadius),
                            border: Border.all(
                              color: kSecondaryColor.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: kSecondaryColor, size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "حدد تاريخ بدء الدواء (إلزامي) وتاريخ الانتهاء (اختياري)",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Start Date Section
                        const Text(
                          "تاريخ البدء",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Start Date Card
                        InkWell(
                          onTap: onSelectStartDate,
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            decoration: BoxDecoration(
                              color: kPrimaryColor.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(kBorderRadius),
                              border: Border.all(
                                color: startDate != null
                                    ? kPrimaryColor.withOpacity(0.5)
                                    : Colors.grey.shade300,
                                width: startDate != null ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: kPrimaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.calendar_today,
                                    color: kPrimaryColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        startDate == null
                                            ? "اختر تاريخ البدء"
                                            : "${startDate!.day}/${startDate!.month}/${startDate!.year}",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                          color: startDate == null
                                              ? Colors.grey.shade600
                                              : Colors.black87,
                                        ),
                                      ),
                                      if (startDate != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            "تاريخ بدء تناول الدواء",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.edit_calendar,
                                  color: startDate != null
                                      ? kPrimaryColor
                                      : Colors.grey.shade400,
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Start Date validation message
                        FormField<DateTime>(
                          initialValue: startDate,
                          validator: (value) {
                            if (value == null) {
                              return 'تاريخ البدء مطلوب';
                            }
                            return null;
                          },
                          builder: (FormFieldState<DateTime> state) {
                            if (state.hasError) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0, right: 12.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: kErrorColor, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      state.errorText ?? '',
                                      style: TextStyle(
                                        color: kErrorColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),

                        const SizedBox(height: 20),

                        // End Date Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "تاريخ الانتهاء",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Text(
                                "اختياري",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        InkWell(
                          onTap: onSelectEndDate,
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            decoration: BoxDecoration(
                              color: endDate != null
                                  ? const Color(0xFFFFF3E0).withOpacity(0.5)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(kBorderRadius),
                              border: Border.all(
                                color: endDate != null
                                    ? Colors.orange.shade300
                                    : Colors.grey.shade300,
                                width: endDate != null ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: endDate != null
                                        ? Colors.orange.shade100
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.event_busy,
                                    color: endDate != null
                                        ? Colors.orange.shade700
                                        : Colors.grey.shade500,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        endDate == null
                                            ? "اختر تاريخ الانتهاء"
                                            : "${endDate!.day}/${endDate!.month}/${endDate!.year}",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                          color: endDate == null
                                              ? Colors.grey.shade600
                                              : Colors.black87,
                                        ),
                                      ),
                                      if (endDate != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            "تاريخ انتهاء تناول الدواء",
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.edit_calendar,
                                  color: endDate != null
                                      ? Colors.orange.shade700
                                      : Colors.grey.shade400,
                                ),
                                if (endDate != null && onClearEndDate != null)
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.red),
                                    onPressed: onClearEndDate,
                                  ),
                              ],
                            ),
                          ),
                        ),

                        // End Date validation message
                        FormField<DateTime>(
                          validator: (value) {
                            if (endDate != null && startDate != null && endDate!.isBefore(startDate!)) {
                              return 'تاريخ الانتهاء يجب أن يكون بعد تاريخ البدء';
                            }
                            return null;
                          },
                          builder: (FormFieldState<DateTime> state) {
                            if (state.hasError) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0, right: 12.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: kErrorColor, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      state.errorText ?? '',
                                      style: TextStyle(
                                        color: kErrorColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Date range preview card if both dates are set
                  if (startDate != null && endDate != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                        border: Border.all(color: kSecondaryColor.withOpacity(0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.date_range, color: kSecondaryColor),
                              const SizedBox(width: 8),
                              Text(
                                "ملخص فترة العلاج",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildDateChip(startDate!, "البداية", kPrimaryColor),
                              _buildDateArrow(),
                              _buildDateChip(endDate!, "النهاية", Colors.orange.shade700),
                            ],
                          ),

                          const SizedBox(height: 16),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: kPrimaryColor.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(kBorderRadius / 2),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.access_time, color: kPrimaryColor),
                                const SizedBox(width: 8),
                                Text(
                                  "مدة العلاج: ${_calculateDuration(startDate!, endDate!)} يوم",
                                  style: const TextStyle(
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

                  const SizedBox(height: 30),

                  ElevatedButton(
                    onPressed: () {
                      if (formKey.currentState!.validate()) {
                        onSubmit();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 55),
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: Colors.green.shade300.withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          submitButtonText ?? 'إضافة الدواء إلى خزانتي',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to create date chips for the summary
  Widget _buildDateChip(DateTime date, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "${date.day}/${date.month}/${date.year}",
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to create an arrow between date chips
  Widget _buildDateArrow() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: 50,
      height: 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryColor, Colors.orange.shade700],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: kPrimaryColor.withOpacity(0.5),
                width: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to calculate duration in days
  int _calculateDuration(DateTime start, DateTime end) {
    return end.difference(start).inDays + 1; // Include the end day
  }
}
