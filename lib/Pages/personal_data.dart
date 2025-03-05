import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PersonalDataPage extends StatefulWidget {
  const PersonalDataPage({super.key});

  @override
  _PersonalDataPageState createState() => _PersonalDataPageState();
}

class _PersonalDataPageState extends State<PersonalDataPage> {
  int _selectedIndex = 1; // Highlights "Profile" tab
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
      FirebaseFirestore.instance.collection('users').doc(user.uid).get().then((document) {
        if (document.exists && document.data() != null) {
          setState(() {
            _username = document.data()!['username'] ?? 'User';
            _email = user.email ?? 'No Email';
          });
        }
      });
    }
  }

  /// Handles Bottom Navigation Bar Tap
  void _onItemTapped(int index) {
    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/mainpage'); // Go to Main Page
    } else if (index == 2) {
      Navigator.pushNamed(context, '/settings'); // Go to Settings Page
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // Disable back button navigation
      child: Scaffold(
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
            Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center, // Center all items
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      /// 👤 Greeting with Username
                      Text(
                        "مرحبا بك $_username",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 10),
                      Text(
                        "هذه هي بياناتك الشخصية",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.blue.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 30),

                      /// 🏷️ User Information Card
                      Container(
                        padding: EdgeInsets.all(20),
                        width: double.infinity, // Ensures it takes full width
                        constraints: BoxConstraints(maxWidth: 400), // Prevents overflow
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
                            Row(
                              children: [
                                Icon(Icons.person, size: 40, color: Colors.blue.shade800),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "اسم المستخدم: $_username",
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.start,
                                    softWrap: true,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 15),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start, // Aligns text properly
                              children: [
                                Icon(Icons.email, size: 40, color: Colors.blue.shade800),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "البريد الإلكتروني: $_email",
                                    style: TextStyle(fontSize: 18),
                                    textAlign: TextAlign.start,
                                    softWrap: true,
                                    maxLines: 2, // Allows long emails to wrap to a second line
                                    overflow: TextOverflow.visible, // Ensures email is fully shown
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 30),

                      /// 🚪 Logout Button
                      ElevatedButton(
                        onPressed: () {
                          FirebaseAuth.instance.signOut();
                          Navigator.pushReplacementNamed(context, "/login");
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                          minimumSize: Size(200, 50),
                        ),
                        child: const Text(
                          'تسجيل الخروج',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
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
          currentIndex: _selectedIndex, // Highlights "Profile" tab
          selectedItemColor: Colors.blue.shade800,
          unselectedItemColor: Colors.grey,
          onTap: _onItemTapped,
        ),
      ),
    );
  }
}
