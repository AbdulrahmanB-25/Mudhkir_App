import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:mudhkir_app/Features/Companions/Companion_Details_Page.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:mudhkir_app/Features/Settings/SettingsPage.dart';
import 'package:mudhkir_app/Features/Companions/Companions_Main_Page.dart';
import 'package:mudhkir_app/Features/Personal_data/Personal_data_Page.dart';
import 'package:mudhkir_app/Features/Auth/AuthWrapper.dart';
import 'Core/Services/AlarmNotificationHelper.dart';
import 'Features/Auth/Forget_Password/ForgetPassword_Page.dart';
import 'Features/Auth/Login/Login_Page.dart';
import 'Features/Auth/Signup/Signup_Page.dart';
import 'Features/Companions/companion_medication_tracker.dart';
import 'Features/Main/Main_Page.dart';
import 'Features/Medication/Add/Add_Medication_Page.dart';
import 'Features/Medication/Schedule/Medications_Schedule_Page.dart';
import 'Features/Welcome/Welcome_Page.dart';
import 'Features/Medication/Detail/MedicationDetail_Page.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String PREF_NEXT_DOSE_DOC_ID = 'next_dose_doc_id';
const String PREF_NEXT_DOSE_TIME_ISO = 'next_dose_time_iso';
const String PREF_CONFIRMATION_SHOWN_PREFIX = 'confirmation_shown_for_';

// Entry point for background notification handling, must be annotated for AOT compilation
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
}

// Background task for companion medication monitoring - must be a top-level function
@pragma('vm:entry-point')
void _runCompanionChecks() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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

// Sets up recurring background tasks to check companion medication status
Future<void> setupPeriodicCompanionChecks() async {
  if (Platform.isAndroid) {
    print("[Periodic Check Setup] Setting up Android Alarm Manager for companion checks.");
    const int checkId = 11223344;
    try {
      await AndroidAlarmManager.cancel(checkId);
      final result = await AndroidAlarmManager.periodic(
        const Duration(minutes: 30),
        checkId,
        _runCompanionChecks,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
      print("[Periodic Check Setup] AndroidAlarmManager.periodic result: $result");
    } catch (e) {
      print("[Periodic Check Setup] Error setting up AndroidAlarmManager: $e");
    }

  } else {
    print("[Periodic Check Setup] Periodic checks using AndroidAlarmManager only supported on Android.");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print("[Main Init] Initializing timezones...");
  tzdata.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
    print("[Main Init] Timezone set to Asia/Riyadh.");
  } catch (e) {
    print("[Main Init] Error setting timezone 'Asia/Riyadh': $e. Using system default.");
  }

  print("[Main Init] Initializing Firebase...");
  await Firebase.initializeApp();
  print("[Main Init] Firebase initialized.");

  print("[Main Init] Initializing date formatting...");
  await initializeDateFormatting('ar_SA', null);
  print("[Main Init] Date formatting initialized.");

  print("[Main Init] Initializing AlarmNotificationHelper (no context)...");
  await AlarmNotificationHelper.initialize(null);
  print("[Main Init] AlarmNotificationHelper initialized (context-dependent features will be initialized later).");

  if (Platform.isAndroid) {
    print("[Main Init] Initializing AndroidAlarmManager...");
    try {
      await AndroidAlarmManager.initialize();
      print("[Main Init] AndroidAlarmManager initialized.");
    } catch (e) {
      print("[Main Init] Error initializing AndroidAlarmManager: $e");
    }
  }

  print("[Main Init] Running app...");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mudhkir App',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Tajawal',
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF2E86C1),
          foregroundColor: Colors.white,
          elevation: 1,
          titleTextStyle: TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold),
        ),
        scaffoldBackgroundColor: Color(0xFFF5F8FA),
      ),
      home: const AuthWrapper(),
      routes: {
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
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is Map<String, dynamic> && args.containsKey('email') && args.containsKey('name')) {
            return CompanionDetailPage(email: args['email'], name: args['name']);
          }
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
          bool autoMarkAsTaken = false;

          if (args is Map<String, dynamic>) {
            docId = args['docId'] as String? ?? '';
            fromNotification = args['fromNotification'] as bool? ?? false;
            needsConfirmation = args['needsConfirmation'] as bool? ?? false;
            confirmationTimeIso = args['confirmationTimeIso'] as String?;
            confirmationKey = args['confirmationKey'] as String?;
            autoMarkAsTaken = args['autoMarkAsTaken'] as bool? ?? false;
          } else if (args is String) {
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
