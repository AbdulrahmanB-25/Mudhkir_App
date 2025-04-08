import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Keep for username cache
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // For robust date/time parsing/formatting if needed

// --- CustomBottomNavigationBar remains the same ---
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
    // Standard implementation from your code...
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'الملف الشخصي'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'الإعدادات'),
        ],
        currentIndex: selectedIndex,
        selectedItemColor: Colors.blue.shade800, // Match theme
        unselectedItemColor: Colors.grey.shade600,
        onTap: onItemTapped,
        backgroundColor: Colors.white.withValues(alpha: 0.9), // Slight opacity
        elevation: 5, // Add some elevation
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}


class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  _MainPageState createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  String _userName = '';
  String _closestMedName = '';
  String _closestMedTimeStr = ''; // Store the formatted time string
  String _closestMedDocId = '';
  bool _isLoadingMed = true; // Loading indicator state

  @override
  void initState() {
    super.initState();
    _loadUserData(); // Combined loading
  }

  Future<void> _loadUserData() async {
    await _loadUserName();
    await _loadClosestMed(); // Fetch meds after getting username (or concurrently)
  }

  // Load username from Firestore, update cache if needed
  Future<void> _loadUserName() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // Should not happen if user logged in

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        String fetchedName = data['username'] as String? ?? 'مستخدم'; // Provide default

        SharedPreferences prefs = await SharedPreferences.getInstance();
        String? cachedName = prefs.getString('userName');

        if (cachedName == null || cachedName != fetchedName) {
          await prefs.setString('userName', fetchedName);
        }

        if (mounted) {
          setState(() {
            _userName = fetchedName;
          });
        }
      } else {
        // Handle case where user doc doesn't exist?
        if (mounted) setState(() => _userName = 'مستخدم');
      }

    } catch (e) {
      print("Error loading username: $e");
      if (mounted) setState(() => _userName = 'مستخدم'); // Default on error
    }
  }

  // --- Time Parsing and Formatting ---

  // Attempt to parse time string, potentially handling different formats.
  // Returns null if parsing fails.
  TimeOfDay? _parseTime(String timeStr) {
    try {
      // 1. Try parsing formats like "9:00 AM" or "9:00 ص" (using intl)
      // Adjust locale if needed, 'en_US' handles AM/PM well
      final DateFormat ampmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (e) {
      // Ignore parsing error and try next format
    }

    try {
      // 2. Try parsing Arabic AM/PM like "9:00 صباحاً"
      String normalizedTime = timeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('مساءً', 'PM')
          .trim();
      final DateFormat arabicAmpmFormat = DateFormat('h:mm a', 'en_US'); // Still use en_US for AM/PM logic
      DateTime parsedDt = arabicAmpmFormat.parseStrict(normalizedTime);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (e) {
      // Ignore parsing error and try next format
    }

    try {
      // 3. Try parsing 24-hour format like "14:30"
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), '')); // Clean minutes just in case
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (e) {
      // Ignore parsing error
    }

    print("Failed to parse time string: $timeStr");
    return null; // Return null if all parsing attempts fail
  }

  // Format TimeOfDay into a user-friendly Arabic string.
  String _formatTimeOfDay(BuildContext context, TimeOfDay time) {
    // Use Localizations for proper formatting if available and configured
    // final localizations = MaterialLocalizations.of(context);
    // return localizations.formatTimeOfDay(time, alwaysUse24HourFormat: false);

    // Manual Arabic formatting (fallback)
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod; // 12-hour format hour (1-12)
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    // Ensure correct Right-to-Left display if needed, though Text widget handles it.
    return '$hour:$minute $period';
  }


  // --- Closest Medication Logic ---

  // Fetch and determine the closest upcoming dose directly from Firestore.
  Future<void> _loadClosestMed() async {
    if (mounted) {
      setState(() {
        _isLoadingMed = true; // Start loading
      });
    }

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingMed = false);
      return;
    }

    List<Map<String, dynamic>> potentialDoses = [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final nowMinutes = now.hour * 60 + now.minute; // Minutes past midnight today

    try {
      final medsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .get(); // Consider adding '.where('endDate', isGreaterThanOrEqualTo: Timestamp.fromDate(today))' for optimization if feasible

      for (var doc in medsSnapshot.docs) {
        final data = doc.data();

        // --- Safely get and validate dates ---
        final startTimeStamp = data['startDate'] as Timestamp?;
        final endTimeStamp = data['endDate'] as Timestamp?;

        if (startTimeStamp == null) continue; // Skip if no start date

        final startDate = startTimeStamp.toDate();
        // Use end date if available, otherwise assume it doesn't end or handle as needed
        final endDate = endTimeStamp?.toDate();

        // Normalize dates to compare days only
        final startDay = DateTime(startDate.year, startDate.month, startDate.day);
        final endDay = endDate != null ? DateTime(endDate.year, endDate.month, endDate.day) : null;

        // --- Check if medication is active today ---
        if (today.isBefore(startDay)) continue; // Not started yet
        if (endDay != null && today.isAfter(endDay)) continue; // Already ended


        // --- Process times ---
        final times = List<String>.from(data['times'] ?? []);
        if (times.isEmpty) continue; // Skip if no times listed

        for (String timeStr in times) {
          final parsedTime = _parseTime(timeStr);
          if (parsedTime != null) {
            final doseTotalMinutes = parsedTime.hour * 60 + parsedTime.minute;

            // Calculate minutes until *next* occurrence of this time
            int minutesUntilNextDose = doseTotalMinutes - nowMinutes;
            if (minutesUntilNextDose < 0) {
              // If time has passed today, calculate for tomorrow
              minutesUntilNextDose += 24 * 60; // Add minutes in a day
            }

            // Store potential dose with its details and time difference
            potentialDoses.add({
              'name': data['name'] as String? ?? 'دواء غير مسمى',
              'doseTime': parsedTime, // Store TimeOfDay object
              'doseTimeStr': timeStr, // Original string for reference
              'minutesUntil': minutesUntilNextDose,
              'docId': doc.id,
            });
          } else {
            print("Skipping unparseable time: $timeStr for med: ${data['name']}");
          }
        }
      }

      // --- Find the dose with the minimum minutesUntil ---
      if (potentialDoses.isNotEmpty) {
        potentialDoses.sort((a, b) => (a['minutesUntil'] as int).compareTo(b['minutesUntil'] as int));
        final closest = potentialDoses.first;

        if (mounted) {
          setState(() {
            _closestMedName = closest['name'];
            // Format the TimeOfDay object for display
            _closestMedTimeStr = _formatTimeOfDay(context, closest['doseTime'] as TimeOfDay);
            _closestMedDocId = closest['docId'];
            _isLoadingMed = false;
          });
        }
      } else {
        // No upcoming doses found
        if (mounted) {
          setState(() {
            _closestMedName = '';
            _closestMedTimeStr = '';
            _closestMedDocId = '';
            _isLoadingMed = false;
          });
        }
      }

    } catch (e) {
      print("Error loading closest medication: $e");
      if (mounted) {
        setState(() {
          _closestMedName = ''; // Clear on error
          _closestMedTimeStr = 'خطأ في التحميل';
          _closestMedDocId = '';
          _isLoadingMed = false;
        });
      }
    }
  }


  void _onItemTapped(int index) {
    // Navigation logic remains the same, but ensure _loadClosestMed is called on return
    if (_selectedIndex == index) return; // Do nothing if tapping the current item

    String? routeName;
    if (index == 1) routeName = "/personal_data";
    if (index == 2) routeName = "/settings";

    if (routeName != null) {
      Navigator.pushNamed(context, routeName).then((_) {
        // After returning from profile or settings, update selection and reload meds
        if (mounted) {
          setState(() {
            _selectedIndex = index;
          });
          _loadClosestMed(); // Reload potential changes
        }
      });
    } else {
      // For index 0 (Home) or any other index not navigating away
      if (mounted) {
        setState(() {
          _selectedIndex = index;
        });
        // Optionally reload meds even when switching to Home if needed
        // _loadClosestMed();
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // Main Content
          SafeArea( // Ensure content is below status bar
            child: RefreshIndicator( // Add pull-to-refresh
              onRefresh: _loadClosestMed, // Reload meds on pull
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // Enable scroll for RefreshIndicator
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25), // Adjusted padding
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end, // Align text to the right
                    children: [
                      // Welcome Message
                      Text(
                        _userName.isEmpty ? "مرحباً بك" : "مرحباً بك، $_userName",
                        style: TextStyle(
                          fontSize: 26, // Slightly smaller
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      Text(
                        "نتمنى لك يوماً صحياً",
                        style: TextStyle(
                          fontSize: 18, // Slightly smaller
                          color: Colors.blue.shade600,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 25),

                      // Upcoming Dose Section Title
                      Text(
                        "الجرعة القادمة",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 10),

                      // Upcoming Dose Card
                      Container(
                        width: double.infinity, // Ensure container takes full width
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15), // Consistent radius
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.2),
                              spreadRadius: 1,
                              blurRadius: 5,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: _isLoadingMed
                            ? const Center(child: CircularProgressIndicator())
                            : _closestMedName.isEmpty
                            ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10.0),
                            child: Text(
                              "لا توجد جرعات قادمة",
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                        )
                            : DoseTile( // Use the DoseTile here
                          medicationName: _closestMedName,
                          nextDose: _closestMedTimeStr, // Use the formatted time string
                          docId: _closestMedDocId,
                          imageUrl: "", // No image for this simple tile
                          onDelete: () {}, // No delete action here
                          deletable: false, // Not deletable
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Action Cards Section
                      _buildActionCards(), // Extracted to a helper method

                      const SizedBox(height: 20), // Bottom padding
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: CustomBottomNavigationBar(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
      ),
    );
  }

  // Helper widget for Action Cards section
  Widget _buildActionCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ActionCard(
                icon: Icons.add_circle_outline, // Use outline icon
                label: "إضافة دواء", // Shorter label
                onTap: () {
                  Navigator.pushNamed(context, '/add_dose')
                      .then((result) {
                    // If AddDose returns true (or any value indicating success), reload meds
                    if (result != null) {
                      _loadClosestMed();
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 15), // Slightly less space
            Expanded(
              child: ActionCard(
                icon: Icons.calendar_month_outlined, // Use outline icon
                label: "جدول الأدوية",
                onTap: () {
                  Navigator.pushNamed(context, '/dose_schedule');
                  // No need to reload meds after viewing schedule unless it can change data
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        ActionCard(
          icon: Icons.people_outline, // Use outline icon
          label: "المرافقين",
          isFullWidth: true,
          onTap: () {
            Navigator.pushNamed(context, '/companions');
          },
        ),
      ],
    );
  }
}


// --- DoseTile remains the same (but imageUrl logic simplified) ---
// --- DoseTile updated to allow name wrapping ---
class DoseTile extends StatelessWidget {
  final String medicationName;
  final String nextDose; // This is the formatted time string
  final String docId;
  final String imageUrl; // Although not used in this specific context currently
  final VoidCallback onDelete;
  final bool deletable;

  const DoseTile({
    super.key,
    required this.medicationName,
    required this.nextDose,
    required this.docId,
    this.imageUrl = "", // Default to empty
    required this.onDelete, // Still required, even if not used by this instance
    this.deletable = true, // Still required
  });

  @override
  Widget build(BuildContext context) {
    // Using ListTile directly inside the Container in MainPage
    // This widget builds the content *for* that container/ListTile slot
    return ListTile(
      contentPadding: EdgeInsets.zero, // Use padding of the parent Container
      leading: Container( // Use Container for icon background
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.medication_liquid, // Using a consistent icon
          size: 30,
          color: Colors.blue.shade700,
        ),
      ),
      title: Text(
        medicationName, // Display the full name
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: Colors.blue.shade900,
        ),
        // REMOVED: overflow: TextOverflow.ellipsis,
        // By removing overflow, text will wrap automatically if it's too long
        // You can optionally set maxLines if you want to limit wrapping
        // maxLines: 2, // Example: Limit to 2 lines before using ellipsis
      ),
      subtitle: Text(
        "الوقت: $nextDose", // Add prefix for clarity
        style: TextStyle(
          fontSize: 15,
          color: Colors.black54,
        ),
      ),
      // No trailing widget as deletable is false for the main page upcoming dose
    );
  }
}

// --- ActionCard remains the same ---
class ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isFullWidth;
  const ActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isFullWidth = false,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      constraints: const BoxConstraints(minHeight: 90), // Min height
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15), // Match card radius
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.15), // Softer shadow
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Padding( // Add padding inside InkWell
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 15.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 35, color: Colors.blue.shade700), // Smaller icon
                const SizedBox(width: 12),
                // Flexible allows text to wrap if needed, though less likely here
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14, // Smaller text
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w600, // Medium bold
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}