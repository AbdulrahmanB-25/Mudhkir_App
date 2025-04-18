import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:ui' as ui;
// Import SharedPreferences keys from main.dart
import '../main.dart';

// Constants for theming
const Color kPrimaryColor = Color(0xFF2E86C1); // Medium hospital blue
const Color kSecondaryColor = Color(0xFF5DADE2); // Light hospital blue
const Color kErrorColor = Color(0xFFFF6B6B); // Error red
const Color kBackgroundColor = Color(0xFFF5F8FA); // Very light blue-gray background
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

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

class _MedicationDetailPageState extends State<MedicationDetailPage> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _medData;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isProcessingConfirmation = false;
  bool _isReschedulingMode = false;

  // Animation controller for smooth transitions
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Store the specific time being confirmed (in local timezone)
  tz.TZDateTime? _confirmationTimeLocal;
  TimeOfDay? _manualConfirmationTime;

  // For smart rescheduling
  List<TimeOfDay> _suggestedTimes = [];
  TimeOfDay? _selectedSuggestedTime;
  TimeOfDay? _customSelectedTime;
  final TextEditingController _customTimeController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Initialize animation controller
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();

    if (widget.needsConfirmation && widget.confirmationTimeIso != null) {
      try {
        // Parse the UTC ISO string and convert it to local TZDateTime
        final utcTime = DateTime.parse(widget.confirmationTimeIso!);
        _confirmationTimeLocal = tz.TZDateTime.from(utcTime, tz.local);
        _manualConfirmationTime = TimeOfDay(
            hour: _confirmationTimeLocal!.hour,
            minute: _confirmationTimeLocal!.minute
        );
      } catch (e) {
        print("[DetailPage] Error parsing confirmation time ISO '${widget.confirmationTimeIso}': $e");
        _errorMessage = "خطأ في تحديد وقت التأكيد.";
      }
    }

    _loadMedicationData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _customTimeController.dispose();
    super.dispose();
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

          // Always prepare suggested times for scheduling
          _generateSmartReschedulingSuggestions(user.uid);

          // Set default confirmation time for non-confirmation mode
          if (!widget.needsConfirmation && _manualConfirmationTime == null) {
            _manualConfirmationTime = TimeOfDay.now();
          }
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

  // --- Smart Rescheduling Logic ---

  Future<void> _generateSmartReschedulingSuggestions(String userId) async {
    if (!mounted) return;

    try {
      // Generate 3 smart suggested times
      final now = tz.TZDateTime.now(tz.local);
      final currentHour = now.hour;
      final currentMinute = now.minute;

      // 1. Fetch all user's medication times to avoid conflicts
      List<TimeOfDay> existingTimes = [];
      final medsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .where(FieldPath.documentId, isNotEqualTo: widget.docId) // Exclude current medication
          .get();

      for (var doc in medsSnapshot.docs) {
        final data = doc.data();
        final List<dynamic> times = data['times'] ?? [];

        for (var timeData in times) {
          String? timeStr;
          if (timeData is String) {
            timeStr = timeData;
          } else if (timeData is Map<String, dynamic> && timeData['time'] is String) {
            timeStr = timeData['time'];
          }

          if (timeStr != null) {
            final tod = _parseTime(timeStr);
            if (tod != null) {
              existingTimes.add(tod);
            }
          }
        }
      }

      // 2. Find optimal times based on current time and existing medication schedule
      List<TimeOfDay> candidateTimes = [];

      // Suggestion 1: Next full hour (if it's in the future)
      final nextHour = TimeOfDay(hour: (currentHour + 1) % 24, minute: 0);
      if (_isTimeInFuture(nextHour)) {
        candidateTimes.add(nextHour);
      }

      // Suggestion 2: Add 2 hours from now
      final twoHoursLater = _addHoursToTime(currentHour, currentMinute, 2);
      candidateTimes.add(twoHoursLater);

      // Suggestion 3: Add 4 hours from now
      final fourHoursLater = _addHoursToTime(currentHour, currentMinute, 4);
      candidateTimes.add(fourHoursLater);

      // Additional suggestions based on common medication times
      final List<TimeOfDay> commonTimes = [
        const TimeOfDay(hour: 8, minute: 0),   // Morning
        const TimeOfDay(hour: 12, minute: 0),  // Noon
        const TimeOfDay(hour: 18, minute: 0),  // Evening
        const TimeOfDay(hour: 21, minute: 0),  // Night
      ];

      for (var time in commonTimes) {
        if (_isTimeInFuture(time) &&
            !_isTimeCloseToAny(time, candidateTimes) &&
            !_isTimeCloseToAny(time, existingTimes)) {
          candidateTimes.add(time);
        }
      }

      // Sort times chronologically and take the first 3 unique times
      candidateTimes.sort((a, b) => _compareTimeOfDay(a, b));

      final uniqueTimes = <TimeOfDay>[];
      for (var time in candidateTimes) {
        if (!_isTimeCloseToAny(time, uniqueTimes)) {
          uniqueTimes.add(time);
          if (uniqueTimes.length >= 3) break;
        }
      }

      // If we still need more suggestions, add some spaced apart
      while (uniqueTimes.length < 3) {
        final lastTime = uniqueTimes.isNotEmpty
            ? uniqueTimes.last
            : TimeOfDay(hour: currentHour, minute: currentMinute);
        final nextTime = _addHoursToTime(lastTime.hour, lastTime.minute, 2);
        uniqueTimes.add(nextTime);
      }

      if (mounted) {
        setState(() {
          _suggestedTimes = uniqueTimes;
        });
      }

    } catch (e) {
      print("[SmartRescheduling] Error generating suggestions: $e");
    }
  }

  bool _isTimeInFuture(TimeOfDay time) {
    final now = TimeOfDay.now();
    return time.hour > now.hour || (time.hour == now.hour && time.minute > now.minute);
  }

  bool _isTimeCloseToAny(TimeOfDay time, List<TimeOfDay> times) {
    const int minimumMinutesBetween = 60; // 1 hour minimum between doses

    for (var existingTime in times) {
      final diff = _getTimeDifferenceInMinutes(time, existingTime).abs();
      if (diff < minimumMinutesBetween) {
        return true;
      }
    }
    return false;
  }

  int _getTimeDifferenceInMinutes(TimeOfDay time1, TimeOfDay time2) {
    return (time1.hour * 60 + time1.minute) - (time2.hour * 60 + time2.minute);
  }

  TimeOfDay _addHoursToTime(int hour, int minute, int hoursToAdd) {
    int totalMinutes = hour * 60 + minute + hoursToAdd * 60;
    return TimeOfDay(
      hour: (totalMinutes ~/ 60) % 24,
      minute: totalMinutes % 60,
    );
  }

  int _compareTimeOfDay(TimeOfDay a, TimeOfDay b) {
    if (a.hour != b.hour) return a.hour - b.hour;
    return a.minute - b.minute;
  }

  // --- Confirmation and Rescheduling Actions ---

  Future<void> _handleConfirmation(bool taken) async {
    if (!mounted || _isProcessingConfirmation) return;

    setState(() => _isProcessingConfirmation = true);

    TimeOfDay timeToConfirm = _manualConfirmationTime ?? TimeOfDay.now();

    print("[DetailPage Confirmation] User action: ${taken ? 'Confirmed' : 'Skipped'} for medication ${widget.docId}");

    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Convert TimeOfDay to DateTime for the current day
        final now = DateTime.now();
        DateTime confirmationTime = DateTime(
            now.year, now.month, now.day, timeToConfirm.hour, timeToConfirm.minute
        );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('medicines')
            .doc(widget.docId)
            .collection('dose_history')
            .add({
          'timestamp': Timestamp.now(),
          'scheduledTime': Timestamp.fromDate(confirmationTime),
          'status': taken ? 'taken' : 'skipped',
          'confirmedVia': widget.needsConfirmation ? 'app_confirmation_prompt' : 'manual_confirmation',
        });

        print("[DetailPage Confirmation] Logged dose history status: ${taken ? 'taken' : 'skipped'}");

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    taken
                        ? "تم تسجيل تناول الجرعة بنجاح."
                        : "تم تسجيل تخطي الجرعة.",
                    textAlign: TextAlign.right
                ),
                backgroundColor: taken ? Colors.green : Colors.orange,
              )
          );
        }
      } catch (e) {
        print("[DetailPage Confirmation] ERROR logging dose history: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("خطأ في تسجيل حالة الجرعة.", textAlign: TextAlign.right),
              backgroundColor: kErrorColor));
        }
        setState(() => _isProcessingConfirmation = false);
        return;
      }
    }

    // If this is from a notification confirmation, clear the shared preferences flag
    if (widget.needsConfirmation && widget.confirmationKey != null && widget.confirmationKey!.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(widget.confirmationKey!);
        print("[DetailPage Confirmation] Removed confirmation flag: ${widget.confirmationKey}");

        // Pop with true to trigger medication reschedule
        if (mounted) {
          Navigator.pop(context, true);
          return; // Early return to avoid re-enabling buttons
        }
      } catch (e) {
        print("[DetailPage Confirmation] ERROR removing SharedPreferences key '${widget.confirmationKey}': $e");
      }
    }

    if (mounted) {
      setState(() => _isProcessingConfirmation = false);

      // If we're in regular mode (not from notification), just re-enable the buttons
      if (!widget.needsConfirmation) {
        setState(() {
          _manualConfirmationTime = TimeOfDay.now();  // Reset for next confirmation
        });
      }
    }
  }

  Future<void> _handleReschedule() async {
    if (!mounted || _isProcessingConfirmation) return;

    setState(() => _isProcessingConfirmation = true);

    final TimeOfDay? selectedTime = _selectedSuggestedTime ?? _customSelectedTime;
    if (selectedTime == null) {
      setState(() => _isProcessingConfirmation = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("الرجاء اختيار وقت لإعادة الجدولة.", textAlign: TextAlign.right),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isProcessingConfirmation = false);
      return;
    }

    try {
      // Convert selected time to a DateTime for today
      final now = DateTime.now();
      DateTime newScheduledTime = DateTime(
          now.year, now.month, now.day, selectedTime.hour, selectedTime.minute
      );

      // If the time is in the past for today, schedule for tomorrow
      if (newScheduledTime.isBefore(now)) {
        newScheduledTime = newScheduledTime.add(const Duration(days: 1));
      }

      // Log the rescheduling action
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(widget.docId)
          .collection('dose_history')
          .add({
        'timestamp': Timestamp.now(),
        'scheduledTime': widget.confirmationTimeIso != null ?
        Timestamp.fromDate(DateTime.parse(widget.confirmationTimeIso!)) : Timestamp.now(),
        'status': 'rescheduled',
        'newScheduledTime': Timestamp.fromDate(newScheduledTime),
        'confirmedVia': widget.needsConfirmation ? 'app_rescheduling' : 'manual_rescheduling',
      });

      // Clear any existing confirmation flag if from notification
      if (widget.needsConfirmation && widget.confirmationKey != null && widget.confirmationKey!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(widget.confirmationKey!);
        print("[DetailPage Confirmation] Removed confirmation flag after rescheduling: ${widget.confirmationKey}");
      }

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "تمت إعادة جدولة الجرعة إلى ${_formatTimeOfDay(selectedTime)} بنجاح.",
              textAlign: TextAlign.right
          ),
          backgroundColor: Colors.green,
        ));

        // If from notification, pop with true to trigger medication reschedule
        if (widget.needsConfirmation) {
          Navigator.pop(context, true);
        } else {
          // Just reset state for regular mode
          setState(() {
            _isReschedulingMode = false;
            _isProcessingConfirmation = false;
            _selectedSuggestedTime = null;
            _customSelectedTime = null;
            _customTimeController.clear();
          });
        }
      }

    } catch (e) {
      print("[DetailPage Rescheduling] ERROR: $e");
      if (mounted) {
        setState(() => _isProcessingConfirmation = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("حدث خطأ أثناء إعادة الجدولة.", textAlign: TextAlign.right),
          backgroundColor: kErrorColor,
        ));
      }
    }
  }

  Future<void> _showCustomTimePickerDialog() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: kPrimaryColor,
              onPrimary: Colors.white,
              surface: kBackgroundColor,
              onSurface: Colors.black87,
            ),
            dialogBackgroundColor: kBackgroundColor,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _customSelectedTime = picked;
        _selectedSuggestedTime = null; // Clear suggested selection
        _customTimeController.text = _formatTimeOfDay(picked);
      });
    }
  }

  Future<void> _showManualTimePickerDialog() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _manualConfirmationTime ?? TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: kPrimaryColor,
              onPrimary: Colors.white,
              surface: kBackgroundColor,
              onSurface: Colors.black87,
            ),
            dialogBackgroundColor: kBackgroundColor,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      setState(() {
        _manualConfirmationTime = picked;
      });
    }
  }

  // --- Helper Methods ---

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
      return DateFormat.yMMMd('ar_SA').format(date);
    } catch (e) {
      print("[DetailPage] Error formatting date: $e");
      return "تاريخ غير صالح";
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }

  // --- Build Methods ---

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
        confirmationTimeFormatted = DateFormat('h:mm a (EEEE)', 'ar_SA').format(_confirmationTimeLocal!);
      } catch (e) {
        print("[DetailPage] Error formatting confirmation time for display: $e");
        confirmationTimeFormatted = "وقت غير صالح";
      }
    }

    return Directionality(
      textDirection: ui.TextDirection.rtl, // Apply RTL for Arabic
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            appBarTitle,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          backgroundColor: widget.needsConfirmation ? Colors.orange.shade700 : kPrimaryColor,
          elevation: 0,
          shape: widget.needsConfirmation ? null : RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(kBorderRadius),
            ),
          ),
        ),
        backgroundColor: kBackgroundColor,
        body: _isLoading
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: kPrimaryColor),
              SizedBox(height: kSpacing),
              Text("جاري تحميل البيانات...", style: TextStyle(color: kPrimaryColor)),
            ],
          ),
        )
            : _errorMessage.isNotEmpty
            ? _buildErrorView()
            : _medData == null
            ? Center(child: Text('لا توجد بيانات لعرضها.', style: TextStyle(fontSize: 16)))
            : FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(kSpacing),
            physics: BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Confirmation Section (if needed or in reschedule mode)
                if (widget.needsConfirmation && !_isReschedulingMode)
                  _buildEnhancedConfirmationSection(confirmationTimeFormatted)
                else if (_isReschedulingMode)
                  _buildReschedulingSection()
                else
                  _buildActionSection(),

                // Medication Info
                SizedBox(height: kSpacing),
                _buildMedicationInfoCard(),
                SizedBox(height: kSpacing),
                _buildScheduleInfoCard(),
                SizedBox(height: kSpacing),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
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
              child: Icon(Icons.error_outline_rounded, color: kErrorColor, size: 48),
            ),
            SizedBox(height: kSpacing),
            Text(
              _errorMessage,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 16,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: kSpacing * 1.5),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back),
              label: Text("العودة"),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kBorderRadius / 2),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // New action section replacing modify/remove with confirm/reschedule
  Widget _buildActionSection() {
    final medName = _medData?['name'] ?? 'هذا الدواء';

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
              borderRadius: BorderRadius.vertical(top: Radius.circular(kBorderRadius - 1)),
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
                      child: Icon(Icons.medication_liquid, color: kPrimaryColor, size: 30),
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
                          if (_manualConfirmationTime != null)
                            Row(
                              children: [
                                Icon(Icons.access_time_outlined, size: 14, color: kSecondaryColor),
                                SizedBox(width: 4),
                                Text(
                                  _manualConfirmationTime != null ? _formatTimeOfDay(_manualConfirmationTime!) : "الوقت الحالي",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700,
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

                // Confirmation and Reschedule buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.check_circle),
                        label: Text("تأكيد تناول الدواء"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shadowColor: Colors.green.shade300,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius / 2),
                          ),
                        ),
                        onPressed: _isProcessingConfirmation
                            ? null
                            : () => _handleConfirmation(true),
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
                            borderRadius: BorderRadius.circular(kBorderRadius / 2),
                          ),
                        ),
                        onPressed: _isProcessingConfirmation
                            ? null
                            : () {
                          setState(() {
                            _isReschedulingMode = true;
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
                            borderRadius: BorderRadius.circular(kBorderRadius / 2),
                          ),
                        ),
                        onPressed: _isProcessingConfirmation
                            ? null
                            : () => _handleConfirmation(false),
                      ),
                    ),
                  ],
                ),

                // Show progress indicator when processing
                if (_isProcessingConfirmation)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
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

  Widget _buildEnhancedConfirmationSection(String timeFormatted) {
    final medName = _medData?['name'] ?? 'هذا الدواء';
    final dosage = _medData?['dosage'] ?? '';
    final dosageUnit = _medData?['dosageUnit'] ?? '';

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
              borderRadius: BorderRadius.vertical(top: Radius.circular(kBorderRadius - 1)),
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
                      child: Icon(Icons.medication_liquid, color: kPrimaryColor, size: 30),
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
                      border: Border.all(color: kSecondaryColor.withOpacity(0.3)),
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

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.check_circle_outline),
                        label: Text("تم تناول الجرعة"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: Colors.green.shade300,
                          padding: EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius / 2),
                          ),
                        ),
                        onPressed: _isProcessingConfirmation
                            ? null
                            : () => _handleConfirmation(true),
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
                        onPressed: _isProcessingConfirmation
                            ? null
                            : () {
                          setState(() {
                            _isReschedulingMode = true;
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
                        onPressed: _isProcessingConfirmation
                            ? null
                            : () => _handleConfirmation(false),
                      ),
                    ),
                  ],
                ),

                // Show progress indicator when processing
                if (_isProcessingConfirmation)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
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

  Widget _buildReschedulingSection() {
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(kBorderRadius - 1)),
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
                      Icon(Icons.lightbulb, color: Colors.amber.shade600, size: 24),
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
                  children: _suggestedTimes.map((time) {
                    final isSelected = _selectedSuggestedTime == time;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedSuggestedTime = time;
                              _customSelectedTime = null; // Clear custom time
                              _customTimeController.clear();
                            });
                          },
                          borderRadius: BorderRadius.circular(kBorderRadius / 2),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? kPrimaryColor : kPrimaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(kBorderRadius / 2),
                              border: Border.all(
                                color: isSelected ? kPrimaryColor : kPrimaryColor.withOpacity(0.3),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _formatTimeOfDay(time),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : kPrimaryColor,
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
                  onTap: _showCustomTimePickerDialog,
                  borderRadius: BorderRadius.circular(kBorderRadius / 2),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: _customSelectedTime != null ? kSecondaryColor.withOpacity(0.1) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(kBorderRadius / 2),
                      border: Border.all(
                        color: _customSelectedTime != null ? kSecondaryColor : Colors.grey.shade300,
                        width: _customSelectedTime != null ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          color: _customSelectedTime != null ? kSecondaryColor : Colors.grey.shade500,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _customSelectedTime != null
                                ? _formatTimeOfDay(_customSelectedTime!)
                                : "اضغط لتحديد وقت مخصص",
                            style: TextStyle(
                              fontSize: 15,
                              color: _customSelectedTime != null ? Colors.black87 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: _customSelectedTime != null ? kSecondaryColor : Colors.grey.shade500,
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
                        onPressed: _isProcessingConfirmation
                            ? null
                            : () {
                          setState(() {
                            _isReschedulingMode = false;
                          });
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.schedule),
                        label: Text("إعادة الجدولة"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kSecondaryColor,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: kSecondaryColor.withOpacity(0.4),
                          padding: EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius / 2),
                          ),
                        ),
                        onPressed: (_selectedSuggestedTime != null || _customSelectedTime != null) && !_isProcessingConfirmation
                            ? _handleReschedule
                            : null,
                      ),
                    ),
                  ],
                ),

                // Show progress indicator when processing
                if (_isProcessingConfirmation)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(kSecondaryColor),
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

  Widget _buildMedicationInfoCard() {
    final imageUrl = _medData?['imageUrl'] as String?;
    final medName = _medData?['name'] ?? 'دواء غير مسمى';
    final dosage = _medData?['dosage'] ?? 'غير محدد';
    final dosageUnit = _medData?['dosageUnit'] ?? '';
    final instructions = _medData?['instructions'] ?? 'لا توجد تعليمات.';

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
              borderRadius: BorderRadius.vertical(top: Radius.circular(kBorderRadius)),
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
                      Icon(Icons.medical_services_outlined, color: kPrimaryColor),
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

                if (instructions.isNotEmpty && instructions != 'لا توجد تعليمات.') ...[
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

  Widget _buildScheduleInfoCard() {
    final frequency = _medData?['frequencyType'] ?? 'غير محدد';
    final List<dynamic> times = _medData?['times'] ?? [];
    final startDate = _medData?['startDate'] as Timestamp?;
    final endDate = _medData?['endDate'] as Timestamp?;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
      // Header
      Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: kSecondaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.vertical(top: Radius.circular(kBorderRadius)),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, color: kSecondaryColor),
          SizedBox(width: 10),
          Text(
            "الجدول الزمني",
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
    Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
    color: kSecondaryColor.withOpacity(0.05),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: kSecondaryColor.withOpacity(0.1)),
    ),
    child: Row(
    children: [
    Icon(Icons.repeat, color: kSecondaryColor),
    SizedBox(width: 10),
    Text(
    "نوع التكرار:",
    style: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.bold,
    color: Colors.grey.shade700,
    ),
    ),
    SizedBox(width: 10),
    Text(
    frequency,
    style: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: kSecondaryColor,
    ),
    ),
    ],
    ),
    ),

    SizedBox(height: 16),

    // Date range info
    Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
    color: Colors.grey.shade50,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
    children: [
    Row(
    children: [
    Container(
    padding: EdgeInsets.all(8),
    decoration: BoxDecoration(
    color: kPrimaryColor.withOpacity(0.1),
    shape: BoxShape.circle,
    ),
    child: Icon(Icons.play_arrow, color: kPrimaryColor, size: 16),
    ),
    SizedBox(width: 12),
    Text(
    "تاريخ البدء:",
    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
    ),
    SizedBox(width: 8),
    Text(
    _formatDate(startDate),
    style: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
    ),
    ),
    ],
    ),

    SizedBox(height: 10),

    Row(
    children: [
    Container(
    padding: EdgeInsets.all(8),
    decoration: BoxDecoration(
    color: Colors.orange.withOpacity(0.1),
    shape: BoxShape.circle,
    ),
    child: Icon(Icons.stop, color: Colors.orange, size: 16),
    ),
    SizedBox(width: 12),
    Text(
    "تاريخ الانتهاء:",
    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
    ),
    SizedBox(width: 8),
    Text(
    _formatDate(endDate),
    style: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
    ),
    ),
    ],
    ),
    ],
    ),
    ),

    SizedBox(height: 16),

    Text(
    "أوقات الجرعات:",
    style: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
    ),
    ),

    SizedBox(height: 10),

    // Improved time display
    if (times.isEmpty)
    Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
    color: Colors.grey.shade50,
    borderRadius: BorderRadius.circular(10),
    ),
    child: Center(
    child: Text(
    "لا توجد أوقات محددة",
    style: TextStyle(color: Colors.grey.shade600),
    ),
    ),
    )
    else
    Container(
    padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: List.generate(times.length, (index) {
          String timeDisplay = "وقت غير صالح";
          String? dayPrefix;
          try {
            if (times[index] is Map) { // Weekly format
              final dayNum = int.tryParse(times[index]['day']?.toString() ?? '');
              final timeStr = times[index]['time']?.toString();
              if (dayNum != null && timeStr != null) {
                final tod = _parseTime(timeStr);
                if (tod != null) timeDisplay = _formatTimeOfDay(tod);
                // Convert day number to name
                dayPrefix = _getWeekdayName(dayNum);
              }
            } else if (times[index] is String) { // Daily format
              final tod = _parseTime(times[index]);
              if (tod != null) timeDisplay = _formatTimeOfDay(tod);
            }
          } catch (e) { print("Error formatting time in list: $e"); }

          return Container(
            margin: EdgeInsets.only(bottom: index < times.length - 1 ? 8 : 0),
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            decoration: BoxDecoration(
              color: index % 2 == 0 ? Colors.white : null,
              borderRadius: BorderRadius.circular(8),
              border: index % 2 == 0 ? Border.all(color: Colors.grey.shade200) : null,
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 18, color: kSecondaryColor),
                SizedBox(width: 10),
                if (dayPrefix != null) ...[
                  Text(
                    "$dayPrefix: ",
                    style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey.shade700),
                  ),
                ],
                Text(
                  timeDisplay,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    ),
    ],
    ),
    ),
          ],
      ),
    );
  }

  // Helper to get weekday name in Arabic
  String _getWeekdayName(int dayNum) {
    const days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    if (dayNum >= 1 && dayNum <= 7) {
      return days[dayNum - 1]; // Adjust index if your numbers are 0-6 or 1-7
    }
    return "يوم؟";
  }
}

// Custom time formatter utility class that could be used elsewhere in the app
class TimeUtils {
  static String formatTimeOfDay(BuildContext context, TimeOfDay time) {
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }

  // Helper method to determine if a time is in the future
  static bool isTimeInFuture(TimeOfDay time) {
    final now = TimeOfDay.now();
    return time.hour > now.hour || (time.hour == now.hour && time.minute > now.minute);
  }

  // Helper method to convert TimeOfDay to DateTime for today
  static DateTime timeOfDayToDateTime(TimeOfDay time) {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
  }

  // Helper method to add hours to a TimeOfDay
  static TimeOfDay addHoursToTime(TimeOfDay time, int hoursToAdd) {
    final totalMinutes = (time.hour * 60 + time.minute) + (hoursToAdd * 60);
    return TimeOfDay(
      hour: (totalMinutes ~/ 60) % 24,
      minute: totalMinutes % 60,
    );
  }
}