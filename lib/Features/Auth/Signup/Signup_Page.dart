import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Signup extends StatefulWidget {
  const Signup({super.key});

  @override
  _SignupState createState() => _SignupState();
}

class _SignupState extends State<Signup> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String _nameError = '';
  String _emailError = '';
  String _passwordError = '';
  String _confirmPasswordError = '';
  String _signupError = '';
  bool _isSubmitted = false;

  @override
  void initState() {
    super.initState();
    // Initialize animation for UI transitions
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    // Clear error messages when user modifies input fields
    _nameController.addListener(() {
      if (_isSubmitted) setState(() => _nameError = '');
    });
    _emailController.addListener(() {
      if (_isSubmitted) setState(() => _emailError = '');
    });
    _passwordController.addListener(() {
      if (_isSubmitted) setState(() => _passwordError = '');
    });
    _confirmPasswordController.addListener(() {
      if (_isSubmitted) setState(() => _confirmPasswordError = '');
    });
  }

  String _validateEmail(String email) {
    // Validates email format and ensures it's not empty
    if (email.isEmpty) return 'الرجاء إدخال البريد الإلكتروني';
    if (!RegExp(r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$").hasMatch(email)) {
      return 'تنسيق البريد الإلكتروني غير صحيح';
    }
    return '';
  }

  String _validatePassword(String password) {
    // Validates password strength (length, uppercase, number, special character)
    if (password.isEmpty) return 'الرجاء إدخال كلمة المرور';
    if (password.length < 8) return 'يجب أن تحتوي كلمة المرور على 8 أحرف على الأقل';
    if (!password.contains(RegExp(r'[A-Z]'))) return 'يجب أن تحتوي على حرف كبير واحد على الأقل';
    if (!password.contains(RegExp(r'[0-9]'))) return 'يجب أن تحتوي على رقم واحد على الأقل';
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'يجب أن تحتوي على رمز خاص واحد على الأقل (!@#\$% إلخ)';
    }
    return '';
  }

  void _registerUser() async {
    // Handles user registration and saves user data to Firestore
    setState(() {
      _isSubmitted = true;
      _nameError = _nameController.text.isEmpty ? 'الرجاء إدخال الاسم' : '';
      _emailError = _validateEmail(_emailController.text);
      _passwordError = _validatePassword(_passwordController.text);
      _confirmPasswordError = _confirmPasswordController.text.isEmpty
          ? 'الرجاء تأكيد كلمة المرور'
          : (_passwordController.text != _confirmPasswordController.text
              ? 'كلمتا المرور غير متطابقتين'
              : '');
      _signupError = '';
    });

    if (_nameError.isEmpty &&
        _emailError.isEmpty &&
        _passwordError.isEmpty &&
        _confirmPasswordError.isEmpty) {
      try {
        UserCredential userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        User? user = userCredential.user;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
            'username': _nameController.text.trim(),
            'email': _emailController.text.trim(),
          });
          Navigator.of(context).pushReplacementNamed('/mainpage');
        }
      } on FirebaseAuthException catch (e) {
        // Handle Firebase-specific errors during registration
        setState(() {
          if (e.code == 'weak-password') {
            _passwordError = 'كلمة المرور ضعيفة جدًا';
          } else if (e.code == 'email-already-in-use') {
            _signupError = 'البريد الإلكتروني مستخدم بالفعل';
          } else {
            _signupError = 'حدث خطأ أثناء التسجيل. يرجى المحاولة مرة أخرى.';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Builds the signup page UI
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient and decorative elements
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.shade50,
                  Colors.white.withOpacity(0.8),
                  Colors.blue.shade100,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).size.height * 0.12,
            left: MediaQuery.of(context).size.width * 0.05,
            child: Opacity(
              opacity: 0.2,
              child: Transform.rotate(
                angle: 0.3,
                child: Container(
                  height: 70,
                  width: 140,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade800,
                    borderRadius: BorderRadius.circular(35),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.22,
            right: MediaQuery.of(context).size.width * 0.1,
            child: Opacity(
              opacity: 0.15,
              child: Transform.rotate(
                angle: -0.5,
                child: Container(
                  height: 60,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade800,
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          ),

          // Back Button
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(
              icon: Icon(Icons.arrow_back_ios, color: Colors.blue.shade800),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Main Content
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Animated Logo/Icon - Smaller size
                    ScaleTransition(
                      scale: _animation,
                      child: Container(
                        width: 90, // Reduced from 120
                        height: 90, // Reduced from 120
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.shade200.withOpacity(0.5),
                              blurRadius: 15, // Reduced from 20
                              spreadRadius: 3, // Reduced from 5
                            ),
                          ],
                        ),
                        child: Icon(
                            Icons.person_add_rounded,
                            size: 45, // Reduced from 60
                            color: Colors.blue.shade800
                        ),
                      ),
                    ),
                    const SizedBox(height: 20), // Reduced from 30

                    // Title
                    Text(
                      "إنشاء حساب",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28, // Reduced from 32
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                        letterSpacing: 1.5,
                        shadows: [
                          Shadow(
                            color: Colors.blue.shade100,
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15), // Reduced from 30

                    // Name field with card styling
                    Card(
                      elevation: 4,
                      shadowColor: Colors.blue.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3.0), // Reduced from 4.0
                        child: TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: "الاسم",
                            labelStyle: TextStyle(color: Colors.blue.shade600),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: Icon(Icons.person, color: Colors.blue.shade800),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16), // Reduced from vertical: 16
                          ),
                        ),
                      ),
                    ),
                    if (_isSubmitted && _nameError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 12), // Reduced from top: 8
                        child: Text(
                          _nameError,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12), // Reduced from fontSize: 13
                          textAlign: TextAlign.right,
                        ),
                      ),
                    const SizedBox(height: 10), // Reduced from 16

                    Card(
                      elevation: 4,
                      shadowColor: Colors.blue.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3.0), // Reduced from 4.0
                        child: TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textDirection: TextDirection.ltr, // Email is always LTR
                          decoration: InputDecoration(
                            labelText: "البريد الإلكتروني",
                            labelStyle: TextStyle(color: Colors.blue.shade600),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: Icon(Icons.email, color: Colors.blue.shade800),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          ),
                        ),
                      ),
                    ),
                    if (_isSubmitted && _emailError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 12),
                        child: Text(
                          _emailError,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    const SizedBox(height: 10),

                    // Password field
                    Card(
                      elevation: 4,
                      shadowColor: Colors.blue.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3.0),
                        child: TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: "كلمة المرور",
                            labelStyle: TextStyle(color: Colors.blue.shade600),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: Icon(Icons.lock, color: Colors.blue.shade800),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                color: Colors.blue.shade700,
                                size: 20,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          ),
                        ),
                      ),
                    ),
                    if (_isSubmitted && _passwordError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 12),
                        child: Text(
                          _passwordError,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    const SizedBox(height: 10),

                    // Confirm Password field
                    Card(
                      elevation: 4,
                      shadowColor: Colors.blue.shade100,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(3.0),
                        child: TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            labelText: "تأكيد كلمة المرور",
                            labelStyle: TextStyle(color: Colors.blue.shade600),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: Icon(Icons.lock_outline, color: Colors.blue.shade800),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                                color: Colors.blue.shade700,
                                size: 20, // Reduced from 22
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword = !_obscureConfirmPassword;
                                });
                              },
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          ),
                        ),
                      ),
                    ),
                    if (_isSubmitted && _confirmPasswordError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 12),
                        child: Text(
                          _confirmPasswordError,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    const SizedBox(height: 15),

                    // Error message display
                    if (_signupError.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          _signupError,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 13, // Reduced from 14
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                    // Signup Button with gradient and elevation
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.shade200.withOpacity(0.5),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade700, Colors.blue.shade900],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: _registerUser,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add, size: 20),
                            SizedBox(width: 10),
                            Text(
                              "إنشاء حساب",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Login redirect section
                    Container(
                      margin: const EdgeInsets.only(top: 20, bottom: 15),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "لديك حساب؟",
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pushNamed(context, '/login'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue.shade800,
                              padding: EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: Text(
                              "تسجيل الدخول",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
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
    // Dispose controllers to free resources
    _controller.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
