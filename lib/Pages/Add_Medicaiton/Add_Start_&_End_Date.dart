import 'package:flutter/material.dart';

class AddStartEndDatePage extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback onSelectStartDate;
  final VoidCallback onSelectEndDate;
  final VoidCallback onSubmit; // Changed from onNext to onSubmit
  final VoidCallback onBack;

  const AddStartEndDatePage({
    Key? key,
    required this.formKey,
    required this.startDate,
    required this.endDate,
    required this.onSelectStartDate,
    required this.onSelectEndDate,
    required this.onSubmit, // Use onSubmit
    required this.onBack,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0;

    return Form(
      key: formKey, // Use passed key
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        child: Stack(
          children: [
            Positioned(
              top: 15,
              left: -10,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue.shade800, size: 28),
                onPressed: onBack, // Use callback
              ),
            ),
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 50),
                    Text(
                      "تاريخ البدء والانتهاء",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: screenWidth * 0.07,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 35.0),
                    // --- Start Date Picker ---
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      elevation: 1.0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: Icon(Icons.calendar_month, color: Colors.blue.shade700),
                        title: Text(
                          startDate == null // Use passed value
                              ? 'اختر تاريخ البدء (إلزامي)'
                              : "تاريخ البدء: ${startDate!.day}/${startDate!.month}/${startDate!.year}",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: startDate == null ? Colors.grey.shade600 : Colors.black87,
                          ),
                        ),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: onSelectStartDate, // Use callback
                      ),
                    ),
                    // --- Start Date Validator ---
                    FormField<DateTime>(
                      initialValue: startDate, // Use passed value
                      validator: (value) {
                        if (value == null) {
                          return 'تاريخ البدء مطلوب';
                        }
                        return null;
                      },
                      builder: (FormFieldState<DateTime> state) {
                        // Display error message if validation fails
                        return state.hasError
                            ? Padding(
                          padding: const EdgeInsets.only(top: 5.0),
                          child: Text(
                            state.errorText ?? '',
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        )
                            : Container(); // Return empty container if valid
                      },
                    ),
                    const SizedBox(height: 15.0),
                    // --- End Date Picker ---
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      elevation: 1.0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: Icon(Icons.event_busy, color: Colors.orange.shade700),
                        title: Text(
                          endDate == null // Use passed value
                              ? 'اختر تاريخ الانتهاء (اختياري)'
                              : "تاريخ الانتهاء: ${endDate!.day}/${endDate!.month}/${endDate!.year}",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: endDate == null ? Colors.grey.shade600 : Colors.black87,
                          ),
                        ),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: onSelectEndDate, // Use callback
                      ),
                    ),
                    // --- End Date Validator ---
                    FormField<DateTime>(
                      // No initial value needed here as it's optional, but validator uses it
                      validator: (value) {
                        // The 'value' passed to the validator is actually the initialValue
                        // of the field if it hasn't changed, or the changed value.
                        // Here, we need to compare the *current* endDate state variable
                        // with the startDate state variable.
                        if (endDate != null && startDate != null && endDate!.isBefore(startDate!)) {
                          return 'تاريخ الانتهاء يجب أن يكون بعد تاريخ البدء';
                        }
                        return null;
                      },
                      builder: (FormFieldState<DateTime> state) {
                        // Display error message if validation fails
                        return state.hasError
                            ? Padding(
                          padding: const EdgeInsets.only(top: 5.0),
                          child: Text(
                            state.errorText ?? '',
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        )
                            : Container(); // Return empty container if valid
                      },
                    ),
                    const SizedBox(height: 40.0),
                    // --- Submit Button ---
                    ElevatedButton(
                      onPressed: () {
                        // Validate using the passed key before calling the callback
                        if (formKey.currentState!.validate()) {
                          onSubmit(); // Use the onSubmit callback
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 55),
                        backgroundColor: Colors.green.shade700, // Submit button color
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      // Changed text to reflect final action
                      child: const Text('إضافة الدواء إلى خزانتي'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}