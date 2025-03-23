import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      String name = userDoc['username'];
      await prefs.setString('userName', name);
      setState(() {
        _userName = name;
      });
    }
  }

  // Helper to pad a date string to "yyyy-MM-dd" format.
  String formatDateString(String dateString) {
    List<String> parts = dateString.split('-');
    if (parts.length != 3) return dateString;
    try {
      String year = parts[0].trim();
      int m = int.parse(parts[1].trim());
      int d = int.parse(parts[2].trim());
      String month = m.toString().padLeft(2, '0');
      String day = d.toString().padLeft(2, '0');
      return '$year-$month-$day';
    } catch (e) {
      print("Error parsing date '$dateString': $e");
      return dateString;
    }
  }

  // Updated _parseTime function using RegExp to extract hour and minute robustly.
  TimeOfDay _parseTime(String timeString) {
    timeString = timeString.trim();
    bool isPM = timeString.contains("مساءً") || timeString.contains("PM");
    // Remove markers (Arabic and English)
    timeString = timeString.replaceAll(RegExp(r'(مساءً|صباحاً|PM|AM)'), "").trim();
    // Use RegExp to extract hour and minute (minute is optional)
    RegExp regExp = RegExp(r'(\d{1,2})\D*(\d{0,2})');
    Match? match = regExp.firstMatch(timeString);
    if (match == null) {
      // If no match, default to 0:00.
      return const TimeOfDay(hour: 0, minute: 0);
    }
    int hour = int.tryParse(match.group(1) ?? "0") ?? 0;
    int minute = 0;
    if (match.group(2) != null && match.group(2)!.isNotEmpty) {
      minute = int.tryParse(match.group(2)!) ?? 0;
    }
    if (isPM && hour < 12) {
      hour += 12;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  // Helper: Format a TimeOfDay to a string (e.g., "8:00 مساءً").
  String _formatTimeOfDay(TimeOfDay time) {
    final int displayHour =
    time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final String period = time.hour >= 12 ? "مساءً" : "صباحاً";
    final String minuteStr = time.minute.toString().padLeft(2, '0');
    return "$displayHour:$minuteStr $period";
  }

  // Fetch upcoming medications and compute each medication's next dose time.
  Future<List<Map<String, String>>> _fetchUpcomingMedications() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('medicines')
        .where('userId', isEqualTo: user.uid)
        .get();
    List<Map<String, String>> upcoming = [];
    DateTime now = DateTime.now();
    int nowMinutes = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;
    for (var doc in snapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      // Reformat date strings to "yyyy-MM-dd" before parsing.
      String startDateStr = formatDateString(data['startDate']);
      String endDateStr = formatDateString(data['endDate']);
      DateTime startDate = DateTime.parse(startDateStr);
      DateTime endDate = DateTime.parse(endDateStr);
      // Check if today is within the active period.
      if (now.isBefore(startDate) || now.isAfter(endDate)) continue;
      List<dynamic> times = data['times'] ?? [];
      TimeOfDay? nextDose;
      int? minDiff;
      for (var timeStr in times) {
        TimeOfDay scheduled = _parseTime(timeStr);
        int scheduledMinutes = scheduled.hour * 60 + scheduled.minute;
        int diff = scheduledMinutes - nowMinutes;
        if (diff < 0) diff += 24 * 60; // Wrap to next day if needed.
        if (minDiff == null || diff < minDiff) {
          minDiff = diff;
          nextDose = scheduled;
        }
      }
      if (nextDose != null) {
        String nextDoseStr = _formatTimeOfDay(nextDose);
        upcoming.add({'name': data['name'], 'nextDose': nextDoseStr});
      }
    }
    // Sort medications by next dose time (in minutes).
    upcoming.sort((a, b) {
      TimeOfDay timeA = _parseTime(a['nextDose']!);
      TimeOfDay timeB = _parseTime(b['nextDose']!);
      int minutesA = timeA.hour * 60 + timeA.minute;
      int minutesB = timeB.hour * 60 + timeB.minute;
      return minutesA.compareTo(minutesB);
    });
    return upcoming;
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      Navigator.pushNamed(context, "/personal_data").then((_) {
        setState(() {
          _selectedIndex = 1;
        });
      });
    } else if (index == 2) {
      Navigator.pushNamed(context, "/SettingsPage").then((_) {
        setState(() {
          _selectedIndex = 2;
        });
      });
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "مرحبا بك، $_userName",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  Text(
                    "نتمنى لك يوماً صحياً",
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.blue.shade600,
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Dynamic upcoming medications section.
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: FutureBuilder<List<Map<String, String>>>(
                      future: _fetchUpcomingMedications(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        } else if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        } else {
                          final upcoming = snapshot.data!;
                          if (upcoming.isEmpty) {
                            return Text(
                              "لا يوجد جرعات قادمة اليوم",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.blue.shade800,
                              ),
                            );
                          }
                          // For each medication, show a DoseTile.
                          return Column(
                            children: upcoming.map((med) {
                              return DoseTile(med['name']!, med['nextDose']!);
                            }).toList(),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 30),
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ActionCard(
                              icon: Icons.add_circle,
                              label: "إضافة دواء جديد",
                              onTap: () {
                                Navigator.pushNamed(context, '/add_dose');
                              },
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: ActionCard(
                              icon: Icons.calendar_today,
                              label: "جدول الأدوية",
                              onTap: () {
                                Navigator.pushNamed(context, '/dose_schedule');
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ActionCard(
                        icon: Icons.people,
                        label: "المرافقين",
                        isFullWidth: true,
                        onTap: () {
                          Navigator.pushNamed(context, '/companions');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'الرئيسية',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'الملف الشخصي',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue.shade800,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
      ),
    );
  }
}

/// Updated DoseTile widget which shows the medication name and next scheduled dose.
class DoseTile extends StatelessWidget {
  final String medicationName;
  final String nextDose;

  const DoseTile(this.medicationName, this.nextDose, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Icons.medical_services, size: 40, color: Colors.blue.shade800),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                medicationName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                nextDose,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.blue.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ActionCard remains unchanged.
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
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 50, color: Colors.blue.shade800),
              const SizedBox(width: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
