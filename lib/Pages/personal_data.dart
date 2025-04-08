import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PersonalDataPage extends StatefulWidget {
  const PersonalDataPage({super.key});

  @override
  _PersonalDataPageState createState() => _PersonalDataPageState();
}

class _PersonalDataPageState extends State<PersonalDataPage> {
  // Keep the selected index for bottom navigation. Here, 1 is for Profile.
  final int _selectedIndex = 1;
  String _username = '...loading'; // Placeholder while fetching username
  String _email = '...loading'; // Placeholder while fetching email

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  void fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .then((document) {
        if (document.exists && document.data() != null) {
          setState(() {
            _username = document.data()!['username'] ?? 'User';
            _email = user.email ?? 'No Email';
          });
        }
      });
    }
  }

  /// Handles Bottom Navigation Bar Tap.
  void _onItemTapped(int index) {
    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/mainpage'); // Navigate to Main Page
    } else if (index == 2) {
      Navigator.pushReplacementNamed(context, '/settings'); // Navigate to Settings Page
    }
    // Since this is the Profile page, no action is needed for index 1.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Background with gradient.
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
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Greeting with username.
                    Text(
                      "مرحبا بك $_username",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "هذه هي بياناتك الشخصية",
                      style: TextStyle(
                        fontSize: 20,
                        color: Colors.blue.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    // User Information Card.
                    Container(
                      padding: const EdgeInsets.all(20),
                      width: double.infinity,
                      constraints:
                      const BoxConstraints(maxWidth: 400), // prevent overflow
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
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.person,
                                  size: 40, color: Colors.blue.shade800),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "اسم المستخدم: $_username",
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.start,
                                  softWrap: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.email,
                                  size: 40, color: Colors.blue.shade800),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "البريد الإلكتروني: $_email",
                                  style: const TextStyle(fontSize: 18),
                                  textAlign: TextAlign.start,
                                  softWrap: true,
                                  maxLines: 2,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Logout Button.
                    ElevatedButton.icon(
                      onPressed: () {
                        FirebaseAuth.instance.signOut();
                        Navigator.pushReplacementNamed(context, "/login");
                      },
                      icon: const Icon(Icons.exit_to_app, color: Colors.white),
                      label: const Text(
                        "تسجيل الخروج",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
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
