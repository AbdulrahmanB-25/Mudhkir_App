import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mudhkir_app/Pages/CompanionDetailPage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your page/widget files
import 'package:mudhkir_app/Pages/SettingsPage.dart';
import 'package:mudhkir_app/Pages/companions.dart';
import 'package:mudhkir_app/Pages/Personal_data_Page.dart';
import 'package:mudhkir_app/pages/Add_Medication_Page.dart' as add_dose;
import 'package:mudhkir_app/pages/Login_Page.dart';
import 'package:mudhkir_app/pages/Main_Page.dart';
import 'package:mudhkir_app/pages/Signup_Page.dart';
import 'package:mudhkir_app/pages/Welcome_Page.dart';
import 'package:mudhkir_app/MedicationsSchedule_Utility/dose_schedule_UI.dart';
import 'package:mudhkir_app/pages/ForgetPassword_Page.dart';
import 'package:mudhkir_app/Widgets/AuthWrapper.dart';
import 'package:mudhkir_app/Pages/MedicationDetail_Page.dart';

// Import AlarmNotificationHelper
import 'package:mudhkir_app/services/AlarmNotificationHelper.dart';

import 'Pages/Medications_Schedule_Page.dart';

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();

// SharedPreferences Keys
const String PREF_NEXT_DOSE_DOC_ID = 'next_dose_doc_id';
const String PREF_NEXT_DOSE_TIME_ISO = 'next_dose_time_iso'; // Store as UTC ISO8601 String
const String PREF_CONFIRMATION_SHOWN_PREFIX = 'confirmation_shown_for_';

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
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const Login(),
        '/signup': (context) => const Signup(),
        '/mainpage': (context) => const MainPage(),
        '/add_dose': (context) => const add_dose.AddDose(),
        '/dose_schedule': (context) => const DoseSchedule(),
        '/personal_data': (context) => const PersonalDataPage(),
        '/settings': (context) => const SettingsPage(),
        '/companions': (context) => const Companions(),
        '/forget_password': (context) => const ForgetPassword(),
        '/welcome': (context) => const Welcome(),
        
        '/companion_detail': (context) {
           final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
            return CompanionDetailPage(
             email: args['email'],
             name: args['name'],
          );
       },

      

        '/medication_detail': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          String docId = '';
          bool fromNotification = false;
          bool needsConfirmation = false;
          String? confirmationTimeIso;
          String? confirmationKey;

          if (args is Map<String, dynamic>) {
            docId = args['docId'] as String? ?? '';
            fromNotification = args['fromNotification'] as bool? ?? false;
            needsConfirmation = args['needsConfirmation'] as bool? ?? false;
            confirmationTimeIso = args['confirmationTimeIso'] as String?;
            confirmationKey = args['confirmationKey'] as String?;
          } else if (args is String) {
            docId = args;
          }

          if (docId.isEmpty) {
            print("ERROR: Navigating to /medication_detail without a valid docId argument.");
            // Return an error page or navigate back
            return Scaffold(
              appBar: AppBar(title: Text("خطأ")),
              body: Center(child: Text("خطأ: معرف الدواء غير موجود للوصول لهذه الصفحة.")),
            );
          }

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

Future<void> _handleNotificationPayload(String? medId) async {
  if (medId != null && medId.isNotEmpty) {
    final now = DateTime.now().toIso8601String();
    print("Notification tapped! Medication ID: $medId at $now");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_tapped_payload', medId);
    await prefs.setString('last_tapped_time', now);

    navigatorKey.currentState?.pushNamed('/medication_detail', arguments: {'docId': medId, 'fromNotification': true});
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AndroidAlarmManager.initialize();

  // Request notification permissions at the very start
  await _requestEssentialPermissions();

  // Initialize Localization
  try {
    await initializeDateFormatting('ar_SA', null);
    print("[Localization] Initialized Arabic (Saudi Arabia) locale data.");
  } catch (e) {
    print("[Localization] ERROR initializing locale data: $e");
  }

  try {
    await dotenv.load(fileName: ".env");
    print("[Environment] Loaded .env file successfully.");
  } catch (e) {
    print("[Environment] Could not load .env file (this might be normal): $e");
  }

  // Initialize Firebase
  try {
    await Firebase.initializeApp();
    print("[Firebase] Initialization complete.");
  } catch (e) {
    print("[Firebase] ERROR initializing Firebase: $e");
    return;
  }

  // Initialize Timezones
  tz.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
    print("[Timezone] Local timezone set to 'Asia/Riyadh'.");
  } catch (e) {
    print("[Timezone] ERROR setting local timezone 'Asia/Riyadh': $e. Using system default.");
  }

  // Initialize Notifications
  const AndroidInitializationSettings androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  final InitializationSettings initSettings = InitializationSettings(android: androidInit);

  await notificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      await _handleNotificationPayload(response.payload);
    },
  );

  // Handle app launch from notification (killed state)
  final NotificationAppLaunchDetails? details = await notificationsPlugin.getNotificationAppLaunchDetails();
  if (details?.didNotificationLaunchApp ?? false) {
    final medId = details!.notificationResponse?.payload;
    if (medId != null && medId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _handleNotificationPayload(medId);
      });
    }
  }

  // Initialize AlarmNotificationHelper (if it needs initialization)
  try {
    await AlarmNotificationHelper.initialize(navigatorKey.currentContext!);
    print("[Notifications] AlarmNotificationHelper initialized.");
  } catch (e) {
    print("[Notifications] ERROR initializing AlarmNotificationHelper: $e");
  }

  print("[Startup] Running the app...");
  runApp(const MyApp());
}

Future<void> _requestEssentialPermissions() async {
  print("[Permissions] Checking/Requesting essential permissions...");
  List<Permission> permissionsToRequest = [];

  // Request Notification Permission (Android 13+ / iOS)
  var notificationStatus = await Permission.notification.status;
  if (notificationStatus.isDenied) {
    permissionsToRequest.add(Permission.notification);
  }

  // Request Exact Alarm Permission (Android 12+) - Crucial for precise scheduling
  if (Platform.isAndroid) {
    var exactAlarmStatus = await Permission.scheduleExactAlarm.status;
    if (exactAlarmStatus.isDenied) {
      permissionsToRequest.add(Permission.scheduleExactAlarm);
    }
  }

  if (permissionsToRequest.isNotEmpty) {
    print("[Permissions] Requesting: ${permissionsToRequest.map((p) => p.toString()).join(', ')}");
    Map<Permission, PermissionStatus> statuses = await permissionsToRequest.request();
    statuses.forEach((permission, status) {
      print("[Permissions] Status for $permission: $status");
      if (status.isPermanentlyDenied) {
        print("[Permissions] $permission permanently denied. Guide user to settings.");
        // openAppSettings();
      }
    });
  } else {
    print("[Permissions] All checked essential permissions seem granted or not applicable.");
  }
}
