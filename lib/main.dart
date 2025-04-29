import 'dart:io'; // Added this line

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mudhkir_app/Features/Companions/Companion_Details_Page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your page/widget files
import 'package:mudhkir_app/Features/Settings/SettingsPage.dart';
import 'package:mudhkir_app/Features/Companions/Companions_Main_Page.dart';
import 'package:mudhkir_app/Features/Personal_data/Personal_data_Page.dart';
import 'package:mudhkir_app/Features/Medication/Schedule/dose_schedule_UI.dart';
import 'package:mudhkir_app/Features/Auth/AuthWrapper.dart';

// Import AlarmNotificationHelper


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
        '/add_dose': (context) => const AddDose(),
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

    // Handle companion check notifications
    if (medId.startsWith('companion_check_')) {
      print("Processing companion check notification: $medId");
      await CompanionMedicationTracker.processCompanionDoseCheck(medId);
      return;
    } else if (medId.startsWith('companion_missed_')) {
      print("Navigating to companions page from missed dose notification");
      navigatorKey.currentState?.pushNamed('/companions');
      return;
    }

    navigatorKey.currentState?.pushNamed('/medication_detail', arguments: {'docId': medId, 'fromNotification': true});
  }
}

// Add this method to periodically check for missed companion doses
Future<void> _setupPeriodicCompanionChecks() async {
  if (Platform.isAndroid) {
    try {
      const int checkId = 11223344;

      final bool success = await AndroidAlarmManager.periodic(
        const Duration(hours: 1),
        checkId,
        _runCompanionChecks,
        exact: false,
        wakeup: false,
        rescheduleOnReboot: true,
      );

      print("Scheduled periodic companion checks every hour: $success");
    } catch (e) {
      print("Failed to schedule periodic companion checks: $e");
      // The app will still work without the background checks
      // Users will need to manually open the app to check companion medications
    }
  }
}

@pragma('vm:entry-point')
void _runCompanionChecks() async {
  print("Running periodic companion checks");
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await CompanionMedicationTracker.runPendingChecks();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await AndroidAlarmManager.initialize();
    print("[AlarmManager] Initialized successfully");
  } catch (e) {
    print("[AlarmManager] Failed to initialize: $e");
    // Continue without background services
  }

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
  // It's better to initialize this where context is available, e.g., in MyApp or HomePage initState
  // try {
  //   await AlarmNotificationHelper.initialize(navigatorKey.currentContext!); // This context is likely null here
  //   print("[Notifications] AlarmNotificationHelper initialized.");
  // } catch (e) {
  //   print("[Notifications] ERROR initializing AlarmNotificationHelper: $e");
  // }

  // Setup periodic companion checks
  await _setupPeriodicCompanionChecks();

  print("[Startup] Running the app...");
  runApp(const MyApp());
}

Future<void> _requestEssentialPermissions() async {
  print("[Permissions] Checking/Requesting essential permissions...");

  // For Android 13+ (API level 33+), explicitly request POST_NOTIFICATIONS permission
  if (Platform.isAndroid) {
    var notificationStatus = await Permission.notification.status;
    print("[Permissions] Notification permission status: $notificationStatus");

    if (notificationStatus.isDenied) {
      print("[Permissions] Requesting notification permission");
      final status = await Permission.notification.request();
      print("[Permissions] Notification permission request result: $status");
    }

    // Request schedule exact alarm permission (crucial for Android 12+)
    var exactAlarmStatus = await Permission.scheduleExactAlarm.status;
    print("[Permissions] Schedule exact alarm permission status: $exactAlarmStatus");

    if (exactAlarmStatus.isDenied) {
      print("[Permissions] Requesting schedule exact alarm permission");
      final status = await Permission.scheduleExactAlarm.request();
      print("[Permissions] Schedule exact alarm permission request result: $status");
    }

    // Add diagnostic function to check notification settings
    // Delaying this call slightly to ensure widgets are built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize AlarmNotificationHelper here, now that binding is ready
      // and potentially after the first frame is rendered.
      // Still, passing context might be tricky. Consider initializing in a widget.
      if (navigatorKey.currentContext != null) {
        AlarmNotificationHelper.initialize(navigatorKey.currentContext!).then((_) {
          print("[Notifications] AlarmNotificationHelper initialized post-frame.");
          _checkNotificationPermissions(); // Run diagnostics after init
        }).catchError((e) {
          print("[Notifications] ERROR initializing AlarmNotificationHelper post-frame: $e");
          _checkNotificationPermissions(); // Run diagnostics even if init fails
        });
      } else {
        print("[Notifications] Cannot initialize AlarmNotificationHelper post-frame: navigatorKey.currentContext is null.");
        _checkNotificationPermissions(); // Run diagnostics anyway
      }
    });
  }

  print("[Permissions] Essential permissions setup completed");
}

// Add a diagnostic function to check notification permissions after startup
Future<void> _checkNotificationPermissions() async {
  await Future.delayed(Duration(seconds: 2)); // Wait for app to settle

  print("[Diagnostic] Checking all notification-related permissions and settings");

  try {
    // Check permission_handler status
    final notificationStatus = await Permission.notification.status;
    print("[Diagnostic] Permission.notification.status: $notificationStatus");

    final alarmStatus = await Permission.scheduleExactAlarm.status;
    print("[Diagnostic] Permission.scheduleExactAlarm.status: $alarmStatus");

    // Check Flutter Local Notifications Plugin status
    // Use the helper method if it's initialized, otherwise skip or handle error
    try {
      final flutterNotificationsStatus = await AlarmNotificationHelper.checkForNotificationPermissions();
      print("[Diagnostic] Flutter Local Notifications permission status: $flutterNotificationsStatus");
    } catch (e) {
      print("[Diagnostic] Could not check FLN status via helper (likely not initialized): $e");
    }


    // Check pending notifications
    // Use the helper method if it's initialized
    try {
      final pendingNotifications = await AlarmNotificationHelper.getPendingNotifications();
      print("[Diagnostic] Number of pending notifications: ${pendingNotifications.length}");
    } catch(e) {
      print("[Diagnostic] Could not check pending notifications via helper (likely not initialized): $e");
    }


    // Check notification channels (Android only)
    if (Platform.isAndroid) {
      try {
        // Access the plugin directly if the helper isn't reliably initialized yet
        final plugin = notificationsPlugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (plugin != null) {
          final channels = await plugin.getNotificationChannels();
          print("[Diagnostic] Found ${channels?.length ?? 0} notification channels:");
          channels?.forEach((channel) {
            print("[Diagnostic] Channel: ${channel.id}, Name: ${channel.name}, Importance: ${channel.importance.index}");
          });
        } else {
          print("[Diagnostic] Could not resolve AndroidFlutterLocalNotificationsPlugin.");
        }
      } catch (e) {
        print("[Diagnostic] Error checking notification channels: $e");
      }
    }

    print("[Diagnostic] Notification diagnostics completed");
  } catch (e) {
    print("[Diagnostic] Error during notification diagnostics: $e");
  }
}