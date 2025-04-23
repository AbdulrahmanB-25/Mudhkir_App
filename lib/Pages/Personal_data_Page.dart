import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mudhkir_app/Pages/ForgetPassword_Page.dart';
import 'package:mudhkir_app/Widgets/bottom_navigation.dart';


const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

//TODO : EMAIL MODIFCATION

class PersonalDataPage extends StatefulWidget {
  const PersonalDataPage({super.key});

  @override
  _PersonalDataPageState createState() => _PersonalDataPageState();
}

class _PersonalDataPageState extends State<PersonalDataPage> with SingleTickerProviderStateMixin {
  final int _selectedIndex = 1; // 1 is for Profile
  String _username = '';
  String _email = '';
  bool _isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  final TextEditingController _usernameController = TextEditingController();
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    // Set up fade-in animation
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();

    fetchUserData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> fetchUserData() async {
    setState(() => _isLoading = true);
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists && userDoc.data() != null) {
          if (mounted) {
            setState(() {
              _username = (userDoc.data() as Map<String, dynamic>)['username'] ?? 'مستخدم';
              _email = user.email ?? 'لا يوجد بريد إلكتروني';
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _username = 'مستخدم';
              _email = user.email ?? 'لا يوجد بريد إلكتروني';
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        print("Error fetching user data: $e");
        if (mounted) {
          setState(() {
            _username = 'مستخدم';
            _email = user.email ?? 'لا يوجد بريد إلكتروني';
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _username = '';
          _email = '';
          _isLoading = false;
        });

        // Navigate to login if not authenticated
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacementNamed(context, "/login");
        });
      }
    }
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      Navigator.pushReplacementNamed(context, '/mainpage');
    } else if (index == 2) {
      Navigator.pushReplacementNamed(context, '/settings');
    }
  }

  // Show dialog to edit username
  Future<void> _showEditProfileDialog() async {
    _usernameController.text = _username;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'تعديل البيانات الشخصية',
            style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'اسم المستخدم',
                      labelStyle: TextStyle(color: kPrimaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: kPrimaryColor, width: 2),
                      ),
                      prefixIcon: Icon(Icons.person, color: kPrimaryColor),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'الرجاء إدخال اسم المستخدم';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('إلغاء', style: TextStyle(color: Colors.grey.shade700)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            _isUpdating
                ? Center(child: CircularProgressIndicator(color: kPrimaryColor))
                : ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('حفظ'),
              onPressed: () async {
                await _updateProfile();
                if (mounted) Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // Update profile information in Firestore
  Future<void> _updateProfile() async {
    if (_usernameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('الرجاء إدخال اسم المستخدم')),
            ],
          ),
          backgroundColor: kErrorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(10),
        ),
      );
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'username': _usernameController.text.trim(),
          'lastUpdated': Timestamp.now(),
        });

        // Update local state
        setState(() {
          _username = _usernameController.text.trim();
          _isUpdating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'تم تحديث البيانات الشخصية بنجاح',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: EdgeInsets.all(10),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isUpdating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('حدث خطأ أثناء تحديث البيانات: $e')),
            ],
          ),
          backgroundColor: kErrorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(10),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false, // added to remove back button
        title: const Text(
          "الملف الشخصي",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: kPrimaryColor,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        actions: [],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kPrimaryColor.withOpacity(0.1),
              kBackgroundColor,
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.3, 1],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: kPrimaryColor))
              : FadeTransition(
            opacity: _fadeInAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryColor.withOpacity(0.3),
                          blurRadius: 10,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Profile Avatar
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.person,
                            size: 60,
                            color: kPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 15),

                        // Username
                        Text(
                          _username,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        // Email
                        Text(
                          _email,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Personal Info Card
                  _buildSectionHeader("معلومات الحساب"),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Username field
                        _buildInfoRow(
                          icon: Icons.person_outline_rounded,
                          label: "اسم المستخدم",
                          value: _username,
                        ),

                        const Divider(height: 25),

                        // Email field
                        _buildInfoRow(
                          icon: Icons.email_outlined,
                          label: "البريد الإلكتروني",
                          value: _email,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Account Actions
                  _buildSectionHeader("إجراءات الحساب"),

                  // Edit Profile Button
                  _buildActionButton(
                    icon: Icons.edit_outlined,
                    label: "تعديل البيانات الشخصية",
                    color: kSecondaryColor,
                    onPressed: () {
                      _showEditProfileDialog();
                    },
                  ),

                  const SizedBox(height: 15),

                  // Change Password Button
                  _buildActionButton(
                    icon: Icons.lock_outline,
                    label: "تغيير كلمة المرور",
                    color: kPrimaryColor,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ForgetPassword(fromPersonalData: true),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 15),

                  // Logout Button
                  _buildActionButton(
                    icon: Icons.logout,
                    label: "تسجيل الخروج",
                    color: kErrorColor,
                    onPressed: () async {
                      // Show confirmation dialog
                      final shouldLogout = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("تسجيل الخروج", textAlign: TextAlign.right),
                          content: const Text(
                            "هل أنت متأكد من تسجيل الخروج من حسابك؟",
                            textAlign: TextAlign.right,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: Text("إلغاء", style: TextStyle(color: Colors.grey.shade700)),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kErrorColor,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text("تسجيل الخروج"),
                            ),
                          ],
                        ),
                      );

                      if (shouldLogout == true) {
                        await FirebaseAuth.instance.signOut();
                        if (mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil(
                              '/welcome',
                                  (route) => false
                          );
                        }
                      }
                    },
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              height: 24,
              width: 4,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const Divider(height: 24, thickness: 1),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kPrimaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: kPrimaryColor,
            size: 22,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kBorderRadius),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kBorderRadius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(kBorderRadius),
          splashColor: color.withOpacity(0.1),
          highlightColor: color.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_ios,
                  color: color,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

