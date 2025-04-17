import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mudhkir_app/pages/welcome.dart';
import 'package:mudhkir_app/pages/mainpage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  String? _redirectDocId;
  bool _allowMainPageAccess = false; // Changed default to false

  @override
  void initState() {
    super.initState();
    _checkAuth();
    // Removing this call since we don't want to allow unauthenticated access
    // _checkMainPageAccessSettings();
  }

  // Keeping this method in case it's used elsewhere, but we won't call it
  Future<void> _checkMainPageAccessSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // Changed default to false to prevent bypassing authentication
      _allowMainPageAccess = prefs.getBool('allowMainPageAccess') ?? false;
    });
  }

  Future<void> _checkAuth() async {
    try {
      // Check auth state
      final user = FirebaseAuth.instance.currentUser;
      setState(() {
        _isAuthenticated = user != null;
      });

      // Check for notification redirect (if authenticated)
      if (_isAuthenticated) {
        final redirectData = await NotificationService.checkRedirect();
        if (redirectData != null) {
          _redirectDocId = redirectData['docId'];
          print("[AuthWrapper] Found notification redirect to medication: $_redirectDocId");
        }
      }
    } catch (e) {
      print("[AuthWrapper] Error in auth check: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.white, Colors.blue.shade100],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: CircularProgressIndicator(color: Colors.blue.shade700),
          ),
        ),
      );
    }

    // Handle the medication detail redirect if we have a docId
    if (_isAuthenticated && _redirectDocId != null && _redirectDocId!.isNotEmpty) {
      // Clear the redirect data to prevent future redirects
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // Clear data first to prevent loops
        await NotificationService.clearRedirectData();
        
        print("[AuthWrapper] Navigating to medication details for: $_redirectDocId");
        
        // Give the app time to fully initialize before navigating
        await Future.delayed(const Duration(milliseconds: 200));
        
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pushReplacementNamed(
            '/medication_detail',
            arguments: {'docId': _redirectDocId},
          );
        } else if (mounted) {
          Navigator.of(context).pushNamed(
            '/medication_detail',
            arguments: {'docId': _redirectDocId},
          );
        }
      });
      
      // Return a loading screen while navigation is being set up
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.white, Colors.blue.shade100],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.blue.shade700),
                const SizedBox(height: 20),
                Text(
                  "جاري فتح تفاصيل الدواء...",
                  style: TextStyle(fontSize: 16, color: Colors.blue.shade800),
                )
              ],
            ),
          ),
        ),
      );
    }

    // Modified to only return MainPage if the user is authenticated
    return _isAuthenticated ? const MainPage() : const Welcome();
  }
}
