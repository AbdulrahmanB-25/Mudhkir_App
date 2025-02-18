import 'package:flutter/material.dart';

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
    return BottomNavigationBar(
      currentIndex: currentIndex,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.medication),
          label: 'Cabinet',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
      selectedItemColor: Colors.blue,
      unselectedItemColor: Colors.grey,
      onTap: onTabChange,
    );
  }
}