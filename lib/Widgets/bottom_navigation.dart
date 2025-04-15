import 'package:flutter/material.dart';

class CustomBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const CustomBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade100.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BottomNavigationBar(
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'الرئيسية'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'الملف الشخصي'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'الإعدادات'),
          ],
          currentIndex: selectedIndex,
          selectedItemColor: Colors.blue.shade800,
          unselectedItemColor: Colors.grey.shade500,
          onTap: onItemTapped,
          backgroundColor: Colors.white.withOpacity(0.95),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          showUnselectedLabels: true,
        ),
      ),
    );
  }
}
