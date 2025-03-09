import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "الإعدادات",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade800,
      ),
      body: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔔 Notifications Toggle
            SettingTile(
              icon: Icons.notifications,
              title: "الإشعارات",
              subtitle: "تشغيل أو إيقاف إشعارات الجرعات",
              trailing: Switch(
                value: true, // You can replace this with a state variable
                onChanged: (bool value) {
                  // Handle toggle logic
                },
                activeColor: Colors.blue.shade800,
              ),
            ),

            /// 🌐 Language Settings
            SettingTile(
              icon: Icons.language,
              title: "اللغة",
              subtitle: "تغيير لغة التطبيق",
              onTap: () {
                // Handle language change navigation
              },
            ),

            /// 🔒 Privacy & Security
            SettingTile(
              icon: Icons.lock,
              title: "الخصوصية والأمان",
              subtitle: "إدارة بياناتك وإعدادات الأمان",
              onTap: () {
                // Handle privacy settings navigation
              },
            ),

            /// 📞 Contact Support
            SettingTile(
              icon: Icons.help,
              title: "الدعم والمساعدة",
              subtitle: "تواصل معنا في حال واجهتك مشكلة",
              onTap: () {
                // Handle support contact navigation
              },
            ),

            /// 🚪 Logout Button
            SizedBox(height: 30),
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  // Handle logout logic
                },
                icon: Icon(Icons.exit_to_app, color: Colors.white),
                label: Text("تسجيل الخروج"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 🎯 Reusable Widget for Each Setting Option
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
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: trailing ?? Icon(Icons.arrow_forward_ios, size: 20),
        onTap: onTap,
      ),
    );
  }
}
