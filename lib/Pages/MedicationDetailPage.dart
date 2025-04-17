import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
// Import SharedPreferences keys from main.dart (adjust path if needed)
import '../main.dart';

// Assuming constants are defined elsewhere or replace with actual values
const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const double kSpacing = 16.0; // Define spacing if not imported
const double kBorderRadius = 16.0; // Define border radius if not imported

class MedicationDetailPage extends StatefulWidget {
  final String docId;
  final bool openedFromNotification;
  final bool needsConfirmation;
  final String? confirmationTimeIso; // UTC ISO8601 String
  final String? confirmationKey;

  const MedicationDetailPage({
    super.key,
    required this.docId,
    this.openedFromNotification = false,
    this.needsConfirmation = false,
    this.confirmationTimeIso,
    this.confirmationKey,
  });

  @override
  _MedicationDetailPageState createState() => _MedicationDetailPageState();
}

class _MedicationDetailPageState extends State<MedicationDetailPage> {
  Map<String, dynamic>? _medData;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isProcessingConfirmation = false; // To disable buttons during action

  // Store the specific time being confirmed (in local timezone)
  tz.TZDateTime? _confirmationTimeLocal;

  @override
  void initState() {
    super.initState();
    if (widget.needsConfirmation && widget.confirmationTimeIso != null) {
      try {
        // Parse the UTC ISO string and convert it to local TZDateTime
        final utcTime = DateTime.parse(widget.confirmationTimeIso!);
        _confirmationTimeLocal = tz.TZDateTime.from(utcTime, tz.local);
      } catch (e) {
        print("[DetailPage] Error parsing confirmation time ISO '${widget.confirmationTimeIso}': $e");
        _errorMessage = "خطأ في تحديد وقت التأكيد."; // Set error message
      }
    }
    _loadMedicationData();
  }

  Future<void> _loadMedicationData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'مستخدم غير مسجل.';
        });
      }
      return;
    }

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(widget.docId)
          .get();

      if (mounted) {
        if (doc.exists) {
          setState(() {
            _medData = doc.data() as Map<String, dynamic>?;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = 'لم يتم العثور على بيانات الدواء.';
          });
        }
      }
    } catch (e) {
      print("[DetailPage] Error loading medication details for ${widget.docId}: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'خطأ في تحميل البيانات.';
        });
      }
    }
  }

  // --- Confirmation Actions ---

  Future<void> _handleConfirmation(bool taken) async {
    if (!mounted || !widget.needsConfirmation || _isProcessingConfirmation) return;

    setState(() => _isProcessingConfirmation = true); // Disable buttons

    print("[DetailPage Confirmation] User action: ${taken ? 'Confirmed' : 'Skipped'} for key ${widget.confirmationKey}");

    User? user = FirebaseAuth.instance.currentUser;
    // 1. Log the action to Firestore dose_history (optional but recommended)
    if (user != null && _confirmationTimeLocal != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('medicines')
            .doc(widget.docId)
            .collection('dose_history')
            .add({
          'timestamp': Timestamp.now(), // Time action was taken by user
          'scheduledTime': Timestamp.fromDate(_confirmationTimeLocal!.toUtc()), // The intended scheduled time (UTC)
          'status': taken ? 'taken' : 'skipped',
          'confirmedVia': 'app_confirmation_prompt', // Identifier
        });
        print("[DetailPage Confirmation] Logged dose history status: ${taken ? 'taken' : 'skipped'}");
      } catch (e) {
        print("[DetailPage Confirmation] ERROR logging dose history: $e");
        // Continue even if logging fails? Or show error?
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("خطأ في تسجيل حالة الجرعة.", textAlign: TextAlign.right),
              backgroundColor: kErrorColor));
        }
        setState(() => _isProcessingConfirmation = false); // Re-enable buttons on error
        return; // Stop further processing on logging error?
      }
    } else {
      print("[DetailPage Confirmation] Cannot log history: User or confirmation time missing.");
    }

    // 2. Clear the SharedPreferences flag for *this specific dose*
    //    This prevents the confirmation prompt from showing again for the same past dose.
    if (widget.confirmationKey != null && widget.confirmationKey!.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(widget.confirmationKey!);
        print("[DetailPage Confirmation] Removed confirmation flag: ${widget.confirmationKey}");
      } catch (e) {
        print("[DetailPage Confirmation] ERROR removing SharedPreferences key '${widget.confirmationKey}': $e");
        // If removing the key fails, the prompt might reappear, which is problematic.
        // Maybe show a persistent error?
      }
    } else {
      print("[DetailPage Confirmation] Warning: Confirmation key was null or empty, cannot clear flag.");
      // This might indicate a logic error in how the key was passed.
    }

    // 3. Pop the screen and signal that rescheduling is needed (returning true)
    //    The `then` block in `MainPage._checkAndShowConfirmationIfNeeded` will handle rescheduling.
    if (mounted) {
      print("[DetailPage Confirmation] Popping screen with result: true");
      Navigator.pop(context, true); // Pop with 'true' to indicate action was taken
    }
    // No need to set _isProcessingConfirmation = false here as the widget will be disposed.
  }

  // --- Helper Methods ---

  /// Parses a time string into a TimeOfDay object.
  TimeOfDay? _parseTime(String timeStr) {
    try {
      final DateFormat ampmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      String normalizedTime = timeStr.replaceAll('صباحاً', 'AM').replaceAll('مساءً', 'PM').trim();
      final DateFormat arabicAmpmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = arabicAmpmFormat.parseStrict(normalizedTime);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (_) {}
    return null;
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "غير محدد";
    try {
      final date = timestamp.toDate();
      // Use 'ar_SA' locale for Arabic date format
      return DateFormat.yMMMd('ar_SA').format(date);
    } catch (e) {
      print("[DetailPage] Error formatting date: $e");
      return "تاريخ غير صالح";
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    // Copied from MainPage for consistency
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }

  // --- Build Method ---

  @override
  Widget build(BuildContext context) {
    String appBarTitle = "تفاصيل الدواء";
    if (widget.needsConfirmation) {
      appBarTitle = "تأكيد جرعة الدواء";
    } else if (widget.openedFromNotification) {
      appBarTitle = "تذكير بجرعة الدواء";
    }

    // Format confirmation time for display
    String confirmationTimeFormatted = '';
    if (_confirmationTimeLocal != null) {
      try {
        // Example format: "9:30 صباحاً (الخميس)" - Adjust as needed
        confirmationTimeFormatted = DateFormat('h:mm a (EEEE)', 'ar_SA').format(_confirmationTimeLocal!);
      } catch (e) {
        print("[DetailPage] Error formatting confirmation time for display: $e");
        confirmationTimeFormatted = "وقت غير صالح";
      }
    }

    return Scaffold(
      // Use a slightly different AppBar style for confirmation
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: widget.needsConfirmation ? Colors.orange.shade700 : kPrimaryColor,
        elevation: widget.needsConfirmation ? 2 : 0, // Add slight elevation for confirmation
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: kPrimaryColor))
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(kSpacing * 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, color: kErrorColor, size: 60),
                        SizedBox(height: kSpacing),
                        Text(_errorMessage, style: TextStyle(color: kErrorColor, fontSize: 16), textAlign: TextAlign.center),
                        SizedBox(height: kSpacing * 1.5),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text("العودة"),
                          style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
                        )
                      ],
                    ),
                  ))
              : _medData == null
                  ? Center(child: Text('لا توجد بيانات لعرضها.'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(kSpacing),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, // Start aligns right in RTL
                        children: [
                          // --- Confirmation Section (Shown at the top if needed) ---
                          if (widget.needsConfirmation)
                            _buildConfirmationSection(confirmationTimeFormatted),

                          // --- Standard Medication Details ---
                          // Use Cards for better visual separation
                          _buildMedicationInfoCard(),
                          SizedBox(height: kSpacing),
                          _buildScheduleInfoCard(),

                          // Add Edit/Delete buttons only if NOT in confirmation mode
                          if (!widget.needsConfirmation)
                            Padding(
                              padding: const EdgeInsets.only(top: kSpacing * 2),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton.icon(
                                    icon: Icon(Icons.edit_rounded),
                                    label: Text("تعديل"),
                                    onPressed: () {
                                      /* TODO: Implement Edit Navigation */
                                    },
                                    style: ElevatedButton.styleFrom(backgroundColor: kSecondaryColor),
                                  ),
                                  ElevatedButton.icon(
                                    icon: Icon(Icons.delete_forever_rounded),
                                    label: Text("حذف"),
                                    onPressed: () {
                                      /* TODO: Implement Delete Confirmation & Action */
                                    },
                                    style: ElevatedButton.styleFrom(backgroundColor: kErrorColor.withOpacity(0.8)),
                                  ),
                                ],
                              ),
                            ),
                          SizedBox(height: kSpacing), // Bottom padding
                        ],
                      ),
                    ),
    );
  }

  /// Builds the confirmation prompt section.
  Widget _buildConfirmationSection(String timeFormatted) {
    // Extract medication name safely
    final medName = _medData?['name'] ?? 'هذا الدواء';

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: kSpacing * 1.5),
      padding: EdgeInsets.all(kSpacing),
      decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.08), // Use orange theme for confirmation
          borderRadius: BorderRadius.circular(kBorderRadius),
          border: Border.all(color: Colors.orange.withOpacity(0.4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // Align right in RTL
        children: [
          Text(
            "هل تناولت جرعة '$medName'؟",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
          ),
          if (timeFormatted.isNotEmpty && timeFormatted != "وقت غير صالح")
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
              child: Text(
                "المجدولة في: $timeFormatted",
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ),
          if (timeFormatted == "وقت غير صالح") // Show error if time parsing failed
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
              child: Text(
                "خطأ في تحديد الوقت المجدول.",
                style: TextStyle(fontSize: 14, color: kErrorColor),
              ),
            ),
          SizedBox(height: 10),
          Row(
            children: [
              // Skip Button (Right in RTL)
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(Icons.cancel_outlined),
                  label: Text("تخطيت الجرعة"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade700),
                    padding: EdgeInsets.symmetric(vertical: 10),
                  ).copyWith(
                    // Disable button while processing
                    foregroundColor: MaterialStateProperty.resolveWith<Color?>(
                      (Set<MaterialState> states) {
                        if (states.contains(MaterialState.disabled)) return Colors.grey;
                        return Colors.red.shade700;
                      },
                    ),
                    side: MaterialStateProperty.resolveWith<BorderSide?>(
                      (Set<MaterialState> states) {
                        if (states.contains(MaterialState.disabled)) return BorderSide(color: Colors.grey.shade300);
                        return BorderSide(color: Colors.red.shade700);
                      },
                    ),
                  ),
                  // Disable button if processing or if time was invalid
                  onPressed: _isProcessingConfirmation || timeFormatted == "وقت غير صالح"
                      ? null
                      : () => _handleConfirmation(false),
                ),
              ),
              SizedBox(width: kSpacing / 1.5),
              // Confirm Taken Button (Left in RTL)
              Expanded(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.check_circle_outline),
                  label: Text("نعم، تم تناولها"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 10),
                  ).copyWith(
                    // Disable button while processing
                    backgroundColor: MaterialStateProperty.resolveWith<Color?>(
                      (Set<MaterialState> states) {
                        if (states.contains(MaterialState.disabled)) return Colors.grey.shade400;
                        return Colors.green.shade700; // Use the component's default.
                      },
                    ),
                  ),
                  // Disable button if processing or if time was invalid
                  onPressed: _isProcessingConfirmation || timeFormatted == "وقت غير صالح"
                      ? null
                      : () => _handleConfirmation(true),
                ),
              ),
            ],
          ),
          // Show progress indicator only when processing
          if (_isProcessingConfirmation)
            Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
    );
  }

  /// Builds a Card containing basic medication info.
  Widget _buildMedicationInfoCard() {
    final imageUrl = _medData?['imageUrl'] as String?;
    final medName = _medData?['name'] ?? 'دواء غير مسمى';
    final dosage = _medData?['dosage'] ?? 'غير محدد';
    final instructions = _medData?['instructions'] ?? 'لا توجد تعليمات.';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kBorderRadius)),
      child: Padding(
        padding: const EdgeInsets.all(kSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // Align right in RTL
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
                      errorBuilder: (_, __, ___) => Container(
                          height: 150,
                          width: 150,
                          color: Colors.grey.shade200,
                          child: Icon(Icons.medication_liquid_outlined, size: 50, color: Colors.grey.shade400)),
                      loadingBuilder: (_, child, loadingProgress) => loadingProgress == null
                          ? child
                          : Center(
                              child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                      : null)),
                    ),
                  ),
                ),
              ),
            Center( // Center the name
              child: Text(medName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: kPrimaryColor), textAlign: TextAlign.center),
            ),
            SizedBox(height: kSpacing * 1.5),
            _buildDetailItem(Icons.medical_services_outlined, "الجرعة", dosage),
            Divider(height: kSpacing * 1.5),
            _buildDetailItem(Icons.info_outline_rounded, "تعليمات", instructions.isNotEmpty ? instructions : 'لا توجد.'),
          ],
        ),
      ),
    );
  }

  /// Builds a Card containing schedule information.
  Widget _buildScheduleInfoCard() {
    final frequency = _medData?['frequencyType'] ?? 'غير محدد';
    final List<dynamic> times = _medData?['times'] ?? [];
    final startDate = _medData?['startDate'] as Timestamp?;
    final endDate = _medData?['endDate'] as Timestamp?;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kBorderRadius)),
      child: Padding(
        padding: const EdgeInsets.all(kSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // Align right in RTL
          children: [
            Text("الجدول الزمني", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: kSpacing),
            _buildDetailItem(Icons.repeat_rounded, "التكرار", frequency),
            Divider(height: kSpacing * 1.5),
            _buildDetailItem(Icons.play_arrow_rounded, "تاريخ البدء", _formatDate(startDate)),
            SizedBox(height: kSpacing * 0.5),
            _buildDetailItem(Icons.stop_rounded, "تاريخ الانتهاء", _formatDate(endDate)),
            Divider(height: kSpacing * 1.5),
            Text("الأوقات:", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            SizedBox(height: kSpacing * 0.5),
            if (times.isEmpty)
              Text("  لا توجد أوقات محددة.", style: TextStyle(color: Colors.grey.shade600)),
            if (times.isNotEmpty)
              ListView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: times.length,
                itemBuilder: (context, index) {
                  String timeDisplay = "وقت غير صالح";
                  String? dayPrefix;
                  try {
                    if (times[index] is Map) { // Weekly format
                      final dayNum = int.tryParse(times[index]['day']?.toString() ?? '');
                      final timeStr = times[index]['time']?.toString();
                      if (dayNum != null && timeStr != null) {
                        final tod = _parseTime(timeStr);
                        if (tod != null) timeDisplay = _formatTimeOfDay(tod);
                        // Convert day number to name (Example)
                        dayPrefix = _getWeekdayName(dayNum);
                      }
                    } else if (times[index] is String) { // Daily format
                      final tod = _parseTime(times[index]);
                      if (tod != null) timeDisplay = _formatTimeOfDay(tod);
                    }
                  } catch (e) { print("Error formatting time in list: $e"); }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 18, color: kSecondaryColor),
                        SizedBox(width: 8),
                        if (dayPrefix != null) Text("$dayPrefix: ", style: TextStyle(fontWeight: FontWeight.w500)),
                        Text(timeDisplay, style: TextStyle(fontSize: 15)),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Helper to build a detail row with icon, label, and value.
  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kPrimaryColor.withOpacity(0.8), size: 20),
          SizedBox(width: 12),
          Text("$label ", style: TextStyle(color: Colors.grey.shade700, fontSize: 14, fontWeight: FontWeight.w500)),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // Helper to get weekday name (adjust based on your needs/locale)
  String _getWeekdayName(int dayNum) {
    const days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    if (dayNum >= 1 && dayNum <= 7) {
      return days[dayNum - 1]; // Adjust index if your numbers are 0-6 or 1-7
    }
    return "يوم؟";
  }
}
