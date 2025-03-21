import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Welcome extends StatefulWidget {
  const Welcome({super.key});

  @override
  _WelcomeState createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    // Redirect to main page if user is already logged in
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        Navigator.pushReplacementNamed(context, '/mainpage');
      }
    });
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

          // Main Content in a Column
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _animation,
                    child: CircleAvatar(
                      radius: 75,
                      backgroundColor: Colors.blue.shade50,
                      child: Icon(
                        //TODO : NEW ICON
                        Icons.medical_services_outlined,
                        size: 80,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                  SizedBox(height: 30),
                  Text(
                    "مُذَكِّر",
                    style: TextStyle(
                      fontSize: 50,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 15),
                  Text(
                    "مرحباً بك في مُذَكِّر،\nمساعدك الأمثل لتتبع الأدوية.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.blue.shade600,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  SizedBox(height: 40),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/login');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 15),
                        minimumSize: Size(double.infinity, 50),
                        elevation: 3,
                        shadowColor: Colors.black26,
                      ),
                      child: Text(
                        "تسجيل الدخول",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/signup');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color.fromARGB(255, 226, 241, 243),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                          side: BorderSide(color: const Color.fromARGB(255, 226, 241, 243), width: 2),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 15),
                        minimumSize: Size(double.infinity, 50),
                        elevation: 3,
                        shadowColor: Colors.black26,
                      ),
                      child: Text(
                        "إنشاء حساب",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 50), // Add spacing before social icons
                ],
              ),
            ),
          ),

          // Social Media Icons at the Bottom (Wrapped in Stack)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.facebook_rounded, color: Colors.blue.shade800, size: 35),
                SizedBox(width: 20),
                Icon(Icons.email_rounded, color: Colors.blue.shade800, size: 35),
                SizedBox(width: 20),
                Icon(Icons.phone_rounded, color: Colors.blue.shade800, size: 35),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
