import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:ui' as ui;

// Import your services and widgets
import 'package:mudhkir_app/services/AlarmNotificationHelper.dart';
import 'package:mudhkir_app/Widgets/bottom_navigation.dart';
import 'package:mudhkir_app/Pages/MedicationDetail_Page.dart'; // Import for type safety if needed
import 'package:mudhkir_app/services/companion_medication_tracker.dart';

// Import SharedPreferences keys from main.dart (adjust path if needed)
import '../main.dart';

// --- Constants ---
const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;
// --- End Constants ---


class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  String _userName = '';
  String _closestMedName = '';
  String _closestMedTimeStr = '';
  String _closestMedDocId = '';
  bool _isLoadingMed = true; // Specifically for the 'Upcoming Dose' UI tile
  bool _isInitializing = true; // Tracks overall initial loading/checking state
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  bool _isAuthenticated = false;
  User? _currentUser; // Store current user

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    FirebaseAuth.instance.authStateChanges().listen(_handleAuthStateChange);
    _initializePage();
  }

  Future<void> _initializePage() async {
    if (!mounted) return;
    setState(() => _isInitializing = true);

    final user = FirebaseAuth.instance.currentUser;
    await _handleAuthStateChange(user, isInitialLoad: true);

    if (mounted) {
      setState(() => _isInitializing = false);
      _animationController.forward();
    }
  }

  Future<void> _handleAuthStateChange(User? user, {bool isInitialLoad = false}) async {
    if (!mounted) return;

    final newAuthStatus = user != null;
    final authChanged = _isAuthenticated != newAuthStatus;
    _currentUser = user;

    setState(() {
      _isAuthenticated = newAuthStatus;
      if (!_isAuthenticated) {
        _userName = '';
        _closestMedName = '';
        _closestMedTimeStr = '';
        _closestMedDocId = '';
        _isLoadingMed = false;
      } else if (authChanged || isInitialLoad) {
        _userName = '';
        _isLoadingMed = true;
      }
    });

    if (!_isAuthenticated) {
      await AlarmNotificationHelper.cancelAllNotifications();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
      await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
      print("[Auth] User logged out or guest. Notifications cancelled and state cleared.");

      if (authChanged && !isInitialLoad) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ModalRoute.of(context)?.settings.name != '/welcome') {
            Navigator.of(context).pushReplacementNamed('/welcome');
          }
        });
      }
    } else if (_currentUser != null) {
      await _loadUserDataAndSchedule();
      await _checkAndShowConfirmationIfNeeded();
    }

    if (isInitialLoad && mounted) {
      setState(() => _isInitializing = false);
      if(!_animationController.isAnimating){
        _animationController.forward();
      }
    }
  }

  Future<void> _loadUserDataAndSchedule() async {
    if (!mounted || !_isAuthenticated || _currentUser == null) return;

    if (!_isLoadingMed && mounted) {
      setState(() => _isLoadingMed = true);
    }

    await _loadUserName();
    await _scheduleAllUserMedications(_currentUser!.uid);
    // --- Fetch and schedule companion medications on every refresh ---
    await CompanionMedicationTracker.fetchAndScheduleCompanionMedications();
    await _loadClosestMedDisplayData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _scheduleAllUserMedications(String userId) async {
    if (!mounted) return;
    print("[Scheduling] Starting scheduling process for user $userId...");

    // Ensure notification channels are configured before scheduling
    try {
      await AlarmNotificationHelper.ensureChannelsSetup();
      print("[Scheduling] Ensured notification channels are set up.");
    } catch (e) {
      print("[Scheduling] ERROR ensuring notification channels setup: $e");
      // Optionally handle this error, though scheduling might still work if channels exist
    }

    await AlarmNotificationHelper.cancelAllNotifications();
    print("[Scheduling] Cancelled previous notifications.");

    List<Map<String, dynamic>> upcomingDoses = [];
    int scheduledCount = 0; // Counter for scheduled notifications

    try {
      final medsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .get();

      print("[Scheduling] Fetched ${medsSnapshot.docs.length} medication documents.");

      final tz.Location local = tz.local;
      final tz.TZDateTime now = tz.TZDateTime.now(local);

      // Calculate start and end of today for filtering today's doses
      final tz.TZDateTime todayStart = tz.TZDateTime(local, now.year, now.month, now.day);
      final tz.TZDateTime tomorrowStart = todayStart.add(const Duration(days: 1));

      print("[Scheduling] Current time: $now (Local)");
      print("[Scheduling] Today's window for next dose check: $todayStart to $tomorrowStart");

      for (var doc in medsSnapshot.docs) {
        final data = doc.data();
        final docId = doc.id;
        final medName = data['name'] as String? ?? 'دواء غير مسمى';
        final startTimestamp = data['startDate'] as Timestamp?;
        final endTimestamp = data['endDate'] as Timestamp?;

        if (startTimestamp == null) {
          print("[Scheduling] Skipping '$medName' ($docId): Missing start date.");
          continue;
        }

        final tz.TZDateTime startDate = tz.TZDateTime.from(startTimestamp.toDate(), local);
        final tz.TZDateTime? endDate = endTimestamp != null ? tz.TZDateTime.from(endTimestamp.toDate(), local) : null;

        // Basic filtering: Skip if medication hasn't started or has already ended
        final tz.TZDateTime todayFloor = tz.TZDateTime(local, now.year, now.month, now.day);
        final tz.TZDateTime startDayFloor = tz.TZDateTime(local, startDate.year, startDate.month, startDate.day);
        if (todayFloor.isBefore(startDayFloor)) {
          print("[Scheduling] Skipping '$medName' ($docId): Start date ($startDate) is in the future.");
          continue;
        }
        if (endDate != null) {
          final tz.TZDateTime endDayFloor = tz.TZDateTime(local, endDate.year, endDate.month, endDate.day);
          if (todayFloor.isAfter(endDayFloor)) {
            print("[Scheduling] Skipping '$medName' ($docId): End date ($endDate) has passed.");
            continue;
          }
        }

        final frequencyType = data['frequencyType'] as String? ?? 'يومي';
        final List<dynamic> timesRaw = data['times'] ?? [];

        // Schedule doses within a reasonable future window (e.g., 48 hours)
        final Duration scheduleWindow = Duration(hours: 48);
        final tz.TZDateTime scheduleUntil = now.add(scheduleWindow);

        print("[Scheduling] Calculating doses for '$medName' ($docId) until $scheduleUntil");

        List<tz.TZDateTime> nextDoseTimes = _calculateNextDoseTimes(
            now: now,
            scheduleUntil: scheduleUntil,
            startDate: startDate,
            endDate: endDate,
            frequencyType: frequencyType,
            timesRaw: timesRaw);

        print("[Scheduling] Found ${nextDoseTimes.length} potential dose times for '$medName' ($docId) in the window.");

        for (tz.TZDateTime doseTime in nextDoseTimes) {
          // Ensure generateNotificationId is available in AlarmNotificationHelper
          final notificationId = AlarmNotificationHelper.generateNotificationId(docId, doseTime.toUtc());

          print("[Scheduling] Attempting to schedule '$medName' (ID: $notificationId) for $doseTime (Local)");

          try {
            // Ensure scheduleAlarmNotification is available and takes 'id'
            await AlarmNotificationHelper.scheduleAlarmNotification(
              id: notificationId,
              title: "💊 تذكير بجرعة دواء",
              body: "حان الآن موعد تناول جرعة دواء '$medName'.",
              scheduledTime: doseTime.toLocal(), // Pass local time for scheduling
              medicationId: docId,
            );
            scheduledCount++; // Increment counter
            print("[Scheduling] Successfully scheduled/updated notification ID $notificationId for $docId at $doseTime");

            // Store all upcoming doses for processing, not just today's doses
            if (doseTime.isAfter(now)) {
              upcomingDoses.add({'docId': docId, 'time': doseTime});
            }
          } catch (e) {
            print("[Scheduling] ERROR scheduling notification ID $notificationId for $docId: $e");
          }
        }
      }

      print("[Scheduling] Total notifications scheduled/updated in this run: $scheduledCount");

      final prefs = await SharedPreferences.getInstance();

      // Filter doses to only include today's doses for display purposes
      List<Map<String, dynamic>> todayDoses = upcomingDoses
          .where((dose) {
        final doseTime = dose['time'] as tz.TZDateTime;
        return doseTime.isAfter(now) &&
            doseTime.isAfter(todayStart) &&
            doseTime.isBefore(tomorrowStart);
      }).toList();

      print("[Scheduling] Found ${todayDoses.length} doses for today out of ${upcomingDoses.length} total upcoming doses");

      if (todayDoses.isNotEmpty) {
        // Sort today's doses to find the closest one
        todayDoses.sort((a, b) => (a['time'] as tz.TZDateTime).compareTo(b['time'] as tz.TZDateTime));
        final nextDose = todayDoses.first;
        final nextDoseTime = nextDose['time'] as tz.TZDateTime;
        final nextDoseDocId = nextDose['docId'] as String;

        await prefs.setString(PREF_NEXT_DOSE_DOC_ID, nextDoseDocId);
        await prefs.setString(PREF_NEXT_DOSE_TIME_ISO, nextDoseTime.toUtc().toIso8601String());
        print("[Scheduling] Next dose for today stored for confirmation: $nextDoseDocId at $nextDoseTime (Local)");
      } else {
        // No doses for today, clear stored next dose
        await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
        await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
        print("[Scheduling] No upcoming doses found for today.");
      }

    } catch (e) {
      print("[Scheduling] ERROR fetching or processing medications: $e");
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
      await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
    }
    print("[Scheduling] Scheduling process finished.");
  }

  List<tz.TZDateTime> _calculateNextDoseTimes({
    required tz.TZDateTime now,
    required tz.TZDateTime scheduleUntil,
    required tz.TZDateTime startDate,
    tz.TZDateTime? endDate,
    required String frequencyType,
    required List<dynamic> timesRaw,
  }) {
    List<tz.TZDateTime> doseTimes = [];
    final tz.Location local = tz.local;

    List<TimeOfDay> parsedTimesOfDay = [];
    List<int>? weeklyDays;

    if (frequencyType == 'اسبوعي') {
      weeklyDays = [];
      for (var entry in timesRaw) {
        if (entry is Map<String, dynamic>) {
          String? timeStr = entry['time']?.toString();
          int? day = int.tryParse(entry['day']?.toString() ?? '');
          if (timeStr != null && day != null) {
            final parsedTod = _parseTime(timeStr);
            if (parsedTod != null) {
              if (!parsedTimesOfDay.any((t) => t.hour == parsedTod.hour && t.minute == parsedTod.minute)) {
                parsedTimesOfDay.add(parsedTod);
              }
              if (!weeklyDays.contains(day)) {
                weeklyDays.add(day);
              }
            }
          }
        }
      }
    } else {
      for (var timeEntry in timesRaw) {
        String? timeStr;
        if (timeEntry is String) {
          timeStr = timeEntry;
        } else if (timeEntry is Map<String, dynamic> && timeEntry['time'] is String) {
          timeStr = timeEntry['time'];
        }
        if (timeStr != null) {
          final parsedTod = _parseTime(timeStr);
          if (parsedTod != null && !parsedTimesOfDay.any((t) => t.hour == parsedTod.hour && t.minute == parsedTod.minute)) {
            parsedTimesOfDay.add(parsedTod);
          }
        }
      }
    }

    if (parsedTimesOfDay.isEmpty) return [];

    tz.TZDateTime currentDay = tz.TZDateTime(local, now.year, now.month, now.day);
    final tz.TZDateTime startDayFloor = tz.TZDateTime(local, startDate.year, startDate.month, startDate.day);
    if(currentDay.isBefore(startDayFloor)){
      currentDay = startDayFloor;
    }

    int safetyBreak = 0;
    const int maxDaysToCheck = 5;

    while (currentDay.isBefore(scheduleUntil) && safetyBreak < maxDaysToCheck) {
      safetyBreak++;

      if (endDate != null) {
        final tz.TZDateTime endDayFloor = tz.TZDateTime(local, endDate.year, endDate.month, endDate.day);
        if(currentDay.isAfter(endDayFloor)) break;
      }

      bool checkThisDay = false;
      if (frequencyType == 'اسبوعي') {
        if (weeklyDays != null && weeklyDays.contains(currentDay.weekday)) {
          checkThisDay = true;
        }
      } else {
        checkThisDay = true;
      }

      if (checkThisDay) {
        for (TimeOfDay tod in parsedTimesOfDay) {
          tz.TZDateTime potentialDoseTime = tz.TZDateTime(
              local, currentDay.year, currentDay.month, currentDay.day, tod.hour, tod.minute);

          if (potentialDoseTime.isAfter(now) &&
              potentialDoseTime.isBefore(scheduleUntil) &&
              (endDate == null || potentialDoseTime.isBefore(endDate))
          )
          {
            doseTimes.add(potentialDoseTime);
          }
        }
      }
      currentDay = currentDay.add(const Duration(days: 1));
    }

    if (safetyBreak >= maxDaysToCheck) {
      print("[Scheduling Calc] Warning: Reached max days to check ($maxDaysToCheck).");
    }

    doseTimes = doseTimes.toSet().toList();
    doseTimes.sort();
    return doseTimes;
  }

  Future<void> _checkAndShowConfirmationIfNeeded() async {
    if (!mounted || !_isAuthenticated) return;
    print("[Confirmation] Checking for needed confirmation...");

    final prefs = await SharedPreferences.getInstance();
    final nextDoseDocId = prefs.getString(PREF_NEXT_DOSE_DOC_ID);
    final nextDoseTimeIso = prefs.getString(PREF_NEXT_DOSE_TIME_ISO);

    bool shouldNavigate = false;
    String confirmationKey = '';
    String? timeIsoForNav;

    if (nextDoseDocId != null && nextDoseTimeIso != null) {
      try {
        final DateTime nextDoseTimeUTC = DateTime.parse(nextDoseTimeIso);
        final tz.TZDateTime nextDoseTimeLocal = tz.TZDateTime.from(nextDoseTimeUTC, tz.local);
        final tz.TZDateTime nowLocal = tz.TZDateTime.now(tz.local);

        print("[Confirmation] Found stored next dose: $nextDoseDocId at $nextDoseTimeLocal (Local)");
        print("[Confirmation] Current time: $nowLocal (Local)");

        if (nowLocal.isAfter(nextDoseTimeLocal)) {
          print("[Confirmation] Stored dose time has passed.");
          confirmationKey = '${PREF_CONFIRMATION_SHOWN_PREFIX}${nextDoseDocId}_${nextDoseTimeIso}';
          final bool alreadyShown = prefs.getBool(confirmationKey) ?? false;

          if (!alreadyShown) {
            print("[Confirmation] Confirmation not shown yet. Preparing to navigate.");
            shouldNavigate = true;
            timeIsoForNav = nextDoseTimeIso;
          } else {
            print("[Confirmation] Confirmation already shown for this dose ($confirmationKey).");
          }
        } else {
          print("[Confirmation] Stored dose time is still in the future.");
        }
      } catch (e) {
        print("[Confirmation] Error parsing stored dose time '$nextDoseTimeIso': $e");
        await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
        await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
      }
    } else {
      print("[Confirmation] No next dose info found in SharedPreferences.");
    }

    if (shouldNavigate && nextDoseDocId != null && confirmationKey.isNotEmpty && timeIsoForNav != null) {
      await prefs.setBool(confirmationKey, true);
      print("[Confirmation] Marked $confirmationKey as shown.");

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          print("[Confirmation] Navigating to details page for confirmation: $nextDoseDocId");
          Navigator.of(context).pushNamed(
            '/medication_detail',
            arguments: {
              'docId': nextDoseDocId,
              'needsConfirmation': true,
              'confirmationTimeIso': timeIsoForNav,
              'confirmationKey': confirmationKey,
            },
          ).then((result) {
            print("[Confirmation] Returned from MedicationDetailPage. Result: $result");
            if (result == true && mounted) {
              print("[Confirmation] Re-scheduling alarms after confirmation/reschedule.");
              if (_currentUser != null) {
                setState(() => _isLoadingMed = true);
                _loadUserDataAndSchedule();
              }
            } else if (mounted) {
              print("[Confirmation] No action taken on detail page or returned false.");
            }
          });
        }
      });
    } else if (mounted) {
      print("[Confirmation] No navigation needed.");
    }
  }

  Future<void> _loadUserName() async {
    if (!mounted || !_isAuthenticated || _currentUser == null) return;
    print("[DataLoad] Loading username...");
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .get();

      String fetchedName = 'مستخدم';
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        fetchedName = data['username'] as String? ?? 'مستخدم';
      }
      print("[DataLoad] Username fetched: $fetchedName");
      if (mounted) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', fetchedName);
        setState(() { _userName = fetchedName; });
      }
    } catch (e) {
      print("[DataLoad] Error loading username: $e");
      if (mounted) { setState(() => _userName = 'مستخدم'); }
    }
  }

  Future<void> _loadClosestMedDisplayData() async {
    if (!mounted || !_isAuthenticated || _currentUser == null) {
      if(mounted) setState(() => _isLoadingMed = false);
      return;
    }
    print("[DataLoad] Loading closest med display data...");

    final prefs = await SharedPreferences.getInstance();
    final nextDocId = prefs.getString(PREF_NEXT_DOSE_DOC_ID);
    final nextTimeIso = prefs.getString(PREF_NEXT_DOSE_TIME_ISO);

    String displayMedName = '';
    String displayMedTime = '';

    if (nextDocId != null && nextTimeIso != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('medicines')
            .doc(nextDocId)
            .get();

        if (doc.exists) {
          displayMedName = doc.data()?['name'] as String? ?? 'دواء غير مسمى';
        } else {
          displayMedName = 'الدواء غير موجود';
          print("[DataLoad] Warning: Medication doc $nextDocId not found for display.");
        }

        final nextTimeUTC = DateTime.parse(nextTimeIso);
        final nextTimeLocal = tz.TZDateTime.from(nextTimeUTC, tz.local);
        displayMedTime = _formatTimeOfDay(context, TimeOfDay.fromDateTime(nextTimeLocal));
        print("[DataLoad] Display data: $displayMedName at $displayMedTime");

      } catch (e) {
        print("[DataLoad] Error fetching display data for closest med $nextDocId: $e");
        displayMedName = '';
        displayMedTime = 'خطأ';
      }
    } else {
      print("[DataLoad] No stored next dose info found for display.");
    }

    if (mounted) {
      setState(() {
        _closestMedName = displayMedName;
        _closestMedTimeStr = displayMedTime;
        _closestMedDocId = nextDocId ?? '';
        _isLoadingMed = false;
      });
    }
  }

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

  String _formatTimeOfDay(BuildContext context, TimeOfDay time) {
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }

  Future<String?> _getRandomMedicationId() async {
    if (!_isAuthenticated || _currentUser == null) return null;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('medicines')
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
    } catch (e) {
      print('Error getting random medication ID: $e');
      return null;
    }
  }

  Future<void> _triggerTestNotification(BuildContext context) async {
    if (!mounted || !_isAuthenticated) {
      _showLoginRequiredDialog("اختبار الإشعارات");
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("جاري إرسال إشعار اختباري...", textAlign: TextAlign.right),
        backgroundColor: Colors.blueGrey,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Use a simple ID for test notifications
      final testId = DateTime.now().millisecondsSinceEpoch % 100000;
      final testPayload = DateTime.now().millisecondsSinceEpoch.toString();

      debugPrint("Showing immediate test notification with ID: $testId");
      
      // Show immediate notification for testing
      await AlarmNotificationHelper.scheduleAlarmNotification(
        id: testId,
        title: "🔔 اختبار إشعار مُذكر",
        body: "هذا إشعار اختباري للتحقق من عمل النظام.",
        scheduledTime: DateTime.now(), // Send immediately
        medicationId: testPayload,
      );
      
      debugPrint("Test notification request sent successfully");
    } catch (e) {
      debugPrint("Error scheduling test notification: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("فشل إرسال الإشعار الاختباري: $e", textAlign: TextAlign.right),
            backgroundColor: kErrorColor,
          ),
        );
      }
    }
  }

  Future<void> _triggerCompanionTestNotification(BuildContext context) async {
    if (!mounted || !_isAuthenticated) {
      _showLoginRequiredDialog("اختبار إشعار مرافق");
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("جاري إرسال إشعار اختباري للمرافق...", textAlign: TextAlign.right),
        backgroundColor: Colors.blueGrey,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final testId = DateTime.now().millisecondsSinceEpoch % 100000;
      
      debugPrint("Showing immediate companion test notification with ID: $testId");
      
      await AlarmNotificationHelper.scheduleAlarmNotification(
        id: testId,
        title: "💊 تذكير جرعة مرافق (اختبار)",
        body: "هذا إشعار اختباري لجرعة مرافق.",
        scheduledTime: DateTime.now(), // Show immediately
        medicationId: "test_companion",
        isCompanionCheck: true,
      );
      
      debugPrint("Companion test notification sent successfully");
    } catch (e) {
      debugPrint("Error scheduling companion test notification: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("فشل إرسال إشعار المرافق: $e", textAlign: TextAlign.right),
            backgroundColor: kErrorColor,
          ),
        );
      }
    }
  }

  Future<void> _testMedicationDetailNavigation(BuildContext context) async {
    if (!mounted || !_isAuthenticated) {
      _showLoginRequiredDialog("اختبار تفاصيل الدواء");
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator(color: kPrimaryColor)),
    );

    try {
      final medicationId = await _getRandomMedicationId();
      Navigator.pop(context);

      if (medicationId != null) {
        Navigator.pushNamed(
          context,
          '/medication_detail',
          arguments: {'docId': medicationId},
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("لم يتم العثور على دواء لاختبار التفاصيل.", textAlign: TextAlign.right), backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e) {
      Navigator.pop(context);
      print("Error testing medication detail navigation: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("حدث خطأ أثناء الاختبار.", textAlign: TextAlign.right), backgroundColor: kErrorColor),
        );
      }
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index && index == 0) {
      if (_isAuthenticated && _currentUser != null && !_isLoadingMed) {
        print("[Navigation] Home tapped again, refreshing...");
        setState(() => _isLoadingMed = true );
        _loadUserDataAndSchedule();
      }
      return;
    }

    if (!_isAuthenticated && index != 0) {
      _showLoginRequiredDialog();
      return;
    }

    String? routeName;

    switch (index) {
      case 0:
        if (ModalRoute.of(context)?.settings.name != '/') {
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        }
        if (mounted) setState(() { _selectedIndex = index; });
        break;
      case 1:
        routeName = "/personal_data";
        break;
      case 2:
        routeName = "/settings";
        break;
      default:
        return;
    }

    if (routeName != null) {
      if (mounted) setState(() { _selectedIndex = index; });
      Navigator.pushNamed(context, routeName).then((_) {
        if (mounted) {
          setState(() { _selectedIndex = 0; });
          if(_isAuthenticated && _currentUser != null) {
            _loadClosestMedDisplayData();
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = _getGreeting(now.hour);

    if (_isInitializing) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor,kPrimaryColor.withOpacity(0.8),kBackgroundColor.withOpacity(0.9),kBackgroundColor,],
              begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0.0, 0.3, 0.7, 1.0],
            ),
          ),
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      );
    }

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor,kPrimaryColor.withOpacity(0.8),kBackgroundColor.withOpacity(0.9),kBackgroundColor,],
              begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0.0, 0.3, 0.7, 1.0],
            ),
          ),
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                if (_isAuthenticated && _currentUser != null) {
                  print("[Refresh] User triggered refresh.");
                  setState(() => _isLoadingMed = true);
                  await _loadUserDataAndSchedule();
                }
              },
              color: kPrimaryColor,
              child: FadeTransition(
                opacity: _fadeInAnimation,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _isAuthenticated
                                  ? "$greeting، ${_userName.isNotEmpty ? _userName : '...'}"
                                  : "$greeting، زائر",
                              style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white,
                                shadows: [ Shadow(offset: Offset(0, 1), blurRadius: 2.0, color: Colors.black.withOpacity(0.3)) ],
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.7),
                        padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
                          boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, -5)) ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _isAuthenticated ? _buildUpcomingDoseSection() : _buildLoginSection(),
                            SizedBox(height: 25),
                            _buildActionCardsSection(),
                            SizedBox(height: 30),
                            if (_isAuthenticated && true) // Replace 'true' with kDebugMode or env check
                              _buildDevelopmentToolsSection(),
                            SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: Directionality(
          textDirection: ui.TextDirection.ltr,
          child: CustomBottomNavigationBar(
            selectedIndex: _selectedIndex,
            onItemTapped: _onItemTapped,
          ),
        ),
      ),
    );
  }

  String _getGreeting(int hour) {
    if (hour >= 4 && hour < 12) return "صباح الخير";
    if (hour >= 12 && hour < 17) return "مساء الخير";
    return "مساء الخير";
  }

  Widget _buildLoginSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor.withOpacity(0.1), Colors.blue.shade50.withOpacity(0.5)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(kBorderRadius),
            border: Border.all(color: kPrimaryColor.withOpacity(0.2), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("مرحباً بك في تطبيق مُذكر", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimaryColor)),
              SizedBox(height: 10),
              Text("سجل الدخول للوصول إلى ميزات التطبيق الكاملة وإدارة أدويتك.", style: TextStyle(fontSize: 14, color: Colors.black87, height: 1.4)),
              SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/register'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, foregroundColor: kPrimaryColor, elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: kPrimaryColor)),
                      ),
                      child: Text("إنشاء حساب"),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor, foregroundColor: Colors.white, elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text("تسجيل الدخول"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 30),
        Text("استكشف الميزات", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildUpcomingDoseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text("الجرعة القادمة", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        _isLoadingMed
            ? _buildLoadingIndicator()
            : _closestMedName.isEmpty
            ? _buildEmptyDoseIndicator()
            : DoseTile(
          medicationName: _closestMedName,
          nextDose: _closestMedTimeStr,
          docId: _closestMedDocId,
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: kPrimaryColor.withOpacity(0.1)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor)),
            SizedBox(height: 10),
            Text("جاري تحميل الجرعة...", style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDoseIndicator() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 25, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.medication_liquid_outlined, size: 40, color: kSecondaryColor),
            SizedBox(height: 10),
            Text("لا توجد جرعات قادمة لليوم", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey.shade700), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCardsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text("الإجراءات السريعة", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ),
        Row(
          children: [
            Expanded(
              child: EnhancedActionCard(
                icon: Icons.add_circle_outline, label: "إضافة دواء", color: Colors.green.shade600,
                onTap: () {
                  if (_isAuthenticated) {
                    Navigator.pushNamed(context, '/add_dose').then((_) {
                      if (mounted && _currentUser != null) {
                        setState(() => _isLoadingMed = true);
                        _loadUserDataAndSchedule();
                      }
                    });
                  } else { _showLoginRequiredDialog("إضافة دواء"); }
                },
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: EnhancedActionCard(
                icon: Icons.calendar_today_rounded, label: "جدول الأدوية", color: kPrimaryColor,
                onTap: () {
                  if (_isAuthenticated) {
                    Navigator.pushNamed(context, '/dose_schedule').then((_){
                      if (mounted && _currentUser != null) {
                        setState(() => _isLoadingMed = true);
                        _loadUserDataAndSchedule();
                      }
                    });
                  } else { _showLoginRequiredDialog("جدول الأدوية"); }
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        EnhancedActionCard(
          icon: Icons.people_alt_rounded, label: "المرافقين", description: "إدارة ومتابعة حالة المرافقين.", color: Colors.orange.shade700, isHorizontal: true,
          onTap: () {
            if (_isAuthenticated) { Navigator.pushNamed(context, '/companions'); }
            else { _showLoginRequiredDialog("المرافقين"); }
          },
        ),
      ],
    );
  }

  Widget _buildDevelopmentToolsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("أدوات المطور (للاختبار)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
              SizedBox(width: 8),
              Icon(Icons.developer_mode, size: 20, color: Colors.grey.shade800),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _triggerTestNotification(context),
                  icon: Icon(Icons.notifications_active_outlined, size: 18),
                  label: Text("اختبار إشعار", style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade600, foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _triggerCompanionTestNotification(context),
                  icon: Icon(Icons.people, size: 18),
                  label: Text("اختبار مرافق", style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _testMedicationDetailNavigation(context),
                  icon: Icon(Icons.medication_liquid_rounded, size: 18),
                  label: Text("تفاصيل تجريبية", style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLoginRequiredDialog([String? featureName]) {
    if (!mounted) return;

    String message = featureName != null
        ? 'يجب تسجيل الدخول للوصول إلى ميزة "$featureName".'
        : 'يجب تسجيل الدخول للمتابعة.';

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('تسجيل الدخول مطلوب', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(width: 8),
              Icon(Icons.login_rounded, color: kPrimaryColor),
            ],
          ),
          content: Text(message, textAlign: TextAlign.right),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kBorderRadius)),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: <Widget>[
            TextButton(
              child: Text('إلغاء', style: TextStyle(color: Colors.grey.shade700)),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.login_rounded, size: 18),
              label: Text('تسجيل الدخول'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ],
        );
      },
    );
  }
}

class DoseTile extends StatelessWidget {
  final String medicationName;
  final String nextDose;
  final String docId;

  const DoseTile({
    super.key,
    required this.medicationName,
    required this.nextDose,
    required this.docId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [ BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: Offset(0, 2)) ],
        border: Border.all(color: kPrimaryColor.withOpacity(0.2), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kBorderRadius),
        child: InkWell(
          // Remove tap handler to disable navigation
          splashColor: kPrimaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(kBorderRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(medicationName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87), overflow: TextOverflow.ellipsis, maxLines: 1),
                      SizedBox(height: 6),
                      _buildTimeDisplay(),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                _buildMedicationIcon(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMedicationIcon() {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: kPrimaryColor.withOpacity(0.2), blurRadius: 8, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Icon(Icons.medication_liquid_rounded, size: 32, color: Colors.white),
    );
  }

  Widget _buildTimeDisplay() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: kSecondaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kSecondaryColor.withOpacity(0.3), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(nextDose, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kPrimaryColor)),
              SizedBox(width: 4),
              Icon(Icons.access_time_filled_rounded, size: 14, color: kPrimaryColor),
            ],
          ),
        ),
      ],
    );
  }
}

class EnhancedActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final Color color;
  final VoidCallback onTap;
  final bool isHorizontal;

  const EnhancedActionCard({
    super.key,
    required this.icon,
    required this.label,
    this.description,
    required this.color,
    required this.onTap,
    this.isHorizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kBorderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kBorderRadius),
          onTap: onTap,
          splashColor: color.withOpacity(0.1),
          highlightColor: color.withOpacity(0.05),
          child: Padding(
            padding: isHorizontal
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                : const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: isHorizontal ? _buildHorizontalLayout() : _buildVerticalLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 32),
        ),
        SizedBox(height: 12),
        Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.withOpacity(0.9)), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildHorizontalLayout() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color.withOpacity(0.9)), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (description != null && description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(description!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
        SizedBox(width: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 28),
        ),
      ],
    );
  }
}


