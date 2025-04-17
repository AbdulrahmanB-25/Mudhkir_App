import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mudhkir_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mudhkir_app/Widgets/bottom_navigation.dart';


// Constants for theming
// Hospital Blue Color Theme
const Color kPrimaryColor = Color(0xFF2E86C1); // Medium hospital blue
const Color kSecondaryColor = Color(0xFF5DADE2); // Light hospital blue
const Color kErrorColor = Color(0xFFFF6B6B); // Error red
const Color kBackgroundColor = Color(0xFFF5F8FA); // Very light blue-gray background
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

// Assuming scheduleNotification is defined globally or imported correctly
// If it's in main.dart, ensure it's accessible here.
// Example placeholder if it's missing:
Future<void> scheduleNotification({required int id, required String title, required String body, required DateTime scheduledTime, required String docId}) async {
  print("Scheduling notification: $title at $scheduledTime");
  // Actual implementation needed
}


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
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  bool _isAuthenticated = false;

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
    _animationController.forward();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // Ensure context is valid before using it
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    final currentAuthStatus = user != null;

    // Only update state and navigate if auth status changed or initially loading
    if (_isAuthenticated != currentAuthStatus || _userName.isEmpty) {
      setState(() {
        _isAuthenticated = currentAuthStatus;
      });

      if (_isAuthenticated) {
        await _loadUserData(); // Load data only if authenticated
      } else {
        // Use pushReplacementNamed to prevent going back to MainPage
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ModalRoute.of(context)?.settings.name != '/welcome') {
            Navigator.of(context).pushReplacementNamed('/welcome');
          }
        });
        // Clear user-specific data when logged out
        setState(() {
          _userName = 'زائر';
          _closestMedName = '';
          _closestMedTimeStr = '';
          _closestMedDocId = '';
          _isLoadingMed = false; // Stop loading as there's no data to load
        });
      }
    }
    // Setup FCM regardless of auth state, but token handling might depend on auth
    _setupFCM();
  }


  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _setupFCM() {
    FirebaseMessaging.instance.requestPermission(); // Request permission

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground Message received: ${message.notification?.title}');
      if (message.notification != null) {
        flutterLocalNotificationsPlugin.show(
          message.notification.hashCode,
          message.notification!.title,
          message.notification!.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'medication_channel', // Ensure this matches channel in main.dart
              'Medication Reminders',
              channelDescription: 'Channel for medication reminder notifications.',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher', // Ensure this icon exists
            ),
          ),
          payload: message.data['docId'] ?? '', // Pass docId as payload
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Message clicked!');
      // Handle notification tap when app is in background/terminated
      final docId = message.data['docId'];
      if (docId != null) {
        Navigator.pushNamed(
          context,
          '/medication_detail',
          arguments: {'docId': docId},
        );
      }
      // You might want to check message.data for specific actions like 'taken' or 'reschedule'
      // if (message.data['action'] == 'taken') _markDoseAsTaken(docId);
    });
  }


  Future<void> _markDoseAsTaken(String docId) async {
    if (!_isAuthenticated || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('medicines')
          .doc(docId)
          .update({'status': 'taken'}); // Consider updating a specific dose record if applicable
      _loadClosestMed(); // Refresh the upcoming dose
    } catch (e) {
      print("Error marking dose as taken: $e");
      // Optionally show a snackbar error
    }
  }

  Future<void> _promptReschedule(String docId) async {
    if (!mounted) return;
    // Example: Show a dialog or navigate to a rescheduling screen
    print("Reschedule prompted for docId: $docId");
    // Navigator.pushNamed(context, '/reschedule_dose', arguments: {'docId': docId});
  }

  Future<void> _loadUserData() async {
    if (!mounted || !_isAuthenticated) return; // Check auth again
    await _loadUserName();
    if (mounted) { // Check mounted again after async gap
      await _loadClosestMed();
    }
  }

  Future<void> _loadUserName() async {
    if (!mounted || !_isAuthenticated) return;
    User? user = FirebaseAuth.instance.currentUser;
    // No need to check user == null again due to _isAuthenticated check

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid) // user is guaranteed non-null here
          .get();

      String fetchedName = 'مستخدم'; // Default
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        fetchedName = data['username'] as String? ?? 'مستخدم';
      }

      if (mounted) { // Check mounted before setState
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', fetchedName); // Update cache
        setState(() {
          _userName = fetchedName;
        });
      }
    } catch (e) {
      print("Error loading username: $e");
      if (mounted) { // Check mounted before setState
        setState(() => _userName = 'مستخدم'); // Fallback
      }
    }
  }


  TimeOfDay? _parseTime(String timeStr) {
    // Try parsing formats like "9:30 AM" or "14:00"
    try {
      // Handle standard AM/PM format
      final DateFormat ampmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}

    try {
      // Handle Arabic AM/PM (normalize first)
      String normalizedTime = timeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('مساءً', 'PM')
          .trim();
      final DateFormat arabicAmpmFormat = DateFormat('h:mm a', 'en_US'); // Still parse with en_US locale
      DateTime parsedDt = arabicAmpmFormat.parseStrict(normalizedTime);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}

    try {
      // Handle 24-hour format like "14:30"
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        // Allow minutes part to have extra non-numeric chars sometimes seen, like "30 "
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (_) {}

    print("Failed to parse time string: $timeStr");
    return null; // Return null if all parsing attempts fail
  }

  String _formatTimeOfDay(BuildContext context, TimeOfDay time) {
    // Format TimeOfDay to Arabic AM/PM string
    // Use MediaQuery context if available, otherwise default to 12-hour format logic
    final localizations = MaterialLocalizations.of(context);
    // Format using localizations for better adaptability if needed, or stick to manual
    // return localizations.formatTimeOfDay(time, alwaysUse24HourFormat: false);

    // Manual formatting for specific Arabic AM/PM
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod; // 0 becomes 12 for 12-hour clock
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }


  Future<void> _loadClosestMed() async {
    if (!mounted || !_isAuthenticated) return;
    setState(() { _isLoadingMed = true; });

    User? user = FirebaseAuth.instance.currentUser;
    // Already checked _isAuthenticated, so user is non-null

    List<Map<String, dynamic>> potentialDoses = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nowMinutes = now.hour * 60 + now.minute;

    try {
      final medsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid) // user is non-null
          .collection('medicines')
          .get();

      for (var doc in medsSnapshot.docs) {
        final data = doc.data();
        final medName = data['name'] as String? ?? 'دواء غير مسمى';
        final startTimestamp = data['startDate'] as Timestamp?;
        final endTimestamp = data['endDate'] as Timestamp?;

        if (startTimestamp == null) continue; // Skip if no start date

        final startDate = startTimestamp.toDate();
        final endDate = endTimestamp?.toDate();
        // Normalize dates to compare days only
        final startDay = DateTime(startDate.year, startDate.month, startDate.day);
        final endDay = endDate != null ? DateTime(endDate.year, endDate.month, endDate.day) : null;

        // Skip if medication hasn't started or has already ended
        if (today.isBefore(startDay)) continue;
        if (endDay != null && today.isAfter(endDay)) continue;

        final frequencyType = data['frequencyType'] as String? ?? 'يومي';
        final List<dynamic> timesRaw = data['times'] ?? [];
        List<TimeOfDay> doseTimesToday = [];

        if (frequencyType == 'اسبوعي') {
          final todayWeekday = today.weekday; // 1 (Monday) to 7 (Sunday)
          for (var entry in timesRaw) {
            // Check if entry is a map and contains 'day' and 'time'
            if (entry is Map<String, dynamic> && entry['day'] != null && entry['time'] != null) {
              int? dayOfWeek = int.tryParse(entry['day'].toString());
              if (dayOfWeek == todayWeekday) {
                String? timeStr = entry['time']?.toString();
                if (timeStr != null) {
                  final parsedTime = _parseTime(timeStr);
                  if (parsedTime != null) doseTimesToday.add(parsedTime);
                }
              }
            }
          }
        } else { // Assumes 'يومي' or default
          for (var timeEntry in timesRaw) {
            // Handles List<String> or List<dynamic> containing strings
            if (timeEntry is String) {
              final parsedTime = _parseTime(timeEntry);
              if (parsedTime != null) doseTimesToday.add(parsedTime);
            }
            // You might need to handle Map entries here too if daily times can be stored differently
          }
        }

        if (doseTimesToday.isEmpty) continue; // Skip if no doses scheduled for today

        // Calculate time until each dose today
        for (TimeOfDay doseTime in doseTimesToday) {
          final doseTotalMinutes = doseTime.hour * 60 + doseTime.minute;
          int minutesUntil = doseTotalMinutes - nowMinutes;

          // If the dose time has passed for today, calculate for the next occurrence (potentially tomorrow, handled by sorting later)
          // For simplicity here, we only consider upcoming doses *today* or the *next* dose if all today's have passed.
          // A more robust solution might calculate the exact next dose time across days.
          if (minutesUntil < 0) {
            // Option 1: Ignore past doses for today
            // continue;
            // Option 2: Calculate time until *next* day's dose (adds complexity)
            minutesUntil += 24 * 60; // Add 24 hours in minutes
          }

          potentialDoses.add({
            'name': medName,
            'doseTime': doseTime, // Keep the TimeOfDay object if needed
            'doseTimeStr': _formatTimeOfDay(context, doseTime), // Formatted string for display
            'minutesUntil': minutesUntil,
            'docId': doc.id,
          });
        }
      } // End loop through meds

      // Update state after processing all medications
      if (mounted) {
        setState(() {
          if (potentialDoses.isNotEmpty) {
            // Sort by minutes until the dose (ascending)
            potentialDoses.sort((a, b) => (a['minutesUntil'] as int).compareTo(b['minutesUntil'] as int));
            final closest = potentialDoses.first; // The one with the smallest positive minutesUntil
            _closestMedName = closest['name'];
            _closestMedTimeStr = closest['doseTimeStr'];
            _closestMedDocId = closest['docId'];
          } else {
            _closestMedName = ''; // No upcoming doses found
            _closestMedTimeStr = '';
            _closestMedDocId = '';
          }
          _isLoadingMed = false;
        });
      }

    } catch (e) {
      print("Error loading closest medication: $e");
      if (mounted) {
        setState(() {
          _closestMedName = '';
          _closestMedTimeStr = 'خطأ في التحميل';
          _closestMedDocId = '';
          _isLoadingMed = false;
        });
      }
    }
  }


  Future<void> _sendTestNotification(BuildContext context) async {
    if (!mounted) return;
    final now = DateTime.now();
    final testTime = now.add(const Duration(seconds: 10));

    final medicationId = await _getRandomMedicationId();
    if (medicationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("لا يوجد دواء لاختبار الإشعار.", textAlign: TextAlign.right),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await scheduleNotification(
        id: 9999, // Use a unique ID for the test notification
        title: "تذكير تجريبي",
        body: "هذا إشعار تجريبي. اضغط لعرض الدواء.",
        scheduledTime: testTime,
        docId: medicationId, // Pass the docId for payload
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("تم جدولة إشعار تجريبي خلال 10 ثوان.", textAlign: TextAlign.right),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print("Error scheduling test notification: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ في جدولة الإشعار التجريبي.", textAlign: TextAlign.right),
          backgroundColor: kErrorColor,
        ),
      );
    }
  }


  Future<String?> _getRandomMedicationId() async {
    if (!_isAuthenticated) return null;
    final user = FirebaseAuth.instance.currentUser;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('medicines')
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty ? snapshot.docs.first.id : null;
    } catch (e) {
      print('Error getting random medication ID: $e');
      return null;
    }
  }

  Future<void> _testMedicationDetailNavigation(BuildContext context) async {
    if (!mounted) return;
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator(color: kPrimaryColor)),
    );

    try {
      final medicationId = await _getRandomMedicationId();
      Navigator.pop(context); // Dismiss loading indicator

      if (medicationId != null) {
        Navigator.pushNamed(
          context,
          '/medication_detail',
          arguments: {'docId': medicationId},
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("لم يتم العثور على دواء لاختبار التفاصيل.", textAlign: TextAlign.right), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Dismiss loading indicator on error
      print("Error testing medication detail navigation: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("حدث خطأ أثناء الاختبار.", textAlign: TextAlign.right), backgroundColor: kErrorColor),
      );
    }
  }


  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;

    if (!_isAuthenticated) {
      _showLoginRequiredDialog();
      return;
    }

    String? routeName;
    // Define routes for bottom navigation items
    switch (index) {
      case 0: // Home - already here, do nothing or reload
      // You might want to reload data if they tap home again
      // _loadClosestMed();
        setState(() { _selectedIndex = index; }); // Update index if needed
        return; // Don't navigate if already on home
      case 1:
        routeName = "/personal_data"; // Profile/Personal Data Page
        break;
      case 2:
        routeName = "/settings"; // Settings Page
        break;
      default:
        return; // Should not happen
    }

    // Navigate and then update the index visually *after* returning (if needed)
    // Or update index immediately if navigation replaces the current screen
    Navigator.pushNamed(context, routeName).then((_) {
      // This runs when returning from the pushed route
      if (mounted) {
        // If you want the home screen to refresh data when returning:
        // if (index == 0) { // Check if returning to home index
        //   _loadClosestMed();
        // }
        // Visually, the bottom bar should reflect the *current* screen.
        // If navigation pushes screens *on top*, selectedIndex should remain 0 (home).
        // If navigation *replaces* or uses a different structure, adjust accordingly.
        // For a simple pushNamed, keep selectedIndex as 0 unless you change pages differently.
        // setState(() { _selectedIndex = index; }); // Reconsider if this logic is correct for pushNamed
      }
    });
    // If you want the bar to highlight the *target* page immediately:
    // setState(() { _selectedIndex = index; });
  }


  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = _getGreeting(now.hour);

    return Directionality(
      textDirection: ui.TextDirection.rtl, // Set RTL direction for the entire scaffold
      child: Scaffold(
        extendBodyBehindAppBar: true, // Allows body to go behind AppBar
        body: Container(
          // Use a gradient background that blends from primary color to background color
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor,
                kPrimaryColor.withOpacity(0.8),
                kBackgroundColor.withOpacity(0.9), // Blend into background
                kBackgroundColor,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.3, 0.7, 1.0], // Adjust stops for smooth transition
            ),
          ),
          child: SafeArea( // Ensure content is below status bar/notches
            child: RefreshIndicator(
              onRefresh: _isAuthenticated ? _loadClosestMed : () async {}, // Allow refresh only if logged in
              color: kPrimaryColor, // Color of the refresh indicator
              child: FadeTransition(
                opacity: _fadeInAnimation,
                child: SingleChildScrollView( // Allows scrolling if content overflows
                  physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollability even if content fits
                  child: Column(
                    // Main column layout
                    children: [
                      // Header Section
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 10, 24, 20), // Adjust padding (more bottom)
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end, // In RTL, this will align to right
                          children: [
                            Text(
                              _isAuthenticated
                                  ? "$greeting، $_userName" // Combined greeting
                                  : "$greeting، زائر",
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ),
                      ),

                      // Main Content Area (White Rounded Container)
                      Container(
                        width: double.infinity, // Take full width
                        padding: const EdgeInsets.fromLTRB(24, 30, 24, 24), // Inner padding
                        decoration: BoxDecoration(
                          color: Colors.white, // Background for content area
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(30),
                            topRight: Radius.circular(30),
                          ),
                          boxShadow: [ // Subtle shadow
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: Offset(0, -5), // Shadow upwards
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, // In RTL, this will align to right
                          children: [
                            // Conditionally show Login or Upcoming Dose
                            if (!_isAuthenticated)
                              _buildLoginSection()
                            else
                              _buildUpcomingDoseSection(),

                            SizedBox(height: 25),
                            _buildActionCardsSection(), // Always show actions?
                            SizedBox(height: 30),

                            // Conditionally show Dev Tools
                            if (_isAuthenticated && true) // Use kDebugMode or env variable in production
                              _buildDevelopmentToolsSection(),
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
        // Bottom Navigation Bar
        bottomNavigationBar: Directionality(
          textDirection: ui.TextDirection.ltr,
          child: CustomBottomNavigationBar(
            selectedIndex: _selectedIndex, // Reflects the current logical tab index
            onItemTapped: _onItemTapped,
          ),
        ),
      ),
    );
  }

  // Helper method to get appropriate greeting
  String _getGreeting(int hour) {
    if (hour < 12) return "صباح الخير";
    if (hour < 17) return "مساء الخير"; // Afternoon
    return "مساء الخير"; // Evening
  }

  // --- Build Helper Methods ---

  Widget _buildLoginSection() {
    // Builds the section shown to non-authenticated users
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // In RTL, this will align to right
      children: [
        Container(
          width: double.infinity, // Ensure container takes full width for alignment
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor.withOpacity(0.1), Colors.blue.shade50],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPrimaryColor.withOpacity(0.2), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // In RTL, this will align to right
            children: [
              Text(
                "مرحباً بك في تطبيق مُذكر",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimaryColor),
                // No need for textAlign in RTL parent
              ),
              SizedBox(height: 10),
              Text(
                "سجل الدخول للوصول إلى ميزات التطبيق الكاملة وإدارة أدويتك.",
                style: TextStyle(fontSize: 14, color: Colors.black87),
                // No need for textAlign in RTL parent
              ),
              SizedBox(height: 20),
              Row( // Buttons side-by-side
                children: [
                  // Register Button (Right side in RTL)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/register'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent, foregroundColor: kPrimaryColor, elevation: 0,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10), side: BorderSide(color: kPrimaryColor),
                        ),
                      ),
                      child: Text("إنشاء حساب"),
                    ),
                  ),
                  SizedBox(width: 12),
                  // Login Button (Left side in RTL)
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
        Text(
          "استكشف الميزات",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
          // No need for textAlign in RTL parent
        ),
      ],
    );
  }

  Widget _buildUpcomingDoseSection() {
    // Builds the section showing the next medication dose
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // In RTL, this will align to right
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            "الجرعة القادمة",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            // No need for textAlign in RTL parent
          ),
        ),
        // Use a dedicated widget for the dose tile for cleaner code
        _isLoadingMed
            ? _buildLoadingIndicator()
            : _closestMedName.isEmpty
            ? _buildEmptyDoseIndicator()
            : DoseTile( // Assuming DoseTile handles its internal RTL correctly
          medicationName: _closestMedName,
          nextDose: _closestMedTimeStr,
          docId: _closestMedDocId,
          // imageUrl: "", // Pass image URL if available
          // onDelete: () {}, // Pass callback if needed
          // deletable: false, // Control if delete action is shown
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    // Simple loading indicator for the dose tile area
    return Container(
      height: 120, // Match DoseTile height approx
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 3, color: kPrimaryColor),
            SizedBox(height: 10),
            Text("جاري تحميل الجرعة...", style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDoseIndicator() {
    // Widget shown when no upcoming doses are found
    return Container(
      padding: EdgeInsets.symmetric(vertical: 25, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.medication_liquid_outlined, size: 40, color: kSecondaryColor),
            SizedBox(height: 10),
            Text(
              "لا توجد جرعات قادمة مجدولة",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              "أضف دواء جديد باستخدام الزر أدناه.",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildActionCardsSection() {
    // Builds the grid/row of action cards
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // In RTL, this will align to right
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            "الإجراءات السريعة",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
            // No need for textAlign in RTL parent
          ),
        ),
        // Row for Add and Schedule cards
        Row(
          children: [
            // Add Dose Card (Right side in RTL)
            Expanded(
              child: EnhancedActionCard(
                icon: Icons.add_circle_outline, // Use outline icon
                label: "إضافة دواء",
                color: Colors.green.shade600,
                onTap: () {
                  if (_isAuthenticated) {
                    Navigator.pushNamed(context, '/add_dose').then((_) => _loadClosestMed()); // Refresh on return
                  } else {
                    _showLoginRequiredDialog("إضافة دواء");
                  }
                },
              ),
            ),
            SizedBox(width: 16),
            // Schedule Card (Left in RTL)
            Expanded(
              child: EnhancedActionCard(
                icon: Icons.calendar_today_rounded, // Different icon
                label: "جدول الأدوية",
                color: kPrimaryColor,
                onTap: () {
                  if (_isAuthenticated) {
                    Navigator.pushNamed(context, '/dose_schedule');
                  } else {
                    _showLoginRequiredDialog("جدول الأدوية");
                  }
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        // Companions Card (Full width)
        EnhancedActionCard(
          icon: Icons.people_alt_rounded, // Different icon
          label: "المرافقين",
          description: "إدارة ومتابعة حالة المرافقين.", // Updated description
          color: Colors.orange.shade700,
          isHorizontal: true, // Use horizontal layout
          onTap: () {
            if (_isAuthenticated) {
              Navigator.pushNamed(context, '/companions');
            } else {
              _showLoginRequiredDialog("المرافقين");
            }
          },
        ),
      ],
    );
  }


  Widget _buildDevelopmentToolsSection() {
    // Builds the developer tools section (conditionally shown)
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(top: 10), // Add some margin above
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // In RTL, this will align to right
        children: [
          Row( // Use Row for icon and title, align right implicitly by Column parent
            mainAxisSize: MainAxisSize.min, // Prevent Row from taking full width unnecessarily
            children: [
              Text(
                "أدوات المطور (للاختبار)", // Title on the right
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                // No need for textAlign in RTL parent
              ),
              SizedBox(width: 8),
              Icon(Icons.developer_mode, size: 20, color: Colors.grey.shade800), // Icon on the left
            ],
          ),
          SizedBox(height: 16),
          Row( // Buttons side-by-side
            children: [
              // Test Notifications Button (Right in RTL)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _sendTestNotification(context),
                  icon: Icon(Icons.notification_add_rounded, size: 18),
                  label: Text("إشعار تجريبي", style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor.withOpacity(0.8), foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              SizedBox(width: 10),
              // Test Details Button (Left in RTL)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _testMedicationDetailNavigation(context),
                  icon: Icon(Icons.medication_liquid_rounded, size: 18),
                  label: Text("تفاصيل تجريبية", style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600, foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 10),
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
    // Shows a dialog prompting the user to log in
    if (!mounted) return; // Check if context is valid

    String message = featureName != null
        ? 'يجب تسجيل الدخول للوصول إلى ميزة "$featureName".'
        : 'يجب تسجيل الدخول للمتابعة.';

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) { // Use different context name
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.login_rounded, color: kPrimaryColor),
              SizedBox(width: 8),
              Text('تسجيل الدخول مطلوب', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(message), // In RTL, no need for explicit textAlign
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actionsAlignment: MainAxisAlignment.spaceBetween, // Space out buttons
          actions: [
            TextButton(
              child: Text('إلغاء', style: TextStyle(color: Colors.grey.shade700)),
              onPressed: () => Navigator.of(dialogContext).pop(), // Use dialog context
            ),
            ElevatedButton.icon(
              icon: Icon(Icons.login_rounded, size: 18),
              label: Text('تسجيل الدخول'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
                // Use pushReplacementNamed to go to login, replacing current route if needed
                Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ],
        );
      },
    );
  }

} // End of _MainPageState


// --- Separate Widgets (for better organization) ---

// Enhanced DoseTile widget
class DoseTile extends StatelessWidget {
  final String medicationName;
  final String nextDose;
  final String docId;
  // final String imageUrl; // Uncomment if needed
  // final VoidCallback onDelete; // Uncomment if needed
  // final bool deletable; // Uncomment if needed

  const DoseTile({
    super.key,
    required this.medicationName,
    required this.nextDose,
    required this.docId,
    // required this.imageUrl,
    // required this.onDelete,
    // this.deletable = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // margin: EdgeInsets.symmetric(vertical: 4), // Margin handled by parent Column spacing
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: Offset(0, 2)),
        ],
        border: Border.all(color: kPrimaryColor.withOpacity(0.2), width: 1.5),
      ),
      child: Material( // For InkWell effect
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kBorderRadius),
        child: InkWell(
          onTap: () {
            if (docId.isNotEmpty) {
              Navigator.pushNamed(context, '/medication_detail', arguments: {'docId': docId});
            }
          },
          splashColor: kPrimaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(kBorderRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row( // Main row layout
              mainAxisAlignment: MainAxisAlignment.spaceBetween, // Push content apart
              children: [
                // Right side content (in RTL)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // In RTL, this will align to right
                    children: [
                      Text(
                        medicationName,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                        overflow: TextOverflow.ellipsis, // Handle long names
                      ),
                      SizedBox(height: 6),
                      _buildTimeDisplay(), // Time display row
                    ],
                  ),
                ),
                SizedBox(width: 16), // Spacing
                // Left side icon (in RTL)
                _buildMedicationIcon(),
                // Notification badge can be added here or overlayed if needed
                // _buildNotificationBadge(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMedicationIcon() {
    // Builds the styled medication icon
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: kPrimaryColor.withOpacity(0.2), blurRadius: 8, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Icon(Icons.medication_liquid_rounded, size: 32, color: Colors.white),
    );
  }

  Widget _buildTimeDisplay() {
    // Builds the formatted time display part
    return Row(
      mainAxisAlignment: MainAxisAlignment.start, // In RTL, this will align to right
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: kSecondaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kSecondaryColor.withOpacity(0.3), width: 1),
          ),
          child: Row( // Icon and text within the time badge
            mainAxisSize: MainAxisSize.min, // Don't take full width
            children: [
              Text( // Time text on the right
                nextDose,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: kPrimaryColor, // FIXED: Changed from shade800
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.access_time_filled_rounded,
                size: 14,
                color: kPrimaryColor, // FIXED: Changed from shade800
              ), // Icon on the left
            ],
          ),
        ),
      ],
    );
  }

  // Optional: Notification Badge (Consider placement)
  Widget _buildNotificationBadge() {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1), shape: BoxShape.circle,
        border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1.5),
      ),
      child: Icon(Icons.notifications_active_rounded, color: Colors.orange.shade600, size: 22),
    );
  }
}


// Enhanced action card widget
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
          child: Padding( // Add padding consistently
            padding: isHorizontal
                ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12) // Padding for horizontal
                : const EdgeInsets.symmetric(horizontal: 8, vertical: 16), // Padding for vertical
            child: isHorizontal ? _buildHorizontalLayout() : _buildVerticalLayout(),
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalLayout() {
    // Vertical layout (Icon top, Text bottom)
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 32),
        ),
        SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: color, // FIXED: Changed from shade800
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildHorizontalLayout() {
    // Horizontal layout (Icon left, Text right in RTL)
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween, // Space between elements
      children: [
        // Right side: Text content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // In RTL, this will align to right
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color, // FIXED: Changed from shade800
                ),
              ),
              if (description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    description!,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(width: 16), // Spacing
        // Left side: Icon
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 28),
        ),
        // Optional: Add arrow icon if needed
        // Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16), // Forward arrow (Left in RTL)
      ],
    );
  }
}

