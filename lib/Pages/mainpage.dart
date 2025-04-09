import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For username cache
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // For robust date/time parsing/formatting

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
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'الملف الشخصي'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
        currentIndex: selectedIndex,
        selectedItemColor: Colors.blue.shade800,
        unselectedItemColor: Colors.grey.shade600,
        onTap: onItemTapped,
        backgroundColor: Colors.white.withOpacity(0.9),
        elevation: 5,
        type: BottomNavigationBarType.fixed,
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

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  String _userName = '';
  String _closestMedName = '';
  String _closestMedTimeStr = ''; // Formatted time string
  String _closestMedDocId = '';
  bool _isLoadingMed = true; // Loading indicator state

  @override
  void initState() {
    super.initState();
    _loadUserData(); // Load username and closest medication concurrently
  }

  Future<void> _loadUserData() async {
    await _loadUserName();
    await _loadClosestMed();
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
    setState(() {
      _isLoadingMed = true;
    });
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isLoadingMed = false;
      });
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
            'docId': doc.id,
          });
        }
      }

      if (potentialDoses.isNotEmpty) {
        potentialDoses.sort((a, b) =>
            (a['minutesUntil'] as int).compareTo(b['minutesUntil'] as int));
        final closest = potentialDoses.first;
        setState(() {
          _closestMedName = closest['name'];
          _closestMedTimeStr =
              _formatTimeOfDay(context, closest['doseTime'] as TimeOfDay);
          _closestMedDocId = closest['docId'];
          _isLoadingMed = false;
        });
      } else {
        setState(() {
          _closestMedName = '';
          _closestMedTimeStr = '';
          _closestMedDocId = '';
          _isLoadingMed = false;
        });
      }
    } catch (e) {
      print("Error loading closest medication: $e");
      setState(() {
        _closestMedName = '';
        _closestMedTimeStr = 'خطأ في التحميل';
        _closestMedDocId = '';
        _isLoadingMed = false;
      });
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
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // Main Content with Pull-to-Refresh
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadClosestMed,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Welcome Message
                      Text(
                        _userName.isEmpty ? "مرحباً بك" : "مرحباً بك، $_userName",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      Text(
                        "نتمنى لك يوماً صحياً",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.blue.shade600,
                        ),
                        textAlign: TextAlign.right,
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
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              spreadRadius: 1,
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: _isLoadingMed
                            ? const Center(child: CircularProgressIndicator())
                            : _closestMedName.isEmpty
                            ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10.0),
                            child: Text(
                              "لا توجد جرعات قادمة",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
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
                    ],
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.medication_liquid,
          size: 30,
          color: Colors.blue.shade700,
        ),
      ),
      title: Text(
        medicationName,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: Colors.blue.shade900,
        ),
      ),
      subtitle: Text(
        "الوقت: $nextDose",
        style: const TextStyle(
          fontSize: 15,
          color: Colors.black54,
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
  final VoidCallback onTap;
  final bool isFullWidth;
  const ActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isFullWidth = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      constraints: const BoxConstraints(minHeight: 90),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withOpacity(0.15),
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 15.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 35, color: Colors.blue.shade700),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
