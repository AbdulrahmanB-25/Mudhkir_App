import 'package:flutter/material.dart';
import 'package:mudhkir_app/Pages/companions.dart';
import 'package:mudhkir_app/Pages/personal_data.dart';
import 'package:mudhkir_app/pages/add_dose.dart';
import 'package:mudhkir_app/pages/login.dart';
import 'package:mudhkir_app/pages/mainpage.dart';
import 'package:mudhkir_app/pages/signup.dart';
import 'package:mudhkir_app/pages/welcome.dart';
import 'package:mudhkir_app/pages/dose_schedule.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: "/",
    routes: {
      "/" : (context) => const Welcome(),
      "/login" : (context) => const Login(),
      "/signup" : (context) => const Signup(),
      "/mainpage" : (context) => const MainPage(),
      "/dose_schedule" : (context) => const dose_schedule(),
      "/add_dose" : (context) => const add_dose(),
      "/companions" : (context) =>  Companions(),
      "/personal_data": (context) => const PersonalDataPage(),

    },

    );
  }
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    );
  }
}
