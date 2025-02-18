import 'package:flutter/material.dart';

//TODO : NAVBAR REWORK

class NavBar extends StatelessWidget {
  final Function(int) onTabChange;
  final int currentIndex;

  const NavBar({
    super.key,
    required this.onTabChange,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return  BottomNavigationBar(
    items: <BottomNavigationBarItem>[
    BottomNavigationBarItem(
    icon: Icon(Icons.home),
    label: 'الرئيسية',
    ),
    BottomNavigationBarItem(
    icon: Icon(Icons.person),
    label: 'الملف الشخصي',
    ),
    BottomNavigationBarItem(
    icon: Icon(Icons.settings),
    label: 'الإعدادات',
    ),
    ],
    currentIndex: currentIndex,
    selectedItemColor: Colors.blue.shade800,
    unselectedItemColor: Colors.grey,
    onTap: onTabChange,
    );
  }
}