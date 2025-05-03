import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mudhkir_app/Features/Companions/Companion_Details_Page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mudhkir_app/Features/Settings/SettingsPage.dart';
import 'package:mudhkir_app/Features/Companions/Companions_Main_Page.dart';
import 'package:mudhkir_app/Features/Personal_data/Personal_data_Page.dart';
import 'package:mudhkir_app/Features/Medication/Schedule/dose_schedule_UI.dart';
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
final FlutterLocalNotificationsPlugin notificationsPlugin = FlutterLocalNotificationsPlugin();

const String PREF_NEXT_DOSE_DOC_ID = 'next_dose_doc_id';
const String PREF_NEXT_DOSE_TIME_ISO = 'next_dose_time_iso';
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
          return CompanionDetailPage(email: args['email'], name: args['name']);
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_tapped_payload', medId);
    await prefs.setString('last_tapped_time', now);
    if (medId.startsWith('companion_check_')) {
      await CompanionMedicationTracker.processCompanionDoseCheck(medId);
      return;
    } else if (medId.startsWith('companion_missed_')) {
      navigatorKey.currentState?.pushNamed('/companions');
      return;
    }
    navigatorKey.currentState?.pushNamed('/medication_detail', arguments: {'docId': medId, 'fromNotification': true});
  }
}

Future<void> _setupPeriodicCompanionChecks() async {
  if (Platform.isAndroid) {
    const int checkId = 11223344;
    await AndroidAlarmManager.periodic(
      const Duration(hours: 1),
      checkId,
      _runCompanionChecks,
      exact: false,
      wakeup: false,
      rescheduleOnReboot: true,
    );
  }
}

@pragma('vm:entry-point')
void _runCompanionChecks() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await CompanionMedicationTracker.runPendingChecks();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
  await Firebase.initializeApp();
  runApp(const MyApp());
}
