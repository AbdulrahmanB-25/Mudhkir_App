import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:ui' as ui;

import '../MeidcaitonDetailPage_Utility/medication_detail_services.dart';
import '../MeidcaitonDetailPage_Utility/medication_detail_ui_components.dart';
import '../MeidcaitonDetailPage_Utility/time_utilities.dart';

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

class _MedicationDetailPageState extends State<MedicationDetailPage>
    with SingleTickerProviderStateMixin {
  // Services
  late MedicationDetailService _service;

  // State variables
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

  // UI components
  late MedicationDetailUIComponents _uiComponents;

  @override
  void initState() {
    super.initState();

    // Initialize service
    _service = MedicationDetailService();

    // Initialize UI components with all the needed callbacks
    _uiComponents = MedicationDetailUIComponents(
      updateState: _updateState,
      handleConfirmation: _handleConfirmation,
      handleReschedule: _handleReschedule,
      showCustomTimePickerDialog: _showCustomTimePickerDialog,
      showManualTimePickerDialog: _showManualTimePickerDialog,
      // Add these new callbacks
      setReschedulingModeTrue: _setReschedulingModeTrue,
      setReschedulingModeFalse: _setReschedulingModeFalse,
      selectSuggestedTime: _selectSuggestedTime,
    );

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
          minute: _confirmationTimeLocal!.minute,
        );
        _logAction("Confirmation Time Set", "Parsed from ISO: ${widget.confirmationTimeIso}");
      } catch (e, stack) {
        _showErrorAndLog(
            "parsing confirmation time",
            "Invalid ISO: '${widget.confirmationTimeIso}': $e",
            stack
        );
        _errorMessage = "خطأ في تحديد وقت التأكيد.";
      }
    }

    _loadMedicationData();
  }

  // Update state callback for UI components
  void _updateState(Function callback) {
    if (mounted) {
      setState(() {
        callback();
      });
    }
  }

  // New methods to handle rescheduling state
  void _setReschedulingModeTrue() {
    setState(() {
      _isReschedulingMode = true;
    });
    _logAction("Rescheduling Mode", "Activated");
  }

  void _setReschedulingModeFalse() {
    setState(() {
      _isReschedulingMode = false;
      _selectedSuggestedTime = null;
      _customSelectedTime = null;
      _customTimeController.clear();
    });
    _logAction("Rescheduling Mode", "Deactivated");
  }

  void _selectSuggestedTime(TimeOfDay time) {
    setState(() {
      _selectedSuggestedTime = time;
      _customSelectedTime = null; // Clear custom selection
      _customTimeController.clear();
    });
    _logAction("Suggested Time Selected", "Time: ${time.hour}:${time.minute}");
  }

  @override
  void dispose() {
    _animationController.dispose();
    _customTimeController.dispose();
    super.dispose();
  }

  // Improved logging helper
  void _logAction(String action, String details) {
    print("[DetailPage] $action: $details | Document: ${widget.docId} | Confirmation needed: ${widget.needsConfirmation}");
  }

  // Enhanced error handler with logging
  void _showErrorAndLog(String operation, dynamic error, StackTrace? stackTrace) {
    final errorMsg = "Error in $operation: $error";
    print("[DetailPage ERROR] $errorMsg");
    if (stackTrace != null) {
      print("[DetailPage ERROR] Stack trace: $stackTrace");
    }

    // Check if user is authenticated
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("[DetailPage ERROR] User is not authenticated!");
    }

    // Check if we have a document ID
    if (widget.docId.isEmpty) {
      print("[DetailPage ERROR] Invalid document ID!");
    }

    if (mounted) {
      setState(() {
        _isProcessingConfirmation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "حدث خطأ: ${error.toString().substring(0, min(50, error.toString().length))}",
            textAlign: TextAlign.right,
          ),
          backgroundColor: kErrorColor,
          duration: Duration(seconds: 5),
          action: SnackBarAction(
            label: 'حاول مجددا',
            onPressed: () {
              _loadMedicationData();
            },
          ),
        ),
      );
    }
  }

  Future<void> _loadMedicationData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      _logAction("Loading Medication", "Fetching document: ${widget.docId}");

      final result = await _service.loadMedicationData(widget.docId);

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _medData = result.data;
          _isLoading = false;
        });

        _logAction("Medication Data Loaded", "Successfully loaded data");

        // Always prepare suggested times for scheduling
        _generateSmartReschedulingSuggestions();

        // Set default confirmation time for non-confirmation mode
        if (!widget.needsConfirmation && _manualConfirmationTime == null) {
          _manualConfirmationTime = TimeOfDay.now();
        }
      } else {
        _logAction("Medication Load Failed", result.error ?? "Unknown error");
        setState(() {
          _isLoading = false;
          _errorMessage = result.error ?? 'لم يتم العثور على بيانات الدواء.';
        });
      }
    } catch (e, stack) {
      _showErrorAndLog("loading medication details", e, stack);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'خطأ في تحميل البيانات.';
        });
      }
    }
  }

  // --- Smart Rescheduling Logic ---
  Future<void> _generateSmartReschedulingSuggestions() async {
    if (!mounted) return;

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      final result = await _service.generateSmartReschedulingSuggestions(
          userId,
          widget.docId
      );

      if (!mounted) return;

      setState(() {
        _suggestedTimes = result;
      });
    } catch (e, stack) {
      _showErrorAndLog("generating rescheduling suggestions", e, stack);
    }
  }

  // --- Confirmation and Rescheduling Actions ---
  Future<void> _handleConfirmation(bool taken) async {
    if (!mounted || _isProcessingConfirmation) return;

    setState(() => _isProcessingConfirmation = true);
    _logAction("Confirmation Action", "User selected: ${taken ? 'TAKEN' : 'SKIPPED'}");

    try {
      TimeOfDay timeToConfirm = _manualConfirmationTime ?? TimeOfDay.now();

      final result = await _service.recordMedicationConfirmation(
          widget.docId,
          timeToConfirm,
          taken,
          widget.needsConfirmation ? 'app_confirmation_prompt' : 'manual_confirmation'
      );

      if (!result.success) {
        throw Exception(result.error ?? "Failed to record confirmation");
      }

      _logAction("Confirmation Recorded", "Status: ${taken ? 'TAKEN' : 'SKIPPED'} at ${timeToConfirm.hour}:${timeToConfirm.minute}");

      // Clear notification flag if applicable
      if (widget.needsConfirmation && widget.confirmationKey != null && widget.confirmationKey!.isNotEmpty) {
        _logAction("Clearing Notification Flag", "Key: ${widget.confirmationKey}");
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(widget.confirmationKey!);

        if (mounted) {
          Navigator.pop(context, true);
          return;
        }
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              taken ? "تم تسجيل تناول الجرعة بنجاح." : "تم تسجيل تخطي الجرعة.",
              textAlign: TextAlign.right,
            ),
            backgroundColor: taken ? Colors.green : Colors.orange,
          ),
        );

        // Reset for next confirmation if not from notification
        if (!widget.needsConfirmation) {
          setState(() {
            _manualConfirmationTime = TimeOfDay.now();
            _isProcessingConfirmation = false;
          });
        }
      }
    } catch (e, stack) {
      _showErrorAndLog("processing confirmation", e, stack);
    }
  }

  // Handle rescheduling
  Future<void> _handleReschedule() async {
    if (!mounted || _isProcessingConfirmation) return;

    setState(() => _isProcessingConfirmation = true);

    try {
      final TimeOfDay? selectedTime = _selectedSuggestedTime ?? _customSelectedTime;
      if (selectedTime == null) {
        setState(() => _isProcessingConfirmation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "الرجاء اختيار وقت لإعادة الجدولة.",
              textAlign: TextAlign.right,
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final dateTime = TimeUtilities.timeOfDayToDateTime(selectedTime);
      String? originalTimeString;
      
      // For manual rescheduling without notification, create a timestamp string for today's date
      if (widget.confirmationTimeIso == null && _medData != null && _medData!.containsKey('times')) {
        // If we're manually rescheduling, log the action with more details
        _logAction("Manual Rescheduling", "Selected new time: ${selectedTime.hour}:${selectedTime.minute} (${dateTime.toString()})");
      } else {
        _logAction("Notification Rescheduling", "New time: ${selectedTime.hour}:${selectedTime.minute} (${dateTime.toString()})");
      }

      final result = await _service.recordMedicationRescheduling(
          widget.docId,
          dateTime,
          widget.confirmationTimeIso,
          widget.needsConfirmation ? 'app_rescheduling' : 'manual_rescheduling'
      );

      if (!result.success) {
        throw Exception(result.error ?? "Failed to reschedule medication");
      }

      // Clear any existing confirmation flag if from notification
      if (widget.needsConfirmation && widget.confirmationKey != null && widget.confirmationKey!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(widget.confirmationKey!);
        _logAction("Cleared Notification Flag", "After rescheduling: ${widget.confirmationKey}");
      }

      // Reload medication data to reflect changes
      _loadMedicationData();

      if (mounted) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "تمت إعادة جدولة الجرعة إلى ${TimeUtilities.formatTimeOfDay(selectedTime)} بنجاح.",
              textAlign: TextAlign.right,
            ),
            backgroundColor: Colors.green,
          ),
        );

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
    } catch (e, stack) {
      _showErrorAndLog("rescheduling dose", e, stack);
    }
  }

  // Time picker dialogs
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
        _customTimeController.text = TimeUtilities.formatTimeOfDay(picked);
      });
      _logAction("Custom Time Selected", "User picked: ${picked.hour}:${picked.minute}");
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
      _logAction("Manual Confirmation Time Selected", "User picked: ${picked.hour}:${picked.minute}");
    }
  }

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
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          backgroundColor: widget.needsConfirmation ? Colors.orange.shade700 : kPrimaryColor,
          elevation: 0,
          shape: widget.needsConfirmation
              ? null
              : RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(kBorderRadius),
            ),
          ),
        ),
        backgroundColor: kBackgroundColor,
        body: _buildBody(confirmationTimeFormatted),
      ),
    );
  }

  Widget _buildBody(String confirmationTimeFormatted) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kPrimaryColor),
            SizedBox(height: kSpacing),
            Text(
              "جاري تحميل البيانات...",
              style: TextStyle(color: kPrimaryColor),
            ),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return _uiComponents.buildErrorView(_errorMessage, _loadMedicationData);
    }

    if (_medData == null) {
      return Center(
        child: Text(
          'لا توجد بيانات لعرضها.',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(kSpacing),
        physics: BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Confirmation Section (if needed or in reschedule mode)
            if (widget.needsConfirmation && !_isReschedulingMode)
              _uiComponents.buildEnhancedConfirmationSection(
                _medData!,
                confirmationTimeFormatted,
                _isProcessingConfirmation,
              )
            else if (_isReschedulingMode)
              _uiComponents.buildReschedulingSection(
                _suggestedTimes,
                _selectedSuggestedTime,
                _customSelectedTime,
                _isProcessingConfirmation,
                _customTimeController,
              )
            else
              _uiComponents.buildActionSection(
                _medData!,
                _manualConfirmationTime,
                _isProcessingConfirmation,
              ),

            // Medication Info
            SizedBox(height: kSpacing),
            _uiComponents.buildMedicationInfoCard(_medData!),
            SizedBox(height: kSpacing),
            _uiComponents.buildScheduleInfoCard(_medData!),
            SizedBox(height: kSpacing),
          ],
        ),
      ),
    );
  }
}

