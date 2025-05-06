import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:ui' as ui;

import '../Schedule/dose_schedule_services.dart';
import 'medication_detail_services.dart';
import 'medication_detail_ui_components.dart';
import 'time_utilities.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
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
  // Initialize services, animations, and state variables
  late MedicationDetailService _service;
  Map<String, dynamic>? _medData;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isProcessingConfirmation = false;
  bool _isReschedulingMode = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  tz.TZDateTime? _confirmationTimeLocal;
  TimeOfDay? _manualConfirmationTime;

  List<TimeOfDay> _suggestedTimes = [];
  TimeOfDay? _selectedSuggestedTime;
  TimeOfDay? _customSelectedTime;
  final TextEditingController _customTimeController = TextEditingController();

  final TextEditingController _dosageController = TextEditingController();
  final TextEditingController _dosageUnitController = TextEditingController();

  late MedicationDetailUIComponents _uiComponents;

  @override
  void initState() {
    super.initState();

    _service = MedicationDetailService();

    _uiComponents = MedicationDetailUIComponents(
      updateState: _updateState,
      handleConfirmation: _handleConfirmation,
      handleReschedule: _handleReschedule,
      showCustomTimePickerDialog: _showCustomTimePickerDialog,
      showManualTimePickerDialog: _showManualTimePickerDialog,
      setReschedulingModeTrue: _setReschedulingModeTrue,
      setReschedulingModeFalse: _setReschedulingModeFalse,
      selectSuggestedTime: _selectSuggestedTime,
      updateDosage: _showDosageUpdateDialog,
    );

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

  // Dispose resources
  @override
  void dispose() {
    _animationController.dispose();
    _customTimeController.dispose();
    _dosageController.dispose();
    _dosageUnitController.dispose();
    super.dispose();
  }

  // Update state callback for UI components
  void _updateState(Function callback) {
    if (mounted) {
      setState(() {
        callback();
      });
    }
  }

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
      _customSelectedTime = null;
      _customTimeController.clear();
    });
    _logAction("Suggested Time Selected", "Time: ${time.hour}:${time.minute}");
  }

  // Load medication data from Firestore
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

        _generateSmartReschedulingSuggestions();

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

  // Handle confirmation of medication dose (taken or skipped)
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

      if (widget.needsConfirmation && widget.confirmationKey != null && widget.confirmationKey!.isNotEmpty) {
        _logAction("Clearing Notification Flag", "Key: ${widget.confirmationKey}");
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(widget.confirmationKey!);
      }

      try {
        final doseScheduleService = DoseScheduleServices(user: FirebaseAuth.instance.currentUser);
        doseScheduleService.clearCache();
        _logAction("Cache Cleared", "Cleared dose schedule cache for refresh");
      } catch (e) {
        _logAction("Cache Clear Error", "Failed to clear cache: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              taken ? "تم تسجيل تناول الجرعة بنجاح." : "تم تسجيل تخطي الجرعة.",
              textAlign: TextAlign.right,
            ),
            backgroundColor: taken ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 1),
          ),
        );

        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            Navigator.pop(context, true);
          }
        });
      }
    } catch (e, stack) {
      _showErrorAndLog("processing confirmation", e, stack);
      if (mounted) {
        setState(() {
          _isProcessingConfirmation = false;
        });
      }
    }
  }

  // Handle rescheduling of medication dose
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

      if (widget.confirmationTimeIso == null && _medData != null && _medData!.containsKey('times')) {
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

      if (widget.needsConfirmation && widget.confirmationKey != null && widget.confirmationKey!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(widget.confirmationKey!);
        _logAction("Cleared Notification Flag", "After rescheduling: ${widget.confirmationKey}");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "تمت إعادة جدولة الجرعة إلى ${TimeUtilities.formatTimeOfDay(selectedTime)} بنجاح.",
              textAlign: TextAlign.right,
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );

        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            Navigator.pop(context, true);
          }
        });
      }
    } catch (e, stack) {
      _showErrorAndLog("rescheduling dose", e, stack);
      if (mounted) {
        setState(() {
          _isProcessingConfirmation = false;
        });
      }
    }
  }

  // Generate smart rescheduling suggestions based on current schedule
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

  // Show a dialog for updating the dosage
  Future<void> _showDosageUpdateDialog(String currentDosage, String currentUnit) async {
    _dosageController.text = currentDosage;
    _dosageUnitController.text = currentUnit;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            "تعديل الجرعة",
            textAlign: TextAlign.right,
            style: TextStyle(
              color: kPrimaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _dosageController,
                  decoration: InputDecoration(
                    labelText: "مقدار الجرعة",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.text,
                ),
                SizedBox(height: 12),
                TextField(
                  controller: _dosageUnitController,
                  decoration: InputDecoration(
                    labelText: "وحدة القياس (مثال: ملغ، حبة)",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.text,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text("إلغاء"),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text("حفظ"),
              onPressed: () {
                _updateMedicationDosage(
                  _dosageController.text.trim(),
                  _dosageUnitController.text.trim(),
                );
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
          actionsPadding: EdgeInsets.all(8),
          actionsAlignment: MainAxisAlignment.spaceBetween,
        );
      },
    );
  }

  // Update the medication dosage in Firestore
  Future<void> _updateMedicationDosage(String newDosage, String newUnit) async {
    if (newDosage.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "الرجاء إدخال مقدار الجرعة",
            textAlign: TextAlign.right,
          ),
          backgroundColor: kErrorColor,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _service.updateMedicationInfo(
        widget.docId,
        {
          'dosage': newDosage,
          'dosageUnit': newUnit,
        },
      );

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "تم تحديث الجرعة بنجاح",
              textAlign: TextAlign.right,
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );

        _loadMedicationData();
      } else {
        _showErrorAndLog(
          "updating dosage",
          result.error ?? "فشل تحديث الجرعة",
          null,
        );
      }
    } catch (e, stack) {
      _showErrorAndLog("updating dosage", e, stack);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorAndLog(String operation, dynamic error, StackTrace? stackTrace) {
    final errorMsg = "Error in $operation: $error";
    print("[DetailPage ERROR] $errorMsg");
    if (stackTrace != null) {
      print("[DetailPage ERROR] Stack trace: $stackTrace");
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("[DetailPage ERROR] User is not authenticated!");
    }

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
        _selectedSuggestedTime = null;
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

  void _logAction(String action, String details) {
    final now = DateTime.now().toIso8601String();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'unknown_user';
    print("[MedicationDetail] [$now] [$userId] $action: $details");
  }

  @override
  Widget build(BuildContext context) {
    String appBarTitle = "تفاصيل الدواء";
    if (widget.needsConfirmation) {
      appBarTitle = "تأكيد جرعة الدواء";
    } else if (widget.openedFromNotification) {
      appBarTitle = "تذكير بجرعة الدواء";
    }

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
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            appBarTitle,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          backgroundColor: widget.needsConfirmation ? Colors.orange.shade700 : kPrimaryColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
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
