import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mudhkir_app/Core/Services/AlarmNotificationHelper.dart';
import 'package:mudhkir_app/Features/Main/Main_Page.dart';
import 'package:mudhkir_app/Features/Welcome/Welcome_Page.dart';
import 'package:mudhkir_app/main.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    
    // Complete notification initialization with context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AlarmNotificationHelper.completeInitialization(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          User? user = snapshot.data;
          if (user == null) {
            // User is not logged in
            return const Welcome();
          } else {
            // Set up periodic companion checks when user logs in
            setupPeriodicCompanionChecks();
            
            // User is logged in
            return const MainPage();
          }
        }
        
        // Checking auth state
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}
