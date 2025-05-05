import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Not used in provided snippet
import 'package:mudhkir_app/Features/Companions/Companion_Details_Page.dart';
// import 'package:permission_handler/permission_handler.dart'; // Not used in provided snippet
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mudhkir_app/Features/Settings/SettingsPage.dart';
import 'package:mudhkir_app/Features/Companions/Companions_Main_Page.dart';
import 'package:mudhkir_app/Features/Personal_data/Personal_data_Page.dart';
import 'package:mudhkir_app/Features/Medication/Schedule/dose_schedule_UI.dart'; // Assuming this is correct path
import 'package:mudhkir_app/Features/Auth/AuthWrapper.dart';
import 'Core/Services/AlarmNotificationHelper.dart';
import 'Features/Auth/Forget_Password/ForgetPassword_Page.dart';
import 'Features/Auth/Login/Login_Page.dart';
import 'Features/Auth/Signup/Signup_Page.dart';
import 'Features/Companions/companion_medication_tracker.dart';
import 'Features/Main/Main_Page.dart';
import 'Features/Medication/Add/Add_Medication_Page.dart';
// import 'Features/Medication/Schedule/Medications_Schedule_Page.dart'; // Commented out as dose_schedule_UI is imported
import 'Features/Medication/Schedule/Medications_Schedule_Page.dart';
import 'Features/Welcome/Welcome_Page.dart';
import 'Features/Medication/Detail/MedicationDetail_Page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String PREF_NEXT_DOSE_DOC_ID = 'next_dose_doc_id';
const String PREF_NEXT_DOSE_TIME_ISO = 'next_dose_time_iso';
const String PREF_CONFIRMATION_SHOWN_PREFIX = 'confirmation_shown_for_';

// Moved from AlarmNotificationHelper for background isolate access if needed
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final payload = response.payload ?? '';
  final id = response.id ?? 0;
  final actionId = response.actionId ?? 'TAP';
  final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss.SSS ZZZZ').format(DateTime.now());

  print("--------------------------------------------------");
  print("[AlarmHelper BACKGROUND Callback] Timestamp: $timestamp");
  print("[AlarmHelper BACKGROUND Callback] Notification Interaction Received:");
  print("[AlarmHelper BACKGROUND Callback]   ID: $id");
  print("[AlarmHelper BACKGROUND Callback]   Action ID: $actionId");
  print("[AlarmHelper BACKGROUND Callback]   Payload: $payload");
  print("--------------------------------------------------");

  // Minimal logic: Store payload for foreground app to maybe pick up later
  // SharedPreferences.getInstance().then((prefs) {
  //   prefs.setString('background_tapped_payload', payload);
  //   prefs.setString('background_tapped_action', actionId);
  //   prefs.setString('background_tapped_time', DateTime.now().toIso8601String());
  // });
}

// Background task runner for AndroidAlarmManager
@pragma('vm:entry-point')
void _runCompanionChecks() async {
  // Ensure initialization for background isolate
  WidgetsFlutterBinding.ensureInitialized(); // Needed if using plugins requiring platform channels indirectly
  await Firebase.initializeApp(); // Needed for Firestore access
  // Initialize timezones for background isolate too
  tzdata.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
  } catch(e) {
    print("[_runCompanionChecks] Error setting local location: $e. Using default.");
  }
  print("[Background Check] Running periodic companion dose checks...");
  await CompanionMedicationTracker.runPendingChecks();
  print("[Background Check] Periodic companion dose check finished.");
}

// Function to setup periodic checks (call this after user logs in)
Future<void> setupPeriodicCompanionChecks() async {
  if (Platform.isAndroid) {
    print("[Periodic Check Setup] Setting up Android Alarm Manager for companion checks.");
    const int checkId = 11223344; // Unique ID for this periodic task
    try {
      await AndroidAlarmManager.cancel(checkId); // Cancel previous just in case
      final result = await AndroidAlarmManager.periodic(
        const Duration(minutes: 30), // Check every 30 minutes
        checkId,
        _runCompanionChecks,
        exact: true, // Use exact for better timing, but consider battery
        wakeup: true, // Wake device if needed
        rescheduleOnReboot: true, // Ensure it persists after reboot
      );
      print("[Periodic Check Setup] AndroidAlarmManager.periodic result: $result");
    } catch (e) {
      print("[Periodic Check Setup] Error setting up AndroidAlarmManager: $e");
    }

  } else {
    print("[Periodic Check Setup] Periodic checks using AndroidAlarmManager only supported on Android.");
    // Consider alternative background fetch mechanisms for iOS if needed
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Timezones
  print("[Main Init] Initializing timezones...");
  tzdata.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
    print("[Main Init] Timezone set to Asia/Riyadh.");
  } catch (e) {
    print("[Main Init] Error setting timezone 'Asia/Riyadh': $e. Using system default.");
    // Fallback or let system decide
  }


  // 2. Initialize Firebase
  print("[Main Init] Initializing Firebase...");
  await Firebase.initializeApp();
  print("[Main Init] Firebase initialized.");

  // 3. Initialize Date Formatting
  print("[Main Init] Initializing date formatting...");
  await initializeDateFormatting('ar_SA', null);
  print("[Main Init] Date formatting initialized.");

  // 4. Initialize Notifications (basic, without context)
  print("[Main Init] Initializing AlarmNotificationHelper (no context)...");
  await AlarmNotificationHelper.initialize(null);
  print("[Main Init] AlarmNotificationHelper initialized (context-dependent features will be initialized later).");

  // 5. Initialize AndroidAlarmManager (if on Android)
  if (Platform.isAndroid) {
    print("[Main Init] Initializing AndroidAlarmManager...");
    try {
      await AndroidAlarmManager.initialize();
      print("[Main Init] AndroidAlarmManager initialized.");
    } catch (e) {
      print("[Main Init] Error initializing AndroidAlarmManager: $e");
    }
  }

  // 6. Run the App
  print("[Main Init] Running app...");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Note: AlarmNotificationHelper.completeInitialization(context) should be called
    // inside a stateful widget that has context, like AuthWrapper or MainPage's initState.
    return MaterialApp(
      title: 'Mudhkir App',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // Use the global key
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Tajawal', // Ensure this font is added to pubspec.yaml and assets
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF2E86C1), // kPrimaryColor
          foregroundColor: Colors.white,
          elevation: 1,
          titleTextStyle: TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold),
        ),
        scaffoldBackgroundColor: Color(0xFFF5F8FA), // kBackgroundColor
      ),
      // Start with AuthWrapper to handle auth state and trigger post-login setup
      home: const AuthWrapper(),
      routes: {
        // Define all necessary routes using correct widget names
        '/login': (context) => const Login(),
        '/signup': (context) => const Signup(),
        '/mainpage': (context) => const MainPage(),
        '/add_dose': (context) => const AddDose(),
        '/dose_schedule': (context) => const DoseSchedule(),
        '/personal_data': (context) => const PersonalDataPage(),
        '/settings': (context) => const SettingsPage(),
        '/companions': (context) => const Companions(),
        '/forget_password': (context) => const ForgetPassword(),
        '/welcome': (context) => const Welcome(),
        '/companion_detail': (context) {
          // Safe argument extraction
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is Map<String, dynamic> && args.containsKey('email') && args.containsKey('name')) {
            return CompanionDetailPage(email: args['email'], name: args['name']);
          }
          // Fallback error page if arguments are wrong
          return Scaffold(
            appBar: AppBar(title: Text("خطأ")),
            body: Center(child: Text("خطأ: بيانات المرافق غير صحيحة.")),
          );
        },
        '/medication_detail': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          String docId = '';
          bool fromNotification = false;
          bool needsConfirmation = false;
          String? confirmationTimeIso;
          String? confirmationKey;
          bool autoMarkAsTaken = false; // Added from helper logic

          if (args is Map<String, dynamic>) {
            docId = args['docId'] as String? ?? '';
            fromNotification = args['fromNotification'] as bool? ?? false;
            needsConfirmation = args['needsConfirmation'] as bool? ?? false;
            confirmationTimeIso = args['confirmationTimeIso'] as String?;
            confirmationKey = args['confirmationKey'] as String?;
            autoMarkAsTaken = args['autoMarkAsTaken'] as bool? ?? false; // Added
          } else if (args is String) {
            // Handle case where only docId might be passed (less likely now)
            docId = args;
          }

          if (docId.isEmpty) {
            print("[Route Error] /medication_detail: docId is empty.");
            return Scaffold(
              appBar: AppBar(title: Text("خطأ")),
              body: Center(child: Text("خطأ: معرف الدواء غير موجود للوصول لهذه الصفحة.")),
            );
          }

          print("[Route] Navigating to /medication_detail with docId: $docId");
          return MedicationDetailPage(
            docId: docId,
            openedFromNotification: fromNotification,
            needsConfirmation: needsConfirmation,
            confirmationTimeIso: confirmationTimeIso,
            confirmationKey: confirmationKey,
          );
        },
      },
    );
  }
}
