import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mudhkir_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For username cache
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // For robust date/time parsing/formatting
import 'package:firebase_messaging/firebase_messaging.dart';

// -----------------------
// Custom Bottom Navigation Bar
// -----------------------
class CustomBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;
  const CustomBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BottomNavigationBar(
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'الرئيسية'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'الملف الشخصي'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'الإعدادات'),
          ],
          currentIndex: selectedIndex,
          selectedItemColor: Colors.blue.shade800,
          unselectedItemColor: Colors.grey.shade500,
          onTap: onItemTapped,
          backgroundColor: Colors.white.withOpacity(0.95),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          showUnselectedLabels: true,
        ),
      ),
    );
  }
}

// -----------------------
// MainPage Widget
// -----------------------
class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  String _userName = '';
  String _closestMedName = '';
  String _closestMedTimeStr = ''; // Formatted time string
  String _closestMedDocId = '';
  bool _isLoadingMed = true; // Loading indicator state
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();
    // Set up animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();
    
    _loadUserData(); // Load username and closest medication concurrently
    _setupFCM();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _setupFCM() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        flutterLocalNotificationsPlugin.show(
          message.notification.hashCode,
          message.notification!.title,
          message.notification!.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'medication_channel',
              'Medication Reminders',
              channelDescription: 'This channel is used for medication reminders.',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['action'] == 'taken') {
        _markDoseAsTaken(message.data['docId']);
      } else if (message.data['action'] == 'reschedule') {
        _promptReschedule(message.data['docId']);
      }
    });
  }

  Future<void> _markDoseAsTaken(String docId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .collection('medicines')
        .doc(docId)
        .update({'status': 'taken'});
    _loadClosestMed();
  }

  Future<void> _promptReschedule(String docId) async {
    // Logic to reschedule dose
    // Suggest optimal time and update Firestore
  }

  Future<void> _loadUserData() async {
    await _loadUserName();
    if (mounted) {
      await _loadClosestMed();
    }
  }

  // Load username from Firestore and cache it in SharedPreferences.
  Future<void> _loadUserName() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        String fetchedName = data['username'] as String? ?? 'مستخدم';
        SharedPreferences prefs = await SharedPreferences.getInstance();
        String? cachedName = prefs.getString('userName');
        if (cachedName == null || cachedName != fetchedName) {
          await prefs.setString('userName', fetchedName);
        }
        if (mounted) {
          setState(() {
            _userName = fetchedName;
          });
        }
      } else {
        if (mounted) setState(() => _userName = 'مستخدم');
      }
    } catch (e) {
      print("Error loading username: $e");
      if (mounted) setState(() => _userName = 'مستخدم');
    }
  }

  // Parse time string using several strategies
  TimeOfDay? _parseTime(String timeStr) {
    try {
      final DateFormat ampmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      String normalizedTime = timeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('مساءً', 'PM')
          .trim();
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
    print("Failed to parse time string: $timeStr");
    return null;
  }

  String _formatTimeOfDay(BuildContext context, TimeOfDay time) {
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }

  // Load the closest upcoming medication dose.
  Future<void> _loadClosestMed() async {
    if (!mounted) return; // Ensure the widget is still in the tree
    setState(() {
      _isLoadingMed = true;
    });

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoadingMed = false;
        });
      }
      return;
    }
    List<Map<String, dynamic>> potentialDoses = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nowMinutes = now.hour * 60 + now.minute; // Minutes passed today

    try {
      final medsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .get();

      for (var doc in medsSnapshot.docs) {
        final data = doc.data();

        // Check start and end dates.
        final startTimestamp = data['startDate'] as Timestamp?;
        final endTimestamp = data['endDate'] as Timestamp?;

        if (startTimestamp == null) continue;

        final startDate = startTimestamp.toDate();
        final endDate = endTimestamp?.toDate();
        final startDay = DateTime(startDate.year, startDate.month, startDate.day);
        final endDay = endDate != null ? DateTime(endDate.year, endDate.month, endDate.day) : null;

        // Skip meds that haven't started or have ended.
        if (today.isBefore(startDay)) continue;
        if (endDay != null && today.isAfter(endDay)) continue;

        // Determine frequency type.
        final frequencyType = data['frequencyType'] as String? ?? 'يومي';
        List<TimeOfDay> doseTimes = [];
        final List<dynamic> timesRaw = data['times'] ?? [];

        if (frequencyType == 'اسبوعي') {
          // For weekly, find times whose 'day' matches today's weekday.
          for (var entry in timesRaw) {
            if (entry is Map<String, dynamic> && entry['day'] == today.weekday) {
              String? timeStr = entry['time']?.toString();
              if (timeStr != null) {
                final parsedTime = _parseTime(timeStr);
                if (parsedTime != null) {
                  doseTimes.add(parsedTime);
                }
              }
            }
          }
        } else {
          // For daily, treat times as List<String> or List<dynamic>.
          for (var timeEntry in timesRaw) {
            if (timeEntry is String) {
              final parsedTime = _parseTime(timeEntry);
              if (parsedTime != null) {
                doseTimes.add(parsedTime);
              }
            }
          }
        }

        if (doseTimes.isEmpty) continue;

        // For each dose time, calculate minutes until next dose.
        for (TimeOfDay doseTime in doseTimes) {
          final doseTotalMinutes = doseTime.hour * 60 + doseTime.minute;
          int minutesUntilNextDose = doseTotalMinutes - nowMinutes;
          if (minutesUntilNextDose < 0) {
            minutesUntilNextDose += 24 * 60;
          }
          potentialDoses.add({
            'name': data['name'] as String? ?? 'دواء غير مسمى',
            'doseTime': doseTime,
            'doseTimeStr': _formatTimeOfDay(context, doseTime),
            'minutesUntil': minutesUntilNextDose,
            'docId': doc.id, // Pass docId here
          });
        }
      }

      if (mounted) {
        setState(() {
          if (potentialDoses.isNotEmpty) {
            final closest = potentialDoses.first;
            _closestMedName = closest['name'];
            _closestMedTimeStr =
                _formatTimeOfDay(context, closest['doseTime'] as TimeOfDay);
            _closestMedDocId = closest['docId'];
          } else {
            _closestMedName = '';
            _closestMedTimeStr = '';
            _closestMedDocId = '';
          }
          _isLoadingMed = false;
        });
      }
    } catch (e) {
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
    final now = DateTime.now();
    final testTime = now.add(const Duration(seconds: 10)); // Schedule 10 seconds from now

    // Get a random medication ID for testing
    final medicationId = await _getRandomMedicationId();
    if (medicationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("لم يتم العثور على أدوية لاختبار الإشعارات"),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(10),
        ),
      );
      return;
    }

    await scheduleNotification(
      id: 9999, // Unique ID for the test notification
      title: "تذكير تجريبي",
      body: "هذا إشعار تجريبي لتذكير الدواء.",
      scheduledTime: testTime,
      docId: medicationId, // Use a real ID format for testing navigation
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("تم جدولة الإشعار التجريبي بنجاح، سيظهر خلال 10 ثوان"),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  Future<String?> _getRandomMedicationId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .limit(1)  // Just get one document
          .get();
      
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.id;
      } else {
        // No medications found
        return null;
      }
    } catch (e) {
      print('Error getting medication ID: $e');
      return null;
    }
  }

  Future<void> _testMedicationDetailNavigation(BuildContext context) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    try {
      // Get a medication ID to use for testing
      final medicationId = await _getRandomMedicationId();
      
      // Close loading dialog
      Navigator.pop(context);
      
      if (medicationId != null) {
        // Navigate to the medication detail page with the retrieved ID
        Navigator.pushNamed(
          context,
          '/medication_detail',
          arguments: {'docId': medicationId},
        );
      } else {
        // No medications found, show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("لم يتم العثور على أدوية لاختبار الصفحة"),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if error occurs
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("حدث خطأ: $e"),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(10),
        ),
      );
    }
  }

  void _onItemTapped(int index) {
    // Navigation logic: update index and call routes based on index.
    if (_selectedIndex == index) return;
    String? routeName;
    if (index == 1) routeName = "/personal_data";
    if (index == 2) routeName = "/settings";

    if (routeName != null) {
      Navigator.pushNamed(context, routeName).then((_) {
        setState(() {
          _selectedIndex = index;
        });
        _loadClosestMed();
      });
    } else {
      setState(() {
        _selectedIndex = index;
      });
      // Optionally reload meds if needed.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient - matching login/signup pages
          Container(
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
            ),
          ),
          
          // Decorative pill shape in background (subtle)
          Positioned(
            top: MediaQuery.of(context).size.height * 0.12,
            left: MediaQuery.of(context).size.width * 0.05,
            child: Opacity(
              opacity: 0.1,
              child: Transform.rotate(
                angle: 0.3,
                child: Container(
                  height: 70,
                  width: 140,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade800,
                    borderRadius: BorderRadius.circular(35),
                  ),
                ),
              ),
            ),
          ),
          
          // Main Content with Pull-to-Refresh
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadClosestMed,
              color: Colors.blue.shade700,
              child: FadeTransition(
                opacity: _fadeInAnimation,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 25),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Welcome Message
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.shade200.withOpacity(0.2),
                                blurRadius: 10,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _userName.isEmpty ? "مرحباً بك" : "مرحباً بك، $_userName",
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade800,
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      "نتمنى لك يوماً صحياً",
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.blue.shade600,
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 15),
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Icon(
                                  Icons.medication_rounded,
                                  size: 32,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 25),
                        
                        // Upcoming Dose Section
                        Text(
                          "الجرعة القادمة",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.shade100.withOpacity(0.3),
                                spreadRadius: 0,
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: _isLoadingMed
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.blue.shade600,
                                    ),
                                  ),
                                )
                              : _closestMedName.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 20.0),
                                        child: Column(
                                          children: [
                                            Icon(
                                              Icons.medication_liquid_outlined,
                                              size: 50,
                                              color: Colors.grey.shade400,
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              "لا توجد جرعات قادمة",
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : DoseTile(
                                      medicationName: _closestMedName,
                                      nextDose: _closestMedTimeStr,
                                      docId: _closestMedDocId,
                                      imageUrl: "", // No image shown here
                                      onDelete: () {},
                                      deletable: false,
                                    ),
                        ),
                        const SizedBox(height: 30),
                        
                        // Action Cards Section
                        _buildActionCards(),
                        
                        const SizedBox(height: 20),
                        // Test Button - styled to match theme
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.shade100.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 0,
                                offset: const Offset(0, 3),
                              ),
                            ],
                            gradient: LinearGradient(
                              colors: [Colors.blue.shade700, Colors.blue.shade800],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () => _sendTestNotification(context),
                            icon: const Icon(Icons.notifications_active, size: 20),
                            label: const Text(
                              "إرسال إشعار تجريبي",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        
                        // NEW: Test Button for Medication Detail Page
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.purple.shade100.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 0,
                                offset: const Offset(0, 3),
                              ),
                            ],
                            gradient: LinearGradient(
                              colors: [Colors.purple.shade500, Colors.purple.shade700],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () => _testMedicationDetailNavigation(context),
                            icon: const Icon(Icons.medication, size: 20),
                            label: const Text(
                              "اختبار صفحة تفاصيل الدواء",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Widget _buildActionCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ActionCard(
                icon: Icons.add_circle_outline,
                label: "إضافة دواء",
                color: Colors.green.shade700,
                onTap: () {
                  Navigator.pushNamed(context, '/add_dose').then((result) {
                    if (result != null) {
                      _loadClosestMed();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: ActionCard(
                icon: Icons.calendar_month_outlined,
                label: "جدول الأدوية",
                color: Colors.blue.shade700,
                onTap: () {
                  Navigator.pushNamed(context, '/dose_schedule');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        ActionCard(
          icon: Icons.people_outline,
          label: "المرافقين",
          color: Colors.orange.shade700,
          isFullWidth: true,
          onTap: () {
            Navigator.pushNamed(context, '/companions');
          },
        ),
      ],
    );
  }
}

// -----------------------
// DoseTile Widget for Closest Dose
// -----------------------
class DoseTile extends StatelessWidget {
  final String medicationName;
  final String nextDose; // formatted time string
  final String docId;
  final String imageUrl;
  final VoidCallback onDelete;
  final bool deletable;
  const DoseTile({
    super.key,
    required this.medicationName,
    required this.nextDose,
    required this.docId,
    required this.imageUrl,
    required this.onDelete,
    this.deletable = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue.shade100, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        leading: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.shade100.withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.medication_liquid,
            size: 32,
            color: Colors.blue.shade700,
          ),
        ),
        title: Text(
          medicationName,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade900,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(
              Icons.access_time_rounded,
              size: 16,
              color: Colors.blue.shade600,
            ),
            const SizedBox(width: 5),
            Text(
              nextDose,
              style: TextStyle(
                fontSize: 15,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.notifications_active_rounded,
          color: Colors.orange.shade600,
          size: 24,
        ),
      ),
    );
  }
}

// -----------------------
// ActionCard Widget
// -----------------------
class ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isFullWidth;
  
  const ActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.isFullWidth = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            decoration: BoxDecoration(
              border: Border.all(color: color.withOpacity(0.2), width: 1.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: isFullWidth 
                  ? MainAxisAlignment.start 
                  : MainAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon, 
                    size: 26, 
                    color: color,
                  ),
                ),
                const SizedBox(width: 15),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                if (isFullWidth)
                  const Spacer(),
                if (isFullWidth)
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: color,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

