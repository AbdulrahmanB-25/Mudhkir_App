import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:ui' as ui;
import 'package:mudhkir_app/Features/Companions/companion_medication_tracker.dart';
import '../../Core/Services/AlarmNotificationHelper.dart';
import '../../Shared/Widgets/bottom_navigation.dart';
import '../../main.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

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
  bool _isLoadingMed = true;
  bool _isInitializing = true;
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  bool _isAuthenticated = false;
  User? _currentUser;
  final tz.Location utcPlus3Location = tz.getLocation('Asia/Riyadh'); // Get the UTC+3 location (Saudi Arabia timezone)

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

    // Complete the notification initialization with context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AlarmNotificationHelper.completeInitialization(context);
      }
    });

    FirebaseAuth.instance.authStateChanges().listen((user) {
      _handleAuthStateChange(user);
    });
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
    if (!mounted) {
      return;
    }

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
    if (!mounted || !_isAuthenticated || _currentUser == null) {
      if (mounted) setState(() => _isLoadingMed = false);
      return;
    }

    if (!_isLoadingMed && mounted) {
      setState(() => _isLoadingMed = true);
    }

    await _loadUserName();
    await _scheduleAllUserMedications(_currentUser!.uid);
    await CompanionMedicationTracker.fetchAndScheduleCompanionMedications();
    
    // Also ensure periodic checks are set up
    await setupPeriodicCompanionChecks();
    
    await _loadClosestMedDisplayData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _scheduleAllUserMedications(String userId) async {
    if (!mounted) {
      return;
    }

    try {
      await AlarmNotificationHelper.ensureChannelsSetup();
    } catch (e) {
      print("[Scheduling] ERROR ensuring notification channels setup: $e");
    }

    await AlarmNotificationHelper.cancelAllNotifications();

    List<Map<String, dynamic>> upcomingDoses = [];
    int scheduledCount = 0;

    try {
      final medsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .get();

      // Use UTC+3 timezone location
      final tz.TZDateTime now = tz.TZDateTime.now(utcPlus3Location);

      print("[Scheduling] Current time in UTC+3: ${now.toString()}");

      for (var doc in medsSnapshot.docs) {
        final data = doc.data();
        final docId = doc.id;
        final medName = data['name'] as String? ?? 'دواء غير مسمى';
        final startTimestamp = data['startDate'] as Timestamp?;
        final endTimestamp = data['endDate'] as Timestamp?;

        if (startTimestamp == null) {
          continue;
        }

        // Convert timestamps to UTC+3 times
        final tz.TZDateTime startDate = tz.TZDateTime.from(startTimestamp.toDate(), utcPlus3Location);
        final tz.TZDateTime? endDate = endTimestamp != null ? tz.TZDateTime.from(endTimestamp.toDate(), utcPlus3Location) : null;

        // Date-only comparisons using UTC+3 timezone
        final tz.TZDateTime todayFloor = tz.TZDateTime(utcPlus3Location, now.year, now.month, now.day);
        final tz.TZDateTime startDayFloor = tz.TZDateTime(utcPlus3Location, startDate.year, startDate.month, startDate.day);

        if (todayFloor.isBefore(startDayFloor)) {
          continue;
        }
        if (endDate != null) {
          final tz.TZDateTime endDayFloor = tz.TZDateTime(utcPlus3Location, endDate.year, endDate.month, endDate.day);
          if (todayFloor.isAfter(endDayFloor)) {
            continue;
          }
        }

        final frequencyType = data['frequencyType'] as String? ?? 'يومي';
        final List<dynamic> timesRaw = data['times'] ?? [];

        final Duration scheduleWindow = Duration(hours: 48);
        final tz.TZDateTime scheduleUntil = now.add(scheduleWindow);

        List<tz.TZDateTime> nextDoseTimes = _calculateNextDoseTimes(
            now: now,
            scheduleUntil: scheduleUntil,
            startDate: startDate,
            endDate: endDate,
            frequencyType: frequencyType,
            timesRaw: timesRaw);

        for (tz.TZDateTime doseTime in nextDoseTimes) {
          final notificationId = AlarmNotificationHelper.generateNotificationId(docId, doseTime);

          try {
            print("[Scheduling] Scheduling notification for med '$medName' at ${doseTime.toString()} (UTC+3)");
            await AlarmNotificationHelper.scheduleAlarmNotification(
              id: notificationId,
              title: "💊 تذكير بجرعة دواء",
              body: "حان الآن موعد تناول جرعة دواء '$medName'.",
              scheduledTime: doseTime,
              medicationId: docId,
              isCompanionCheck: false,
            );
            scheduledCount++;

            if (doseTime.isAfter(now)) {
              upcomingDoses.add({'docId': docId, 'time': doseTime});
            }
          } catch (e) {
            print("[Scheduling] ERROR scheduling notification ID $notificationId for $docId: $e");
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();

      if (upcomingDoses.isNotEmpty) {
        upcomingDoses.sort((a, b) => (a['time'] as tz.TZDateTime).compareTo(b['time'] as tz.TZDateTime));

        final absoluteNextDose = upcomingDoses.first;
        final absoluteNextDoseTime = absoluteNextDose['time'] as tz.TZDateTime;
        final absoluteNextDoseDocId = absoluteNextDose['docId'] as String;

        print("[Scheduling] Storing next dose: ${absoluteNextDoseTime.toString()} (UTC+3) for med $absoluteNextDoseDocId");

        // Store the time in ISO format but with explicit timezone info
        await prefs.setString(PREF_NEXT_DOSE_DOC_ID, absoluteNextDoseDocId);
        await prefs.setString(PREF_NEXT_DOSE_TIME_ISO, absoluteNextDoseTime.toString());

      } else {
        await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
        await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
      }

    } catch (e) {
      print("[Scheduling] ERROR fetching or processing medications: $e");
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
      await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
    }
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

    // Use UTC+3 for all date calculations
    tz.TZDateTime currentDay = tz.TZDateTime(utcPlus3Location, now.year, now.month, now.day);
    final tz.TZDateTime startDayFloor = tz.TZDateTime(utcPlus3Location, startDate.year, startDate.month, startDate.day);

    if(currentDay.isBefore(startDayFloor)){
      currentDay = startDayFloor;
    }

    int safetyBreak = 0;
    const int maxDaysToCheck = 7;

    while (currentDay.isBefore(scheduleUntil) && safetyBreak < maxDaysToCheck) {
      safetyBreak++;

      if (endDate != null) {
        final tz.TZDateTime endDayFloor = tz.TZDateTime(utcPlus3Location, endDate.year, endDate.month, endDate.day);
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
          // Create the potential dose time in UTC+3
          tz.TZDateTime potentialDoseTime = tz.TZDateTime(
              utcPlus3Location, currentDay.year, currentDay.month, currentDay.day, tod.hour, tod.minute);

          // Compare using UTC+3 time
          if (potentialDoseTime.isAfter(now) && potentialDoseTime.isBefore(scheduleUntil)) {
            if (endDate == null || potentialDoseTime.isBefore(endDate)) {
              doseTimes.add(potentialDoseTime);
            }
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
    if (!mounted || !_isAuthenticated) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final nextDoseDocId = prefs.getString(PREF_NEXT_DOSE_DOC_ID);
    final nextDoseTimeIso = prefs.getString(PREF_NEXT_DOSE_TIME_ISO);

    bool shouldNavigate = false;
    String confirmationKey = '';
    String? timeIsoForNav;

    final DateFormat logTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss ZZZZ', 'en_US');

    if (nextDoseDocId != null && nextDoseTimeIso != null) {
      try {
        // Parse the stored time with timezone awareness (should be in UTC+3 format)
        tz.TZDateTime nextDoseTimeLocal;

        try {
          // Try parsing as stored TZDateTime string (new format)
          nextDoseTimeLocal = tz.TZDateTime.parse(utcPlus3Location, nextDoseTimeIso);
        } catch (_) {
          // Fall back to parsing as UTC ISO string (old format)
          final DateTime nextDoseTimeUTC = DateTime.parse(nextDoseTimeIso);
          nextDoseTimeLocal = tz.TZDateTime.from(nextDoseTimeUTC, utcPlus3Location);
        }

        // Get current time in UTC+3
        final tz.TZDateTime nowLocal = tz.TZDateTime.now(utcPlus3Location);

        print("[Confirmation] Now (UTC+3): ${logTimeFormat.format(nowLocal)} vs Next Dose (UTC+3): ${logTimeFormat.format(nextDoseTimeLocal)}");

        if (nowLocal.isAfter(nextDoseTimeLocal)) {
          confirmationKey = '${PREF_CONFIRMATION_SHOWN_PREFIX}${nextDoseDocId}_${nextDoseTimeIso}';
          final bool alreadyShown = prefs.getBool(confirmationKey) ?? false;

          if (!alreadyShown) {
            shouldNavigate = true;
            timeIsoForNav = nextDoseTimeIso;
          }
        }
      } catch (e) {
        print("[Confirmation] Error parsing stored dose time '$nextDoseTimeIso': $e");
        await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
        await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
      }
    }

    if (shouldNavigate && nextDoseDocId != null && confirmationKey.isNotEmpty && timeIsoForNav != null) {
      await prefs.setBool(confirmationKey, true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamed(
            '/medication_detail',
            arguments: {
              'docId': nextDoseDocId,
              'needsConfirmation': true,
              'confirmationTimeIso': timeIsoForNav,
              'confirmationKey': confirmationKey,
            },
          ).then((result) {
            if (result == true && mounted) {
              if (_currentUser != null) {
                setState(() => _isLoadingMed = true);
                _loadUserDataAndSchedule();
              }
            } else if (mounted) {
              _loadClosestMedDisplayData();
            }
          });
        }
      });
    }
  }

  Future<void> _loadUserName() async {
    if (!mounted || !_isAuthenticated || _currentUser == null) {
      return;
    }
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
      if (mounted) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', fetchedName);
        setState(() { _userName = fetchedName; });
      }
    } catch (e) {
      print("[DataLoad User] Error loading username: $e");
      if (mounted) { setState(() => _userName = 'مستخدم'); }
    }
  }

  Future<void> _loadClosestMedDisplayData() async {
    if (!mounted || !_isAuthenticated || _currentUser == null) {
      if (mounted) {
        setState(() => _isLoadingMed = false);
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final nextDocId = prefs.getString(PREF_NEXT_DOSE_DOC_ID);
    final nextTimeIso = prefs.getString(PREF_NEXT_DOSE_TIME_ISO);

    String displayMedName = '';
    String displayMedTime = '';
    String displayDocId = '';

    final DateFormat logTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss ZZZZ', 'en_US');

    if (nextDocId != null && nextTimeIso != null) {
      try {
        // Parse the time with UTC+3 timezone awareness
        tz.TZDateTime nextTimeLocal;

        try {
          // Try parsing as stored TZDateTime string (new format)
          nextTimeLocal = tz.TZDateTime.parse(utcPlus3Location, nextTimeIso);
        } catch (_) {
          // Fall back to parsing as UTC ISO string (old format)
          final DateTime nextTimeUTC = DateTime.parse(nextTimeIso);
          nextTimeLocal = tz.TZDateTime.from(nextTimeUTC, utcPlus3Location);
        }

        // Get current time in UTC+3
        final tz.TZDateTime nowLocal = tz.TZDateTime.now(utcPlus3Location);

        // Get DateTime objects for today and tomorrow in UTC+3 for comparison
        final DateTime todayDate = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
        final DateTime medicationDate = DateTime(nextTimeLocal.year, nextTimeLocal.month, nextTimeLocal.day);
        final DateTime tomorrowDate = todayDate.add(const Duration(days: 1));

        print("[DataLoad Display] Now (UTC+3): ${logTimeFormat.format(nowLocal)}");
        print("[DataLoad Display] Next Dose (UTC+3): ${logTimeFormat.format(nextTimeLocal)}");
        print("[DataLoad Display] Today: $todayDate, Next Dose Day: $medicationDate, Tomorrow: $tomorrowDate");

        // Check if the dose time has passed
        if (nowLocal.isAfter(nextTimeLocal)) {
          print("[DataLoad Display] Medication time has passed, clearing data");
          await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
          await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
          displayMedName = '';
          displayMedTime = '';
          displayDocId = '';
        } else {
          // Time is in the future - fetch and display the medication
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(_currentUser!.uid)
              .collection('medicines')
              .doc(nextDocId)
              .get();

          if (doc.exists) {
            displayMedName = doc.data()?['name'] as String? ?? 'دواء غير مسمى';
            displayDocId = nextDocId;

            // Format the time with proper UTC+3 timezone awareness
            displayMedTime = _formatTimeWithDate(nextTimeLocal);

            print("[DataLoad Display] Medicine found: $displayMedName, Formatted time: $displayMedTime");
          } else {
            print("[DataLoad Display] Medicine document not found, clearing data");
            displayMedName = '';
            await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
            await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
          }
        }
      } catch (e, stackTrace) {
        print("[DataLoad Display] Error processing display data: $e");
        print("[DataLoad Display] Stack trace: $stackTrace");
        displayMedName = '';
        displayMedTime = 'خطأ';
        displayDocId = '';
        await prefs.remove(PREF_NEXT_DOSE_DOC_ID);
        await prefs.remove(PREF_NEXT_DOSE_TIME_ISO);
      }
    } else {
      displayMedName = '';
      displayMedTime = '';
      displayDocId = '';
    }

    if (mounted) {
      setState(() {
        _closestMedName = displayMedName;
        _closestMedTimeStr = displayMedTime;
        _closestMedDocId = displayDocId;
        _isLoadingMed = false;
      });
    }
  }

  // Format time with correct AM/PM and date if needed
  String _formatTimeWithDate(tz.TZDateTime dateTime) {
    try {
      // Get current time in UTC+3 for comparison
      final tz.TZDateTime now = tz.TZDateTime.now(utcPlus3Location);

      // Compare dates for "today", "tomorrow" or specific date display
      final bool isToday = dateTime.year == now.year &&
          dateTime.month == now.month &&
          dateTime.day == now.day;

      final bool isTomorrow = dateTime.year == now.year &&
          dateTime.month == now.month &&
          dateTime.day == (now.day + 1);

      // Format the time portion
      final TimeOfDay tod = TimeOfDay.fromDateTime(dateTime);
      final int hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
      final String minute = tod.minute.toString().padLeft(2, '0');
      final String period = tod.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
      String timeStr = '$hour:$minute $period';

      // Add appropriate date indicator if needed
      if (isTomorrow) {
        timeStr += " (غداً)";
      } else if (!isToday) {
        final DateFormat dateFormat = DateFormat('dd/MM', 'ar');
        final String formattedDate = dateFormat.format(dateTime);
        timeStr += " ($formattedDate)";
      }

      return timeStr;
    } catch (e) {
      print("[TimeFormat] Error formatting time: $e");
      // Fallback formatting
      return "${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}";
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
    if (!_isAuthenticated || _currentUser == null) {
      return null;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('medicines')
          .limit(1)
          .get();
      final id = snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
      return id;
    } catch (e) {
      print('[Util] Error getting random medication ID: $e');
      return null;
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index && index == 0) {
      if (_isAuthenticated && _currentUser != null && !_isLoadingMed) {
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
                      Container(
                        width: double.infinity,
                        height: 130,
                        child: Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              height: 170,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.blue.shade50,
                                    Colors.white.withOpacity(0.8),
                                    Colors.blue.shade100,
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(40),
                                  bottomRight: Radius.circular(40),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: kPrimaryColor.withOpacity(0.3),
                                    blurRadius: 16,
                                    offset: Offset(0, 8),
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 15,
                                    left: 25,
                                    child: Opacity(
                                      opacity: 0.1,
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 20,
                                    left: 60,
                                    child: Opacity(
                                      opacity: 0.1,
                                      child: Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        TweenAnimationBuilder(
                                          tween: Tween<double>(begin: 0, end: 1),
                                          duration: Duration(milliseconds: 800),
                                          builder: (context, value, child) {
                                            return Opacity(
                                              opacity: value,
                                              child: Transform.translate(
                                                offset: Offset(0, 20 * (1 - value)),
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: Text(
                                            _isAuthenticated ? "$greeting،" : "$greeting، زائر",
                                            style: TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.blue.shade800,
                                              shadows: [
                                                Shadow(
                                                  offset: Offset(0, 1),
                                                  blurRadius: 2.0,
                                                  color: Colors.black.withOpacity(0.1),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        TweenAnimationBuilder(
                                          tween: Tween<double>(begin: 0, end: 1),
                                          duration: Duration(milliseconds: 800),
                                          curve: Curves.easeOutCubic,
                                          builder: (context, value, child) {
                                            return Opacity(
                                              opacity: value,
                                              child: Transform.translate(
                                                offset: Offset(0, 15 * (1 - value)),
                                                child: child,
                                              ),
                                            );
                                          },
                                          child: AnimatedSwitcher(
                                            duration: Duration(milliseconds: 400),
                                            transitionBuilder: (Widget child, Animation<double> animation) {
                                              return FadeTransition(opacity: animation, child: child);
                                            },
                                            child: Text(
                                              _isAuthenticated
                                                  ? (_userName.isNotEmpty ? _userName : '...')
                                                  : "زائر",
                                              key: ValueKey(_userName),
                                              style: TextStyle(
                                                fontSize: 30,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue.shade900,
                                                height: 1.2,
                                                shadows: [
                                                  Shadow(
                                                    offset: Offset(0, 1),
                                                    blurRadius: 2.0,
                                                    color: Colors.black.withOpacity(0.15),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 40,
                                      backgroundColor: Colors.white,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.blue.shade700,
                                              Colors.blue.shade900
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        margin: EdgeInsets.all(3),
                                        child: Center(
                                          child: Icon(
                                            Icons.person_rounded,
                                            color: Colors.white,
                                            size: 50,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
    // Use Saudi Arabia's timezone for the greeting
    final utcPlus3Hour = (DateTime.now().toUtc().hour + 3) % 24;

    if (utcPlus3Hour >= 4 && utcPlus3Hour < 12) return "صباح الخير";
    if (utcPlus3Hour >= 12 && utcPlus3Hour < 17) return "مساء الخير";
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
          splashColor: kPrimaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(kBorderRadius),
          onTap: () {
          },
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
