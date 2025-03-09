import 'package:flutter/material.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  /// Handles Bottom Navigation Bar Tap
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
          /// 🌈 Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          /// 📜 Main Content
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end, 
                children: [
                  /// 👋 Greeting
                  Text(
                    "مرحبا بك",
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
                  SizedBox(height: 30),

                  /// 💊 Coming Drug Dose Section (Handles Multiple Doses)
                  Container(
                    
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        DoseTile("بانادول 500 ملجم", "8:00 مساءً"),
                        DoseTile("باراسيتامول", "8:00 مساءً"), 
                      ],
                    ),
                  ),
                  SizedBox(height: 30),

                  /// 🚀 Quick Actions
                  Column(
                    children: [
                      /// First Row (2 Cards)
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
                          SizedBox(width: 20),
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
                      SizedBox(height: 20),

                      /// Second Row (1 Large Companion Card)
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

      /// 📌 Bottom Navigation Bar
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

/// 💊 Widget to Show Each Dose in the Next Dose Section
class DoseTile extends StatelessWidget {
  final String medicationName;
  final String time;
  const DoseTile(this.medicationName, this.time, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Icons.medical_services, size: 40, color: Colors.blue.shade800),
          SizedBox(width: 15),
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
              SizedBox(height: 5),
              Text(
                time,
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

/// 🎯 Widget for Quick Actions (Add Dose, View Schedule, View Companions)
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
      height: 100, // Ensuring uniform height
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
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
              SizedBox(width: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.blue.shade800, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
