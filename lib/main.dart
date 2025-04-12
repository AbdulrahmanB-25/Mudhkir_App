import 'package:flutter/material.dart';
import 'package:mudhkir_app/Pages/SettingsPage.dart';
import 'package:mudhkir_app/Pages/companions.dart';
import 'package:mudhkir_app/Pages/personal_data.dart';
import 'package:mudhkir_app/pages/add_dose.dart' as add_dose; // Alias to avoid conflict
import 'package:mudhkir_app/pages/login.dart';
import 'package:mudhkir_app/pages/mainpage.dart';
import 'package:mudhkir_app/pages/signup.dart';
import 'package:mudhkir_app/pages/welcome.dart';
import 'package:mudhkir_app/pages/dose_schedule.dart' as dose_schedule; // Alias to avoid conflict
import 'package:mudhkir_app/pages/ForgetPassword.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mudhkir_app/Widgets/AuthWrapper.dart'; // Assuming AuthWrapper is in Widgets folder
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Ensure this is imported
import 'dart:io'; // Add this import for platform checks
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';

// Import the intl package localization data initialization function
import 'package:intl/date_symbol_data_local.dart'; // <-- ADD THIS IMPORT
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

Future<void> requestExactAlarmPermission() async {
  try {
    if (Platform.isAndroid && (await Permission.scheduleExactAlarm.isDenied)) {
      final status = await Permission.scheduleExactAlarm.request();
      if (status.isGranted) {
        print("Exact alarm permission granted.");
      } else {
        print("Exact alarm permission denied.");
      }
    }
  } catch (e) {
    print("Error requesting exact alarm permission: $e");
  }
}
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background messages
  if (message.notification != null) {
    // Display local notification for background messages
    final notification = message.notification!;
    flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'medication_channel',
          'Medication Reminders',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigPictureStyleInformation(
            FilePathAndroidBitmap(message.data['imageUrl'] ?? ''),
          ),
        ),
      ),
    );
  }
}

Future<void> scheduleNotification({
  required int id,
  required String title,
  required String body,
  required DateTime scheduledTime,
}) async {
  final androidDetails = AndroidNotificationDetails(
    'medication_channel',
    'Medication Reminders',
    channelDescription: 'This channel is used for medication reminders.',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  final notificationDetails = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.zonedSchedule(
    id,
    title,
    body,
    tz.TZDateTime.from(scheduledTime, tz.local),
    notificationDetails,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // Correct enum value
    matchDateTimeComponents: DateTimeComponents.time,
  );
}
Future<void> rescheduleAllNotifications() async {
  // Fetch all medications from Firestore and reschedule notifications
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final medsSnapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('medicines')
      .get();

  await flutterLocalNotificationsPlugin.cancelAll(); // Clear existing notifications

  int notificationId = 0; // Unique ID for each notification
  final now = DateTime.now();

  for (var doc in medsSnapshot.docs) {
    final data = doc.data();
    final String medicationName = data['name'] ?? 'دواء غير مسمى';
    final List<dynamic> timesRaw = data['times'] ?? [];
    final String frequencyType = data['frequencyType'] ?? 'يومي';

    if (frequencyType == 'يومي') {
      for (var timeStr in timesRaw) {
        final time = add_dose.TimeUtils.parseTime(timeStr.toString()); // Use alias to resolve conflict
        if (time != null) {
          final scheduledTime = DateTime(
            now.year,
            now.month,
            now.day,
            time.hour,
            time.minute,
          );
          if (scheduledTime.isAfter(now)) {
            await scheduleNotification(
              id: notificationId++,
              title: 'تذكير الدواء',
              body: 'حان وقت تناول $medicationName',
              scheduledTime: scheduledTime,
            );
          }
        }
      }
    }
    // Handle weekly frequency if needed
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key}); // Define the MyApp constructor

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mudhkir App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AuthWrapper(), // Ensure AuthWrapper is defined
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
      },
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp();

  // Initialize timezone data
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Riyadh')); // Set to your local timezone

  // Request notification permissions for Android 13+
  if (Platform.isAndroid && (await FirebaseMessaging.instance.isSupported())) {
    if (await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        ) ==
        AuthorizationStatus.authorized) {
      print("Notification permissions granted.");
    } else {
      print("Notification permissions denied.");
    }
  }

  // Activate Firebase App Check (Keep this if you use it)
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug, // Use PlayIntegrity in production
    appleProvider: AppleProvider.debug,   // Use AppAttest in production
  );

  // Initialize local notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      // Handle notification tap
      if (response.payload != null) {
        print("Notification payload: ${response.payload}");
      }
    },
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Create a notification channel for Android
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'medication_channel', // ID
    'Medication Reminders', // Name
    description: 'This channel is used for medication reminders.', // Description
    importance: Importance.high,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // --- FIX: Initialize locale data for intl package ---
  // You need to initialize every locale you use with DateFormat
  await initializeDateFormatting('ar_SA', null); // <-- INITIALIZE ARABIC LOCALE DATA
  // await initializeDateFormatting('en_US', null); // <-- Add others if needed (e.g., English)
  // ----------------------------------------------------

  // Request exact alarm permission
  await requestExactAlarmPermission();

  await rescheduleAllNotifications(); // Reschedule notifications on app start

  // Get FCM token
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  String? token = await messaging.getToken();
  print("FCM Token: $token");

  runApp(const MyApp());
}

//TODO : ORGANIZE  THE FILES AND FOLDERS

// TODO : TRY 3GS FOR ANIMATIONS AND DESIGN

//TODO :
