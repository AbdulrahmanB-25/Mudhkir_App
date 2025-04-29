import 'package:flutter/material.dart';

// Constants for theming
const Color kPrimaryColor = Color(0xFF1A5CFF); // Primary blue
const Color kSecondaryColor = Color(0xFF4ECDC4); // Teal accent
const Color kBackgroundColor = Color(0xFFF7F9FC); // Light background

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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.15),
            blurRadius: 10,
            spreadRadius: 0.5,
            offset: const Offset(0, -2),
          ),
        ],
        gradient: LinearGradient(
          colors: [
            Colors.white,
            kBackgroundColor.withOpacity(0.9),
          ],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BottomNavigationBar(
          items: [
            _buildNavItem(Icons.home_rounded, 'الرئيسية', 0),
            _buildNavItem(Icons.person_rounded, 'الملف الشخصي', 1),
            _buildNavItem(Icons.settings_rounded, 'الإعدادات', 2),
          ],
          currentIndex: selectedIndex,
          onTap: onItemTapped,
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 13,
          unselectedFontSize: 12,
          showUnselectedLabels: true,
          selectedItemColor: kPrimaryColor,
          unselectedItemColor: Colors.grey.shade600,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
        ),
      ),
    );
  }

  BottomNavigationBarItem _buildNavItem(IconData icon, String label, int index) {
    final bool isSelected = selectedIndex == index;

    return BottomNavigationBarItem(
      icon: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? kPrimaryColor.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? kPrimaryColor : Colors.grey.shade600,
              size: isSelected ? 26 : 24,
            ),
          ],
        ),
      ),
      label: label,
    );
  }
}
