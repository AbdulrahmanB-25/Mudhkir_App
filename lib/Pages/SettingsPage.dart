import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mudhkir_app/main.dart'; // Import notification utilities

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
        color: Colors.white.withOpacity(0.8),
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
  int _selectedIndex = 2; // Index for the bottom navigation bar
  bool _vibrationEnabled = true;
  bool _soundEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAlarmSettings();
  }

  Future<void> _saveAlarmSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vibrationEnabled', _vibrationEnabled);
    await prefs.setBool('soundEnabled', _soundEnabled);

    print("Settings saved. Vibration: $_vibrationEnabled, Sound: $_soundEnabled");
    
    // Reschedule notifications with new settings
    print("Rescheduling notifications with updated settings...");
    await rescheduleAllNotifications();
    print("Notifications rescheduled successfully");
  }

  Future<void> _loadAlarmSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vibrationEnabled = prefs.getBool('vibrationEnabled') ?? true;
      _soundEnabled = prefs.getBool('soundEnabled') ?? true;
    });
    print("Settings loaded. Vibration: $_vibrationEnabled, Sound: $_soundEnabled");
  }

  Future<void> _sendTestNotification() async {
    final now = DateTime.now();
    final testTime = now.add(const Duration(seconds: 5)); // Schedule 5 seconds from now

    await scheduleNotification(
      id: 9999, // Unique ID for the test notification
      title: "تذكير تجريبي",
      body: "هذا إشعار تجريبي لتذكير الدواء.",
      scheduledTime: testTime,
      docId: '', // No specific docId for the test
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("تم جدولة الإشعار التجريبي، ستظهر خلال 5 ثوان"),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

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
              const SizedBox(height: 20),
              /// 🔔 Notification Settings Section
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Text(
                  "إعدادات التنبيهات",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              /// 🔊 Sound Settings
              SettingTile(
                icon: Icons.volume_up,
                title: "تشغيل الصوت",
                subtitle: "تشغيل أو إيقاف صوت التنبيه",
                trailing: Switch(
                  value: _soundEnabled,
                  onChanged: (bool value) {
                    setState(() {
                      _soundEnabled = value;
                    });
                    _saveAlarmSettings();
                  },
                  activeColor: Colors.blue.shade800,
                ),
              ),
              const SizedBox(height: 10),
              /// 📳 Vibration Settings
              SettingTile(
                icon: Icons.vibration,
                title: "تشغيل الاهتزاز",
                subtitle: "تشغيل أو إيقاف الاهتزاز مع التنبيه",
                trailing: Switch(
                  value: _vibrationEnabled,
                  onChanged: (bool value) {
                    setState(() {
                      _vibrationEnabled = value;
                    });
                    _saveAlarmSettings();
                  },
                  activeColor: Colors.blue.shade800,
                ),
              ),
              const SizedBox(height: 20),
              /// 🧪 Test Notification Button
              ElevatedButton.icon(
                onPressed: _sendTestNotification,
                icon: const Icon(Icons.notifications_active),
                label: const Text("اختبار الإشعارات"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
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
