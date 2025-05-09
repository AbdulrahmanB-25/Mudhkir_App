import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mudhkir_app/Core/Services/AlarmNotificationHelper.dart';
import 'package:mudhkir_app/Features/Main/Main_Page.dart';
import 'package:mudhkir_app/Features/Welcome/Welcome_Page.dart';
import 'package:mudhkir_app/main.dart';

import '../Companions/companion_medication_tracker.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isAuthenticated = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Initialize notifications and schedule user medications
        AlarmNotificationHelper.completeInitialization(context);
        AlarmNotificationHelper.scheduleAllUserMedications(FirebaseAuth.instance.currentUser!.uid);
      }
    });
    FirebaseAuth.instance.authStateChanges().listen((user) {
      _handleAuthStateChange(user);
    });
  }

  Future<void> _handleAuthStateChange(User? user) async {
    // Handles authentication state changes and triggers post-login tasks
    final bool wasAuthenticated = _isAuthenticated;
    setState(() {
      _isAuthenticated = user != null;
      _isLoading = false;
    });
    if (!wasAuthenticated && _isAuthenticated) {
      _postAuthenticationTasks();
    }
  }

  Future<void> _postAuthenticationTasks() async {
    // Fetch and schedule companion medications after login
    await CompanionMedicationTracker.fetchAndScheduleCompanionMedications();
    await setupPeriodicCompanionChecks();
  }

  @override
  Widget build(BuildContext context) {
    // Builds the UI based on authentication state
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          User? user = snapshot.data;
          if (_isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (user == null) {
            return const Welcome();
          } else {
            return const MainPage();
          }
        }
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
