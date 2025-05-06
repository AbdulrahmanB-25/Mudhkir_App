import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../Shared/Widgets/bottom_navigation.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedIndex = 2;
  String _appVersion = "جاري التحميل...";

  @override
  void initState() {
    super.initState();
    _fetchAppVersion();
  }

  // Fetches the latest app version from GitHub API
  Future<void> _fetchAppVersion() async {
    try {
      final response = await http.get(Uri.parse(
          'https://api.github.com/repos/<owner>/<repo>/releases/latest'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _appVersion = data['tag_name'] ?? "غير متوفر";
        });
      } else {
        setState(() {
          _appVersion = "خطأ في جلب الإصدار";
        });
      }
    } catch (e) {
      setState(() {
        _appVersion = "خطأ في الاتصال";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          "الإعدادات",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: kPrimaryColor,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        actions: [],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kPrimaryColor.withOpacity(0.1),
              kBackgroundColor,
              Colors.white,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.3, 1],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader("إعدادات التطبيق"),

                SettingTile(
                  icon: Icons.language,
                  title: "اللغة",
                  subtitle: "تغيير لغة التطبيق",
                  onTap: () {
                    // Handle language change navigation.
                  },
                ),
                const SizedBox(height: 12),

                SettingTile(
                  icon: Icons.lock_outline_rounded,
                  title: "الخصوصية والأمان",
                  subtitle: "إدارة بياناتك وإعدادات الأمان",
                  onTap: () {
                    // Handle privacy settings navigation.
                  },
                ),
                const SizedBox(height: 12),

                SettingTile(
                  icon: Icons.help_outline_rounded,
                  title: "الدعم والمساعدة",
                  subtitle: "تواصل معنا في حال واجهتك مشكلة",
                  onTap: () {
                    // Handle support contact navigation.
                  },
                ),
                const SizedBox(height: 20),

                _buildSectionHeader("حول التطبيق"),

                SettingTile(
                  icon: Icons.info_outline_rounded,
                  title: "معلومات التطبيق",
                  subtitle: "الإصدار $_appVersion",
                  onTap: () {},
                ),

                const SizedBox(height: 12),

                SettingTile(
                  icon: Icons.star_border_rounded,
                  title: "تقييم التطبيق",
                  subtitle: "ساعدنا بتحسين التطبيق من خلال تقييمك",
                  trailing: const Icon(Icons.open_in_new, size: 20, color: kSecondaryColor),
                  onTap: () {},
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: (int index) {
          if (index == _selectedIndex) return;

          String? routeName;
          if (index == 0) routeName = "/mainpage";
          if (index == 1) routeName = "/personal_data";

          if (routeName != null) {
            Navigator.pushReplacementNamed(context, routeName);
          }
        },
      ),
    );
  }

  // Builds a section header with a colored indicator and divider
  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              height: 24,
              width: 4,
              decoration: BoxDecoration(
                color: kPrimaryColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const Divider(height: 24, thickness: 1),
      ],
    );
  }
}

// Reusable setting tile widget with icon, title, subtitle and optional trailing widget
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kBorderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kBorderRadius),
          splashColor: kPrimaryColor.withOpacity(0.1),
          highlightColor: kPrimaryColor.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: kPrimaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing ?? const Icon(Icons.chevron_right_rounded,
                  size: 22,
                  color: kPrimaryColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
