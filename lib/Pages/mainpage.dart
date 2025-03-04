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
    setState(() {
      _selectedIndex = index;
    });
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
                crossAxisAlignment: CrossAxisAlignment.end, // Aligned to the right
                children: [
                  /// 👋 Greeting
                  Text(
                    "مرحبا بك",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  Text(
                    "نتمنى لك يوماً صحياً",
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.blue.shade600,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  SizedBox(height: 30),

                  /// 💊 Coming Drug Dose Bar
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
                    child: Row(
                      children: [
                        Icon(Icons.medical_services,
                            size: 40, color: Colors.blue.shade800),
                        SizedBox(width: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "الجرعة القادمة",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            SizedBox(height: 5),
                            Text(
                              "بانادول 500 ملجم - الساعة 8:00 مساءً",
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.blue.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 30),

                  /// 🚀 Quick Actions
                  GridView.count(
                    shrinkWrap: true,
                    crossAxisCount: 2,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                    children: [
                      /// ➕ Add New Medication
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/add_dose');
                        },
                        child: Container(
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
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle, size: 50, color: Colors.blue.shade800),
                              SizedBox(height: 10),
                              Text(
                                "إضافة دواء جديد",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),

                      /// 📅 View Medication Schedule
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/dose_schedule');
                        },
                        child: Container(
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
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today, size: 50, color: Colors.blue.shade800),
                              SizedBox(height: 10),
                              Text(
                                "جدول الأدوية",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),

                      /// 👥 View Companions
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/companions');
                        },
                        child: Container(
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
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people, size: 50, color: Colors.blue.shade800),
                              SizedBox(height: 10),
                              Text(
                                "المرافقين",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.blue.shade800, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
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
        items: <BottomNavigationBarItem>[
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
