import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart'; // If using App Check
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // If using .env
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// Import your page/widget files
import 'package:mudhkir_app/Pages/SettingsPage.dart';
import 'package:mudhkir_app/Pages/companions.dart';
import 'package:mudhkir_app/Pages/personal_data.dart';
import 'package:mudhkir_app/pages/add_dose.dart' as add_dose;
import 'package:mudhkir_app/pages/login.dart';
import 'package:mudhkir_app/pages/mainpage.dart';
import 'package:mudhkir_app/pages/signup.dart';
import 'package:mudhkir_app/pages/welcome.dart';
import 'package:mudhkir_app/pages/dose_schedule.dart' as dose_schedule;
import 'package:mudhkir_app/pages/ForgetPassword.dart';
import 'package:mudhkir_app/Widgets/AuthWrapper.dart';
import 'package:mudhkir_app/Pages/MedicationDetailPage.dart';

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Local notifications plugin instance
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

// --- Background Message Handler (FCM) ---
@pragma('vm:entry-point') // Ensures tree shaking doesn't remove this
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(); // Required for background isolate
  print("Handling a background FCM message: ${message.messageId}");
  // Add logic here if you use FCM data messages to trigger actions/notifications
}

// --- Schedule Local Notification Function ---
Future<void> scheduleNotification({
  required int id,
  required String title,
  required String body,
  required DateTime scheduledTime,
  required String docId, // Payload to identify the dose/reminder
}) async {
  // ADDED LOG: Check received docId
  print("[ScheduleNotification] Received call with docId: '$docId', id: $id");

  try {
    final prefs = await SharedPreferences.getInstance();
    final bool vibrationEnabled = prefs.getBool('vibrationEnabled') ?? true;
    final bool soundEnabled = prefs.getBool('soundEnabled') ?? true;

    // Determine Channel ID and Name based on settings
    String channelId = 'medication_channel';
    String channelName = 'Medication Reminders';
    if (soundEnabled && vibrationEnabled) {
      channelId += '_sound_on_vib_on';
      channelName += ' (Sound & Vibration)';
    } else if (soundEnabled && !vibrationEnabled) {
      channelId += '_sound_on_vib_off';
      channelName += ' (Sound Only)';
    } else if (!soundEnabled && vibrationEnabled) {
      channelId += '_sound_off_vib_on';
      channelName += ' (Vibration Only)';
    } else {
      channelId += '_sound_off_vib_off';
      channelName += ' (Silent)';
    }

    // Configure Android Notification Details
    final Int64List? vibrationPattern = vibrationEnabled
        ? Int64List.fromList([0, 500, 100, 500, 100, 1000]) // Example pattern
        : null;

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Channel for medication reminders based on user settings.',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      enableVibration: vibrationEnabled,
      vibrationPattern: vibrationPattern,
      playSound: soundEnabled,
      sound: soundEnabled ? const RawResourceAndroidNotificationSound('alarm_sound') : null,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableLights: true,
      ledColor: Colors.red,
      ledOnMs: 1000,
      ledOffMs: 500,
      ongoing: true,
      autoCancel: false,
      timeoutAfter: 120000, // 2 minutes
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
    );

    // Configure iOS/macOS Notification Details (Basic)
    const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    // Combine Platform Details
    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // Payload Handling
    final String payload = docId.isNotEmpty ? docId : "no_doc_id_${id}";
    print('[ScheduleNotification] Scheduling notification ID: $id with payload: $payload for time: $scheduledTime');

    // Schedule the Notification using Timezone-aware DateTime
    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
      matchDateTimeComponents: DateTimeComponents.time, // Repeats daily
    );

    print('[ScheduleNotification] Successfully scheduled notification $id for $scheduledTime (repeats daily). Payload: $payload');

  } catch (e, stacktrace) {
    print('[ScheduleNotification] Error scheduling notification $id: $e');
    print('[ScheduleNotification] Stacktrace: $stacktrace');
  }
}

// --- Reschedule All Notifications Function ---
Future<void> rescheduleAllNotifications() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    print("[Reschedule] Failed: User not logged in.");
    return;
  }
  print("[Reschedule] Starting process for user ${user.uid}...");

  try {
    // Cancel All Existing Notifications first
    print("[Reschedule] Cancelling all previous notifications...");
    await flutterLocalNotificationsPlugin.cancelAll();
    print("[Reschedule] Previous notifications cancelled.");

    // Fetch Medications
    final medsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('medicines')
        .get();
    print("[Reschedule] Found ${medsSnapshot.docs.length} medicine documents.");

    int notificationIdCounter = 0;
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

    for (var doc in medsSnapshot.docs) {
      final data = doc.data();
      final String medicationName = data['name'] ?? 'Unnamed Medicine';
      final List<dynamic> timesRaw = data['times'] ?? [];
      final String frequencyType = data['frequencyType'] ?? 'يومي';
      final String docId = doc.id; // Get the document ID

      // ADDED LOG: Check the docId being processed
      print("[Reschedule] >>>>> CHECKING DOC ID: '$docId' for medication '$medicationName'");

      if (frequencyType == 'يومي') {
        print("[Reschedule] Processing daily medication: $medicationName (ID: $docId)");
        for (var timeStr in timesRaw) {
          final TimeOfDay? time = add_dose.TimeUtils.parseTime(timeStr.toString());
          if (time != null) {
            tz.TZDateTime scheduledTime = tz.TZDateTime(
              tz.local, now.year, now.month, now.day, time.hour, time.minute,
            );
            if (scheduledTime.isBefore(now)) {
              scheduledTime = scheduledTime.add(const Duration(days: 1));
              print("[Reschedule] Time $timeStr already passed today. Scheduling first occurrence for tomorrow: $scheduledTime");
            } else {
              print("[Reschedule] Scheduling first occurrence for today: $scheduledTime");
            }

            int uniqueNotificationId = (docId.hashCode ^ time.hashCode) + notificationIdCounter;
            notificationIdCounter++;

            print("[Reschedule] >>> Scheduling Check: Medication ID: $docId, Time: $timeStr, Notification ID: $uniqueNotificationId");

            // Ensure docId is not empty before scheduling
            if (docId.isEmpty) {
              print("[Reschedule] ERROR: docId is empty for medication '$medicationName'. Skipping scheduling for time $timeStr.");
              continue; // Skip this time slot if docId is invalid
            }

            await scheduleNotification(
              id: uniqueNotificationId,
              title: 'تذكير الدواء',
              body: 'حان وقت تناول $medicationName',
              scheduledTime: scheduledTime,
              docId: docId, // Pass Firestore document ID as payload
            );
          } else {
            print("[Reschedule] WARN: Could not parse time string: '$timeStr' for medication $docId");
          }
        }
      } else {
        print("[Reschedule] INFO: Skipping medication $docId with frequencyType '$frequencyType'.");
      }
    }
    print("[Reschedule] Process completed.");

  } catch (e, stacktrace) {
    print("[Reschedule] ERROR during rescheduling: $e");
    print("[Reschedule] Stacktrace: $stacktrace");
  }
}

// --- Request Permissions Function ---
Future<void> requestRequiredPermissions() async {
  print("[Permissions] Requesting necessary permissions...");
  // Notification Permission
  if (await Permission.notification.isDenied || await Permission.notification.isPermanentlyDenied) {
    print("[Permissions] Requesting Notification permission...");
    final notificationStatus = await Permission.notification.request();
    print("[Permissions] Notification permission status: $notificationStatus");
    if (notificationStatus.isPermanentlyDenied) {
      print("[Permissions] WARN: Notification permission permanently denied.");
    }
  } else {
    print("[Permissions] Notification permission already granted.");
  }
  // Exact Alarm Permission (Android)
  if (Platform.isAndroid) {
    if (await Permission.scheduleExactAlarm.isDenied || await Permission.scheduleExactAlarm.isPermanentlyDenied) {
      print("[Permissions] Requesting Schedule Exact Alarm permission...");
      final alarmStatus = await Permission.scheduleExactAlarm.request();
      print("[Permissions] Schedule Exact Alarm permission status: $alarmStatus");
      if (alarmStatus.isPermanentlyDenied) {
        print("[Permissions] WARN: Schedule Exact Alarm permission permanently denied.");
      }
    } else {
      print("[Permissions] Schedule Exact Alarm permission already granted.");
    }
    print("[Permissions] Note: USE_FULL_SCREEN_INTENT permission is declared in AndroidManifest.xml.");
  }
  print("[Permissions] Permission check complete.");
}

// --- Main Application Widget ---
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
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const Login(),
        '/signup': (context) => const Signup(),
        '/mainpage': (context) => const MainPage(),
        '/add_dose': (context) => const add_dose.AddDose(),
        '/dose_schedule': (context) => const dose_schedule.DoseSchedule(),
        '/personal_data': (context) => const PersonalDataPage(),
        '/settings': (context) => const SettingsPage(),
        '/companions': (context) => const Companions(),
        '/forget_password': (context) => const ForgetPassword(),
        '/welcome': (context) => const Welcome(),
        '/medication_detail': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          String docId = '';
          if (args is Map<String, dynamic> && args.containsKey('docId')) {
            docId = args['docId'] as String? ?? '';
          } else if (args is String) {
            docId = args;
          }
          if (docId.isEmpty) {
            print("WARN: Navigating to /medication_detail without a valid docId argument.");
          }
          return MedicationDetailPage(docId: docId);
        },
      },
    );
  }
}

// --- Main Entry Point ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env (optional)
  await dotenv.load(fileName: ".env").catchError((e) {
    print("Could not load .env file (this might be normal): $e");
  });

  // Initialize Firebase
  await Firebase.initializeApp();
  print("[Firebase] Initialization complete.");

  // Initialize App Check (optional)
  // await FirebaseAppCheck.instance.activate(...);

  // Request Permissions Early
  await requestRequiredPermissions();

  // Initialize Timezones
  tz.initializeTimeZones();
  try {
    tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
    print("[Timezone] Local timezone set to Asia/Riyadh.");
  } catch (e) {
    print("[Timezone] ERROR setting local timezone: $e. Using system default.");
  }

  // Firebase Messaging Setup
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings fcmSettings = await messaging.requestPermission(
    alert: true, badge: true, sound: true, provisional: false,
  );
  print('[FCM] User granted permission: ${fcmSettings.authorizationStatus}');
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('[FCM] Got a message whilst in the foreground: ${message.messageId}');
    // Decide if you need to handle foreground FCM messages
  });

  // Local Notifications Initialization
  const AndroidInitializationSettings androidSettings =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings darwinSettings = DarwinInitializationSettings(
    requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false,
  );
  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings, iOS: darwinSettings, macOS: darwinSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    // Callback when notification is tapped (App IS RUNNING)
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      final String? payload = response.payload;
      print("[Notification Tap - Running] Tapped! Payload: ${payload ?? 'NULL'}");

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print("[Notification Tap - Running] Cannot navigate: User not logged in.");
        return;
      }
      if (payload == null || payload.isEmpty) {
        print("[Notification Tap - Running] Cannot navigate: Payload is null or empty.");
        return;
      }
      if (payload.startsWith("no_doc_id_")) {
        print("[Notification Tap - Running] Fallback/Test payload detected - no navigation.");
        return;
      }

      print("[Notification Tap - Running] Attempting navigation to MedicationDetailPage with docId: $payload");
      Future.delayed(const Duration(milliseconds: 100), () {
        if (navigatorKey.currentState != null) {
          try {
            navigatorKey.currentState!.pushNamed(
              '/medication_detail', arguments: {'docId': payload},
            );
            print("[Notification Tap - Running] Navigation successful.");
          } catch (e) {
            print("[Notification Tap - Running] ERROR during navigation: $e");
          }
        } else {
          print("[Notification Tap - Running] ERROR: NavigatorKey.currentState is NULL.");
        }
      });
    },
  );

  // Check if App was Launched by Notification (App WAS TERMINATED)
  final NotificationAppLaunchDetails? appLaunchDetails = await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
  if (appLaunchDetails != null && appLaunchDetails.didNotificationLaunchApp) {
    final String? payload = appLaunchDetails.notificationResponse?.payload;
    print("[Notification Launch] App launched via notification.");
    print("[Notification Launch] Payload: ${payload ?? 'NULL'}");

    if (payload != null && payload.isNotEmpty && !payload.startsWith("no_doc_id_")) {
      print("[Notification Launch] Valid payload found: $payload. Will navigate after init.");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        print("[Notification Launch] Post frame callback executing...");
        final currentUser = FirebaseAuth.instance.currentUser;
        final navigatorState = navigatorKey.currentState;
        if (currentUser != null && navigatorState != null) {
          print("[Notification Launch] User logged in and navigator ready. Navigating...");
          try {
            navigatorState.pushNamed(
              '/medication_detail', arguments: {'docId': payload},
            );
            print("[Notification Launch] Navigation successful.");
          } catch (e) {
            print("[Notification Launch] ERROR during navigation: $e");
          }
        } else {
          print('[Notification Launch] Navigation skipped: User=${currentUser?.uid ?? 'NULL'}, Navigator State=${navigatorState == null ? 'NULL' : 'Ready'}');
        }
      });
    } else {
      print('[Notification Launch] No navigation needed - Payload invalid or fallback/test.');
    }
  } else {
    print("[Notification Launch] App was not launched via notification tap.");
  }

  // Initialize date formatting
  await initializeDateFormatting('ar_SA', null);
  print("[Localization] Arabic date formatting initialized.");

  // Run the app
  print("[Startup] Running the app...");
  runApp(const MyApp());
}

// --- Example Test Notification Function (Optional) ---
Future<void> _sendTestNotification(BuildContext context) async {
  print("[Test Notification] Scheduling test notification...");
  final now = DateTime.now();
  final testTime = now.add(const Duration(seconds: 5));
  await scheduleNotification(
    id: 99999, // Unique ID for test
    title: "تذكير تجريبي",
    body: "هذا إشعار تجريبي. اضغط للاختبار.",
    scheduledTime: testTime,
    docId: 'test_payload_123', // Use a clear test payload
  );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("تم جدولة إشعار تجريبي (سيظهر خلال 5 ثوانٍ)"),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }
  print("[Test Notification] Test notification scheduled.");
}