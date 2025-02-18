import 'package:flutter/material.dart';
import 'package:mudhkir_app/Pages/login.dart';
import 'package:mudhkir_app/Pages/mainpage.dart';
import 'package:mudhkir_app/Pages/signup.dart';
import 'package:mudhkir_app/Pages/welcome.dart';
import 'package:mudhkir_app/Pages/Cabinet.dart';
import 'package:mudhkir_app/Pages/signup.dart';
import 'package:mudhkir_app/Pages/welcome.dart';


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
      "/Cabinet" : (context) => const Cabinet(),

    },

    );
  }

}

