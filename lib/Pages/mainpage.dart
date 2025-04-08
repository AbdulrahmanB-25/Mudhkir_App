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
  String _closestMedName = '';
  String _closestMedDose = '';
  String _closestMedDocId = '';

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadClosestMed();
  }

  // Always fetch the username from Firestore. Update the cache if it differs.
  Future<void> _loadUserName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cachedName = prefs.getString('userName');
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      String fetchedName = userDoc['username'] as String;
      if (cachedName == null || cachedName != fetchedName) {
        await prefs.setString('userName', fetchedName);
        if (!mounted) return;
        setState(() {
          _userName = fetchedName;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _userName = cachedName;
        });
      }
    }
  }

  // Helper to parse a time string into a TimeOfDay.
  TimeOfDay _parseTime(String timeStr) {
    final cleaned = timeStr.replaceAll(RegExp(r'[^\d:]'), '').trim();
    final parts = cleaned.split(':');
    int hour = int.tryParse(parts[0]) ?? 0;
    int minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    if (timeStr.contains("PM") || timeStr.contains("مساءً")) {
      if (hour < 12) hour += 12;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  // Helper to format a TimeOfDay as a string.
  String _formatTimeOfDay(TimeOfDay time) {
    final int displayHour =
    time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
    final String minuteStr = time.minute.toString().padLeft(2, '0');
    final String suffix = time.hour >= 12 ? "مساءً" : "صباحاً";
    return "$displayHour:$minuteStr $suffix";
  }

  // Fetch upcoming doses from Firestore. Return only the closest upcoming dose.
  Future<List<Map<String, String>>> _getUpcomingDoses() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final medsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('medicines')
        .get();
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    List<Map<String, String>> upcoming = [];
    for (var doc in medsSnapshot.docs) {
      final data = doc.data();
      final startDate = DateTime.tryParse(data['startDate'] ?? '');
      final endDate = DateTime.tryParse(data['endDate'] ?? '');
      if (startDate == null || endDate == null) continue;
      if (now.isBefore(startDate) || now.isAfter(endDate)) continue;
      final times = List<String>.from(data['times'] ?? []);
      String? closestTime;
      int minDiff = 24 * 60;
      for (String time in times) {
        final parsed = _parseTime(time);
        final totalMins = parsed.hour * 60 + parsed.minute;
        final diff = (totalMins - nowMinutes + 24 * 60) % (24 * 60);
        if (diff < minDiff) {
          minDiff = diff;
          closestTime = _formatTimeOfDay(parsed);
        }
      }
      if (closestTime != null) {
        upcoming.add({
          'name': data['name'] as String,
          'nextDose': closestTime,
          'docId': doc.id,
        });
      }
    }
    // Sort by upcoming dose time.
    upcoming.sort((a, b) {
      final aTime = _parseTime(a['nextDose']!);
      final bTime = _parseTime(b['nextDose']!);
      return (aTime.hour * 60 + aTime.minute)
          .compareTo(bTime.hour * 60 + bTime.minute);
    });
    return upcoming.take(1).toList();
  }

  // Always fetch the closest med and update SharedPreferences only if changed.
  Future<void> _loadClosestMed() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<Map<String, String>> meds = await _getUpcomingDoses();
    if (meds.isNotEmpty) {
      final closestMed = meds.first;
      String? cachedMedName = prefs.getString('closestMedName');
      String? cachedMedDose = prefs.getString('closestMedDose');
      if (cachedMedName == null ||
          cachedMedName != closestMed['name'] ||
          cachedMedDose == null ||
          cachedMedDose != closestMed['nextDose']) {
        await prefs.setString('closestMedName', closestMed['name']!);
        await prefs.setString('closestMedDose', closestMed['nextDose']!);
        await prefs.setString('closestMedDocId', closestMed['docId']!);
        if (!mounted) return;
        setState(() {
          _closestMedName = closestMed['name']!;
          _closestMedDose = closestMed['nextDose']!;
          _closestMedDocId = closestMed['docId']!;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _closestMedName = cachedMedName;
          _closestMedDose = cachedMedDose;
          _closestMedDocId = prefs.getString('closestMedDocId') ?? '';
        });
      }
    } else {
      await prefs.remove('closestMedName');
      await prefs.remove('closestMedDose');
      await prefs.remove('closestMedDocId');
      if (!mounted) return;
      setState(() {
        _closestMedName = '';
        _closestMedDose = '';
        _closestMedDocId = '';
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      Navigator.pushNamed(context, "/personal_data").then((_) {
        setState(() {
          _selectedIndex = 1;
        });
        _loadClosestMed();
      });
    } else if (index == 2) {
      Navigator.pushNamed(context, "/SettingsPage").then((_) {
        setState(() {
          _selectedIndex = 2;
        });
        _loadClosestMed();
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
      // Background Gradient.
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
          // Main Content.
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
                  // Upcoming Dose Section.
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 5)),
                      ],
                    ),
                    child: _closestMedName.isEmpty
                        ? Center(
                      child: Text(
                        "لا يوجد جرعات قادمة اليوم",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    )
                        : DoseTile(
                      medicationName: _closestMedName,
                      nextDose: _closestMedDose,
                      docId: _closestMedDocId,
                      onDelete: _loadClosestMed,
                      deletable: false, // Disable deletion.
                    ),
                  ),
                  const SizedBox(height: 30),
                  // Action Cards Section.
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ActionCard(
                              icon: Icons.add_circle,
                              label: "إضافة دواء جديد",
                              onTap: () {
                                Navigator.pushNamed(context, '/add_dose')
                                    .then((_) => _loadClosestMed());
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
      // Bottom Navigation Bar.
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

/// DoseTile now includes a "deletable" flag. For the upcoming dose, deletable is false.
class DoseTile extends StatefulWidget {
  final String medicationName;
  final String nextDose;
  final String docId;
  final VoidCallback onDelete;
  final bool deletable;

  const DoseTile({
    super.key,
    required this.medicationName,
    required this.nextDose,
    required this.docId,
    required this.onDelete,
    this.deletable = true,
  });

  @override
  _DoseTileState createState() => _DoseTileState();
}

class _DoseTileState extends State<DoseTile> {
  Future<bool?> _confirmDismiss(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            const SizedBox(width: 10),
            const Text(
              "تأكيد",
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        content: const Text("هل أنت متأكد من حذف هذا الدواء؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("إلغاء", style: TextStyle(color: Colors.blue)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("حذف"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMedication(BuildContext context) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(widget.docId)
          .delete();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم حذف الدواء بنجاح")),
    );
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    Widget tile = Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 4,
      child: ListTile(
        // For this version, we remove the delete ability by showing a default icon.
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10), // Rounded rectangle edges.
          child: Icon(
            Icons.medication_liquid,
            color: Colors.blue.shade800,
            size: 40,
          ),
        ),
        title: Text(
          widget.medicationName,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
        ),
        subtitle: Text(
          widget.nextDose,
          style: TextStyle(
            fontSize: 14,
            color: Colors.blue.shade600,
          ),
        ),
      ),
    );

    // If deletable is true, wrap the tile in Dismissible; otherwise, simply return the tile.
    return widget.deletable
        ? Dismissible(
      key: Key(widget.docId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white, size: 30),
      ),
      confirmDismiss: (direction) => _confirmDismiss(context),
      onDismissed: (direction) async {
        await _deleteMedication(context);
      },
      child: tile,
    )
        : tile;
  }
}

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
              color: Colors.black12, blurRadius: 10, offset: Offset(0, 5)),
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
