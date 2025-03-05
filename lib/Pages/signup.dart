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
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

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
    if (email.isEmpty) return 'الرجاء إدخال البريد الإلكتروني';
    if (!RegExp(r"^[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+$").hasMatch(email)) {
      return 'تنسيق البريد الإلكتروني غير صحيح';
    }
    return '';
  }

  String _validatePassword(String password) {
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
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScaleTransition(
                      scale: _animation,
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.blue.shade50,
                        child: Icon(Icons.person_add,
                            size: 60, color: Colors.blue.shade800),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      "إنشاء حساب",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800),
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(_nameController, "الاسم", Icons.person, _nameError),
                    _buildTextField(_emailController, "البريد الإلكتروني", Icons.email, _emailError),
                    _buildPasswordField(),
                    _buildConfirmPasswordField(),
                    if (_signupError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _signupError,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.red,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ElevatedButton(
                      onPressed: _registerUser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text("إنشاء حساب",
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("لديك حساب؟ ",
                            style: TextStyle(color: Colors.blue.shade800)),
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/login'),
                          child: Text("تسجيل الدخول",
                              style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      IconData icon, String error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: Colors.blue.shade50,
            prefixIcon: Icon(icon, color: Colors.blue.shade800),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_isSubmitted && error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(error, style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: "كلمة المرور",
            filled: true,
            fillColor: Colors.blue.shade50,
            prefixIcon: Icon(Icons.lock, color: Colors.blue.shade800),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.blue.shade800,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_isSubmitted && _passwordError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(_passwordError,
                style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _buildConfirmPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            labelText: "تأكيد كلمة المرور",
            filled: true,
            fillColor: Colors.blue.shade50,
            prefixIcon:
            Icon(Icons.lock_outline, color: Colors.blue.shade800),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_off
                    : Icons.visibility,
                color: Colors.blue.shade800,
              ),
              onPressed: () {
                setState(
                        () => _obscureConfirmPassword = !_obscureConfirmPassword);
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_isSubmitted && _confirmPasswordError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(_confirmPasswordError,
                style: const TextStyle(color: Colors.red)),
          ),
        const SizedBox(height: 15),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}