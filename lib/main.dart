import 'package:flutter/material.dart';
import 'package:mudhkir_app/Pages/SettingsPage.dart';
import 'package:mudhkir_app/Pages/companions.dart';
import 'package:mudhkir_app/Pages/personal_data.dart';
import 'package:mudhkir_app/pages/add_dose.dart';
import 'package:mudhkir_app/pages/login.dart';
import 'package:mudhkir_app/pages/mainpage.dart';
import 'package:mudhkir_app/pages/signup.dart';
import 'package:mudhkir_app/pages/welcome.dart';
import 'package:mudhkir_app/pages/dose_schedule.dart';
import 'package:mudhkir_app/pages/ForgetPassword.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mudhkir_app/Widgets/AuthWrapper.dart'; // Assuming AuthWrapper is in Widgets folder
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';


// Import the intl package localization data initialization function
import 'package:intl/date_symbol_data_local.dart'; // <-- ADD THIS IMPORT

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Ensures widgets are ready
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(); // Initializes Firebase

  // Activate Firebase App Check (Keep this if you use it)
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug, // Use PlayIntegrity in production
    appleProvider: AppleProvider.debug,   // Use AppAttest in production
  );

  // --- FIX: Initialize locale data for intl package ---
  // You need to initialize every locale you use with DateFormat
  await initializeDateFormatting('ar_SA', null); // <-- INITIALIZE ARABIC LOCALE DATA
  // await initializeDateFormatting('en_US', null); // <-- Add others if needed (e.g., English)
  // ----------------------------------------------------

  runApp(const MyApp()); // Runs your app
}

//TODO : ORGANIZE  THE FILES AND FOLDERS

// TODO : TRY 3GS FOR ANIMATIONS AND DESIGN

//TODO : MAKE THE PAGES TRANSATION SLOWER

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Hides the debug banner
      initialRoute: "/", // Sets the initial route (AuthWrapper handles auth check)
      routes: {
        // Defines the navigation routes for your app
        "/" : (context) => const AuthWrapper(), // Entry point, checks auth state
        "/login" : (context) => const Login(), // Login page
        "/signup" : (context) => const Signup(), // Signup page
        "/mainpage" : (context) => const MainPage(), // Main page after login
        "/dose_schedule" : (context) => const DoseSchedule(), // The page causing the error
        "/add_dose" : (context) => const AddDose(), // Add dose page
        "/companions" : (context) =>  Companions(), // Companions page
        "/personal_data": (context) => const PersonalDataPage(), // Personal data page
        "/settings": (context) => const SettingsPage(), // Settings page
        "/welcome": (context) => const Welcome(), // Welcome page
        "/forget_password": (context) => const ForgetPassword(), // Forget password page
      },
      // Optional: You can set theme, locales etc. here if needed
      // theme: ThemeData(...),
      // locale: Locale('ar', 'SA'), // Example: Set default locale
      // supportedLocales: [Locale('ar', 'SA'), Locale('en', 'US')], // Example
    );
  }
}