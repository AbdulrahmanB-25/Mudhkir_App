import 'package:flutter/material.dart';
import 'package:mudhkir_app/Pages/Home.dart';
import 'package:mudhkir_app/Pages/Cabinet.dart';
import 'package:mudhkir_app/Widgets/NavBar.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medication App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainWrapper(),
    );
  }
}

class MainWrapper extends StatefulWidget {
  const MainWrapper({super.key});

  @override
  State<MainWrapper> createState() => _MainWrapperState();
}

class _MainWrapperState extends State<MainWrapper> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const Home(),
    const Cabinet(),
    const Placeholder(), // Settings screen
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavBar(
        currentIndex: _currentIndex,
        onTabChange: (index) => setState(() => _currentIndex = index),
      ),
    );
  }
}