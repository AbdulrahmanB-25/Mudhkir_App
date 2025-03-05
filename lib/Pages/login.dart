import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _emailError = '';
  String _passwordError = '';
  String _loginError = ''; // General login error (wrong credentials)
  bool _isSubmitted = false; // Track if login button was pressed

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    // Remove error messages when user starts typing
    _emailController.addListener(() {
      if (_isSubmitted) {
        setState(() {
          _emailError = '';
          _loginError = '';
        });
      }
    });

    _passwordController.addListener(() {
      if (_isSubmitted) {
        setState(() {
          _passwordError = '';
          _loginError = '';
        });
      }
    });
  }

  /// **Validates Email (After Button Press)**
  String _validateEmail(String email) {
    if (email.isEmpty) {
      return 'الرجاء إدخال البريد الإلكتروني';
    }
    if (!RegExp(r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$").hasMatch(email)) {
      return 'تنسيق البريد الإلكتروني غير صحيح';
    }
    return '';
  }

  /// **Validates Password Format (On Unfocus)**
  String _validatePassword(String password) {
    if (password.isEmpty) {
      return 'الرجاء إدخال كلمة المرور';
    }
    if (password.length < 6) {
      return 'يجب أن تحتوي كلمة المرور على 6 أحرف على الأقل';
    }
    return '';
  }

  /// **Handles User Login with Firebase**
  void _login() async {
    setState(() {
      _isSubmitted = true; // Mark that login button was pressed
      _emailError = _validateEmail(_emailController.text);
      _passwordError = _passwordController.text.isEmpty ? 'الرجاء إدخال كلمة المرور' : '';
      _loginError = ''; // Reset login error when button is pressed
    });

    if (_emailError.isEmpty && _passwordError.isEmpty) {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        Navigator.of(context).pushReplacementNamed('/mainpage');
      } on FirebaseAuthException catch (e) {
        setState(() {
          if (e.code == 'user-not-found') {
            _loginError = 'لم يتم العثور على مستخدم بهذا البريد الإلكتروني';
          } else if (e.code == 'wrong-password') {
            _loginError = 'كلمة المرور غير صحيحة';
          } else {
            _loginError = 'حدث خطأ أثناء تسجيل الدخول. يرجى المحاولة مرة أخرى.';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacementNamed(context, '/'); // Go to Welcome Page
        return false;
      },
      child: Scaffold(
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
                            Icons.lock_open,
                            size: 60,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                      SizedBox(height: 30),

                      // Page Title
                      Text(
                        "تسجيل الدخول",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      SizedBox(height: 20),

                      // Email Field
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
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
                      if (_isSubmitted && _emailError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            _emailError,
                            style: TextStyle(color: Colors.red, fontSize: 14),
                          ),
                        ),
                      SizedBox(height: 15),

                      // Password Field
                      Focus(
                        onFocusChange: (hasFocus) {
                          if (!hasFocus) {
                            setState(() {
                              _passwordError = _validatePassword(_passwordController.text);
                            });
                          }
                        },
                        child: TextField(
                          controller: _passwordController,
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
                      ),
                      if (_isSubmitted && _passwordError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            _passwordError,
                            style: TextStyle(color: Colors.red, fontSize: 14),
                          ),
                        ),
                      SizedBox(height: 10),

                      // General Login Error (Appears Above Login Button)
                      if (_loginError.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _loginError,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),

                      // Login Button
                      ElevatedButton(
                        onPressed: _login,
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
                      SizedBox(height: 20),

                      // Sign Up Link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("ليس لديك حساب؟ ", style: TextStyle(color: Colors.blue.shade800)),
                          GestureDetector(
                            onTap: () => Navigator.pushNamed(context, '/signup'),
                            child: Text("إنشاء حساب", style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
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
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
