import 'package:flutter/material.dart';

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  _SignupState createState() => _SignupState();
}

class _SignupState extends State<Signup> with SingleTickerProviderStateMixin {
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

          // Main Content
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Animated Logo
                    ScaleTransition(
                      scale: _animation,
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.blue.shade50,
                        child: Icon(
                          Icons.person_add_alt_1,
                          size: 60,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ),
                    SizedBox(height: 30),

                    // Page Title
                    Text(
                      "إنشاء حساب",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    SizedBox(height: 20),

                    // Full Name Field
                    TextField(
                      decoration: InputDecoration(
                        labelText: "الاسم الكامل",
                        labelStyle: TextStyle(color: Colors.blue.shade800),
                        filled: true,
                        fillColor: Colors.blue.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(Icons.person, color: Colors.blue.shade800),
                      ),
                    ),
                    SizedBox(height: 15),

                    // Email Field
                    TextField(
                      decoration: InputDecoration(
                        labelText: "البريد الإلكتروني",
                        labelStyle: TextStyle(color: Colors.blue.shade800),
                        filled: true,
                        fillColor: Colors.blue.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(Icons.email, color: Colors.blue.shade800),
                      ),
                    ),
                    SizedBox(height: 15),

                    // Password Field
                    TextField(
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "كلمة المرور",
                        labelStyle: TextStyle(color: Colors.blue.shade800),
                        filled: true,
                        fillColor: Colors.blue.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(Icons.lock, color: Colors.blue.shade800),
                      ),
                    ),
                    SizedBox(height: 15),

                    // Confirm Password Field
                    TextField(
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "تأكيد كلمة المرور",
                        labelStyle: TextStyle(color: Colors.blue.shade800),
                        filled: true,
                        fillColor: Colors.blue.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Icon(Icons.lock_outline, color: Colors.blue.shade800),
                      ),
                    ),
                    SizedBox(height: 30),

                    // Signup Button
                    ElevatedButton(
                      onPressed: () {
                        // Implement signup logic here
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
                        "إنشاء حساب",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    // Sign In Link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "لديك حساب بالفعل؟ ",
                          style: TextStyle(color: Colors.blue.shade800),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, '/login');
                          },
                          child: Text(
                            "تسجيل الدخول",
                            style: TextStyle(
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
