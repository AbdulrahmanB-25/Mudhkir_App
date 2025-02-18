import 'package:flutter/material.dart';
import 'package:myapp/pages/add_dose.dart';
import 'package:myapp/pages/login.dart';
import 'package:myapp/pages/mainpage.dart';
import 'package:myapp/pages/signup.dart';
import 'package:myapp/pages/welcome.dart';
import 'package:myapp/pages/dose_schedule.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: "/",

    routes: {
      "/" : (context) => const Welcome(),
      "/login" : (context) => const Login(),
      "/signup" : (context) => const Signup(),
      "/mainpage" : (context) => const MainPage(),
      "/dose_schedule" : (context) => const dose_schedule(),
      "/add_dose" : (context) => const add_dose(),
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
