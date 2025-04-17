import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mudhkir_app/Pages/ForgetPassword.dart';
import 'package:mudhkir_app/Widgets/bottom_navigation.dart';

class PersonalDataPage extends StatefulWidget {
  const PersonalDataPage({super.key});

 //TODO : ACCOUNT EDITING AND EMAIL CHANGE MAKE IT IN SETTINGS
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
            style: TextStyle(color: Colors.blue.shade800),
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
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      prefixIcon: Icon(Icons.person, color: Colors.blue.shade700),
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
          actions: <Widget>[
            TextButton(
              child: const Text('إلغاء'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            _isUpdating
                ? CircularProgressIndicator(color: Colors.blue.shade700)
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
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
        const SnackBar(content: Text('الرجاء إدخال اسم المستخدم')),
      );
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Update Firestore document
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
            content: const Text('تم تحديث البيانات الشخصية بنجاح'),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isUpdating = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تحديث البيانات: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom Header - Removed back button and centered title
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Center(
                  child: Text(
                    "الملف الشخصي",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              
              // Main Content
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: Colors.blue.shade700))
                    : FadeTransition(
                        opacity: _fadeInAnimation,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // Profile Header with Avatar
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.shade200.withOpacity(0.2),
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
                                        color: Colors.blue.shade50,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.blue.shade200,
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                    const SizedBox(height: 15),
                                    
                                    // Username
                                    Text(
                                      _username,
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade800,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    
                                    // Email
                                    Text(
                                      _email,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.blue.shade600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 25),
                              
                              // Personal Info Card
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.shade200.withOpacity(0.2),
                                      blurRadius: 10,
                                      spreadRadius: 0,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "معلومات الحساب",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 15),
                                    
                                    // Username field
                                    _buildInfoRow(
                                      icon: Icons.person_outline,
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
                                    
                                    const Divider(height: 25),
                                    
                                    // Account type field (just a placeholder, you can modify as needed)
                                    _buildInfoRow(
                                      icon: Icons.verified_user_outlined,
                                      label: "نوع الحساب",
                                      value: "مستخدم عادي",
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 25),
                              
                              // Account Actions
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.shade200.withOpacity(0.2),
                                      blurRadius: 10,
                                      spreadRadius: 0,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "إجراءات الحساب",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue.shade800,
                                      ),
                                    ),
                                    const SizedBox(height: 15),
                                    
                                    // Edit Profile Button
                                    _buildActionButton(
                                      icon: Icons.edit_outlined,
                                      label: "تعديل البيانات الشخصية",
                                      color: Colors.orange.shade700,
                                      onPressed: () {
                                        _showEditProfileDialog();
                                      },
                                    ),
                                    
                                    const SizedBox(height: 15),
                                    
                                    // Change Password Button
                                    _buildActionButton(
                                      icon: Icons.lock_outline,
                                      label: "تغيير كلمة المرور",
                                      color: Colors.blue.shade700,
                                      onPressed: () {
                                        // Update to use Navigator.push with the parameter
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const ForgetPassword(fromPersonalData: true),
                                          ),
                                        );
                                      },
                                    ),
                                    
                                    const SizedBox(height: 15),
                                    
                                    // Logout Button - Updated to navigate to welcome page
                                    _buildActionButton(
                                      icon: Icons.logout,
                                      label: "تسجيل الخروج",
                                      color: Colors.red.shade700,
                                      onPressed: () async {
                                        await FirebaseAuth.instance.signOut();
                                        if (mounted) {
                                          // Navigate to welcome page and clear navigation history
                                          Navigator.of(context).pushNamedAndRemoveUntil(
                                            '/welcome', 
                                            (route) => false
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 30),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
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
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: Colors.blue.shade700,
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
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: color),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          alignment: Alignment.centerRight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: color.withOpacity(0.3)),
          ),
          backgroundColor: color.withOpacity(0.1),
        ),
      ),
    );
  }
}

