import 'package:flutter/material.dart';

/// You can import your custom bottom navigation widget here if it is in a separate file.

/// For demonstration, here is a simple CustomBottomNavigationBar implementation.
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
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: Colors.white.withValues(alpha:0.8),
        child: BottomNavigationBar(
          items: const [
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
          currentIndex: selectedIndex,
          selectedItemColor: Colors.blue.shade800,
          unselectedItemColor: Colors.grey,
          onTap: onItemTapped,
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // For the bottom navigation bar, we track the selected index.
  int _selectedIndex = 2; // Set index 2 to show that we're on the "Settings" page.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "الإعدادات",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade800,
      ),
      body: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// 🔔 Notifications Toggle
              SettingTile(
                icon: Icons.notifications,
                title: "الإشعارات",
                subtitle: "تشغيل أو إيقاف إشعارات الجرعات",
                trailing: Switch(
                  value: true, // Replace with your state variable if needed.
                  onChanged: (bool value) {
                    // Handle toggle logic.
                  },
                  activeColor: Colors.blue.shade800,
                ),
              ),
              const SizedBox(height: 10),
              /// 🌐 Language Settings
              SettingTile(
                icon: Icons.language,
                title: "اللغة",
                subtitle: "تغيير لغة التطبيق",
                onTap: () {
                  // Handle language change navigation.
                },
              ),
              const SizedBox(height: 10),
              /// 🔒 Privacy & Security
              SettingTile(
                icon: Icons.lock,
                title: "الخصوصية والأمان",
                subtitle: "إدارة بياناتك وإعدادات الأمان",
                onTap: () {
                  // Handle privacy settings navigation.
                },
              ),
              const SizedBox(height: 10),
              /// 📞 Contact Support
              SettingTile(
                icon: Icons.help,
                title: "الدعم والمساعدة",
                subtitle: "تواصل معنا في حال واجهتك مشكلة",
                onTap: () {
                  // Handle support contact navigation.
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: (int index) {
          // Handle bottom navigation taps.
          setState(() {
            _selectedIndex = index;
          });
          // For example, navigate to the corresponding screen.
          if (index == 0) {
            Navigator.pushReplacementNamed(context, '/mainpage');
          } else if (index == 1) {
            Navigator.pushReplacementNamed(context, '/personal_data');
          }
          // Do nothing for index 2 because we are on the Settings page.
        },
      ),
    );
  }
}

/// Reusable widget for each setting option.
class SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue.shade800, size: 30),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 20),
        onTap: onTap,
      ),
    );
  }
}
