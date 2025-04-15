import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart'; // For time parsing and date formatting

// --- Import your Edit screen ---
// Ensure this path is correct for your project structure
import 'package:mudhkir_app/pages/EditMedicationScreen.dart';

import '../main.dart';

// --- Time Utilities (Ideally move to a separate utils file) ---
// Using the same TimeUtils logic provided
class TimeUtils {
  static TimeOfDay? parseTime(String timeStr) {
    try {
      final DateFormat ampmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      String normalizedTime = timeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('مساءً', 'PM')
          .trim();
      final DateFormat arabicAmpmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = arabicAmpmFormat.parseStrict(normalizedTime);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (_) {}
    print("Failed to parse time string: $timeStr");
    return null;
  }

  static String formatTimeOfDay(BuildContext context, TimeOfDay time) {
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }
}
// --- End Time Utilities ---

// --- EnlargeableImage Widget (Styled to fit theme) ---
class EnlargeableImage extends StatefulWidget {
  final String imageUrl;
  final double width;
  final double height;

  const EnlargeableImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
  });

  @override
  _EnlargeableImageState createState() => _EnlargeableImageState();
}

class _EnlargeableImageState extends State<EnlargeableImage> {
  late Future<File?> _imageFileFuture;

  @override
  void initState() {
    super.initState();
    _imageFileFuture = _downloadAndSaveImage(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant EnlargeableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _imageFileFuture = _downloadAndSaveImage(widget.imageUrl);
    }
  }

  Future<File?> _downloadAndSaveImage(String url) async {
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.isAbsolute) {
      print("Invalid or empty URL for download: $url");
      return null;
    }
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final Directory directory = await getTemporaryDirectory();
        final String filePath = '${directory.path}/${url.hashCode}.png';
        File file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      } else {
        print("Failed to download image ($url). Status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error downloading image ($url): $e");
    }
    return null;
  }

  void _openEnlargedImage(BuildContext context, File imageFile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) {
          return Scaffold(
            backgroundColor: Colors.black87, // Keep dark for focus
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.blue),
            ),
            body: Center(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(imageFile),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.imageUrl);
    // Use placeholder if URL is invalid or empty
    if (widget.imageUrl.isEmpty || uri == null || !uri.isAbsolute) {
      return _buildPlaceholder(showErrorText: false);
    }

    return FutureBuilder<File?>(
      future: _imageFileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Loading state with themed placeholder
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.blue.shade50, // Match theme background elements
              borderRadius: BorderRadius.circular(12), // Consistent rounding
            ),
            child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.blue.shade600, // Match theme progress indicator
                )),
          );
        } else if (snapshot.hasData && snapshot.data != null) {
          // Image loaded successfully
          return GestureDetector(
            onTap: () => _openEnlargedImage(context, snapshot.data!),
            child: Container(
              decoration: BoxDecoration( // Add subtle shadow like ActionCards
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade100.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12), // Consistent rounding
                child: Image.file(
                  snapshot.data!,
                  width: widget.width,
                  height: widget.height,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    print("Error displaying file image: $error");
                    return _buildPlaceholder(showErrorText: true); // Show error placeholder
                  },
                ),
              ),
            ),
          );
        } else {
          // Error loading image or no image URL
          return _buildPlaceholder(showErrorText: true); // Show error placeholder
        }
      },
    );
  }

  // Placeholder widget, styled consistently
  Widget _buildPlaceholder({required bool showErrorText}) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.blue.shade50, // Match theme background elements
        borderRadius: BorderRadius.circular(12), // Consistent rounding
        border: Border.all(color: Colors.blue.shade100, width: 1),
      ),
      alignment: Alignment.center,
      child: Icon(
        showErrorText ? Icons.broken_image_outlined : Icons.image_not_supported_outlined,
        color: Colors.blue.shade300, // Softer color for placeholder icon
        size: widget.width * 0.5, // Adjust size as needed
      ),
    );
  }
}
// --- End EnlargeableImage Widget ---

// --- DoseSchedule Widget (Themed) ---
class DoseSchedule extends StatefulWidget {
  const DoseSchedule({super.key});

  @override
  _DoseScheduleState createState() => _DoseScheduleState();
}

class _DoseScheduleState extends State<DoseSchedule> {
  User? _user; // Make user nullable initially
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<Map<String, dynamic>>> _doses = {};
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser; // Get current user
    if (_user == null) {
      print("Error: User not logged in for DoseSchedule.");
      // Schedule Snackbar display after the first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("الرجاء تسجيل الدخول أولاً لعرض الجدول"),
              backgroundColor: Colors.red.shade700, // Error color
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(10),
            ),
          );
          // Optionally navigate back if appropriate
          // if (Navigator.canPop(context)) {
          //   Navigator.of(context).pop();
          // }
        }
      });
      setState(() => _isLoading = false); // Stop loading if no user
    } else {
      _fetchDoses(); // Fetch doses only if user is logged in
    }
  }

  // Fetch doses remains largely the same, added null check for user
  Future<void> _fetchDoses() async {
    if (!mounted || _user == null) return; // Check if mounted and user exists
    setState(() {
      _isLoading = true;
    });

    final Map<DateTime, List<Map<String, dynamic>>> newDoses = {};
    final String userId = _user!.uid; // Safe to use ! here due to check above

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .get();

      // --- (Parsing logic remains the same as provided) ---
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String medicationName = data['name'] as String? ?? 'دواء غير مسمى';
        final String dosage = data['dosage'] as String? ?? 'غير محددة';
        final Timestamp? startTimestamp = data['startDate'] as Timestamp?;
        final Timestamp? endTimestamp = data['endDate'] as Timestamp?;

        if (startTimestamp == null) {
          print('Document ${doc.id} missing start date. Skipping.');
          continue;
        }

        final String frequencyRaw = data['frequency'] as String? ?? '1 يومي';
        final List<String> frequencyParts = frequencyRaw.split(" ");
        final String frequencyType = frequencyParts.length > 1 ? frequencyParts[1] : 'يومي';

        // Use frequencyType from the 'frequency' field for logic
        final String resolvedFrequencyType = frequencyType;

        final List<dynamic> timesRaw = data['times'] ?? [];
        final String imageUrl = data['imageUrl'] as String? ?? '';
        final String imgbbDeleteHash = data['imgbbDeleteHash'] as String? ?? '';

        final DateTime startDate = startTimestamp.toDate();
        final DateTime? endDate = endTimestamp?.toDate();

        DateTime currentDate = startDate;
        while (endDate == null || !currentDate.isAfter(endDate)) {
          final DateTime normalizedDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
          bool shouldAddDoseToday = false;
          List<TimeOfDay> timesParsed = [];

          if (resolvedFrequencyType == 'يومي') {
            timesParsed = timesRaw
                .map((t) => t != null ? TimeUtils.parseTime(t.toString()) : null)
                .whereType<TimeOfDay>()
                .toList();
            shouldAddDoseToday = timesParsed.isNotEmpty;
          } else if (resolvedFrequencyType == 'اسبوعي') {
            timesParsed = timesRaw
                .whereType<Map>()
                .where((map) => map['day'] == currentDate.weekday)
                .map((map) => TimeUtils.parseTime(map['time'].toString()))
                .whereType<TimeOfDay>()
                .toList();
            shouldAddDoseToday = timesParsed.isNotEmpty;
          }

          if (shouldAddDoseToday) {
            newDoses.putIfAbsent(normalizedDate, () => []);
            for (var time in timesParsed) {
              newDoses[normalizedDate]!.add({
                'medicationName': medicationName,
                'dosage': dosage,
                'timeOfDay': time,
                'timeString': TimeUtils.formatTimeOfDay(context, time),
                'docId': doc.id,
                'imageUrl': imageUrl,
                'imgbbDeleteHash': imgbbDeleteHash,
              });
            }
          }

          currentDate = currentDate.add(const Duration(days: 1));
          if (endDate != null && currentDate.isAfter(endDate)) break;
          // Add a safety break for potentially endless loops without an end date
          if (endDate == null && currentDate.difference(startDate).inDays > (365 * 10)) {
            print("Warning: Medication ${doc.id} seems to have no end date or a very long duration; stopping iteration after 10 years.");
            break;
          }
        }
      }

      newDoses.forEach((date, meds) {
        meds.sort((a, b) {
          final TimeOfDay timeA = a['timeOfDay'];
          final TimeOfDay timeB = b['timeOfDay'];
          final int cmp = timeA.hour != timeB.hour
              ? timeA.hour.compareTo(timeB.hour)
              : timeA.minute.compareTo(timeB.minute);
          if (cmp != 0) return cmp;
          // Secondary sort by name if times are identical
          return (a['medicationName'] as String).compareTo(b['medicationName'] as String);
        });
      });
      // --- (End of parsing logic) ---

      if (mounted) {
        setState(() {
          _doses = newDoses;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print('Error fetching doses: $e');
      print(stackTrace);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _doses = {}; // Clear doses on error
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("حدث خطأ أثناء تحميل جدول الأدوية."),
            backgroundColor: Colors.red.shade700, // Error color
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    }
  }

  // Get events for a specific day (used by TableCalendar).
  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final DateTime normalizedDay = DateTime(day.year, day.month, day.day);
    return _doses[normalizedDay] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    // Display message if loading is done and user is still null
    if (!_isLoading && _user == null) {
      return Scaffold(
        // Apply background gradient even on the error screen
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue.shade50,
                Colors.white.withOpacity(0.8),
                Colors.blue.shade100,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.login_rounded, size: 60, color: Colors.blue.shade300),
                const SizedBox(height: 15),
                Text(
                  "الرجاء تسجيل الدخول لعرض الجدول",
                  style: TextStyle(fontSize: 18, color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 16),
                  label: const Text("العودة"),
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                )
              ],
            ),
          ),
        ),
      );
    }

    // Main Scaffold with Themed Elements
    return Scaffold(
      extendBodyBehindAppBar: true, // Allow body content to go behind AppBar
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Make AppBar transparent
        elevation: 0, // Remove shadow
        title: const Text(
          "جدول الأدوية",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
            shadows: [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 3.0,
                color: Color.fromARGB(150, 0, 0, 0),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(
          color: Colors.blue,
          shadows: [Shadow(offset: Offset(0, 1), blurRadius: 3.0, color: Color.fromARGB(150, 0, 0, 0))],
        ), // Add shadow to back arrow
      ),
      // Apply background gradient
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade50,
              Colors.white.withOpacity(0.8),
              Colors.blue.shade100,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Scrollable Content Area
              Expanded(
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: Colors.blue.shade700))
                    : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(), // Nicer scroll physics
                  child: Padding(
                    padding: const EdgeInsets.all(16.0), // Consistent padding
                    child: Column(
                      children: [
                        // Calendar Card - Themed
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16), // Consistent rounding
                          ),
                          elevation: 3, // Subtle elevation
                          color: Colors.white.withOpacity(0.95), // Slightly transparent white
                          shadowColor: Colors.blue.shade100.withOpacity(0.3),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TableCalendar<Map<String, dynamic>>(
                              locale: 'ar_SA',
                              focusedDay: _focusedDay,
                              firstDay: DateTime.utc(DateTime.now().year - 2, 1, 1),
                              lastDay: DateTime.utc(DateTime.now().year + 5, 12, 31),
                              calendarFormat: _calendarFormat,
                              // Keep format options simple
                              availableCalendarFormats: const {
                                CalendarFormat.month: 'شهر',
                                CalendarFormat.week: 'اسبوع',
                              },
                              eventLoader: _getEventsForDay,
                              // Themed Header Style
                              headerStyle: HeaderStyle(
                                formatButtonVisible: true,
                                titleCentered: true,
                                titleTextStyle: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800, // Theme color
                                ),
                                formatButtonDecoration: BoxDecoration(
                                    color: Colors.blue.shade100.withOpacity(0.5), // Lighter blue
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blue.shade200)
                                ),
                                formatButtonTextStyle: TextStyle(
                                  color: Colors.blue.shade700, // Theme color
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                leftChevronIcon: Icon(Icons.chevron_left, color: Colors.blue.shade600),
                                rightChevronIcon: Icon(Icons.chevron_right, color: Colors.blue.shade600),
                              ),
                              // Remove default markers/event dots
                              calendarBuilders: CalendarBuilders(
                                // Empty marker builder to remove event dots
                                markerBuilder: (context, date, events) {
                                  // Return empty container instead of dots
                                  return const SizedBox.shrink();
                                },
                                // Customize day cells to show a subtle indicator for days with events
                                // by adding a bottom border or different background
                                defaultBuilder: (context, day, focusedDay) {
                                  final events = _getEventsForDay(day);
                                  return Container(
                                    margin: const EdgeInsets.all(4),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      // Apply a subtle bottom border for days with events
                                      border: events.isNotEmpty
                                          ? Border(
                                              bottom: BorderSide(
                                                color: Colors.orange.shade300,
                                                width: 2,
                                              ),
                                            )
                                          : null,
                                      // Optional: Add a very subtle background for days with events
                                      color: events.isNotEmpty
                                          ? Colors.orange.shade50.withOpacity(0.3)
                                          : null,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        color: events.isNotEmpty
                                            ? Colors.blue.shade900
                                            : null,
                                        fontWeight: events.isNotEmpty
                                            ? FontWeight.bold
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              // Themed Calendar Style
                              calendarStyle: CalendarStyle(
                                outsideDaysVisible: false,
                                todayDecoration: BoxDecoration(
                                  color: Colors.blue.shade700.withOpacity(0.8), // Theme color
                                  shape: BoxShape.circle,
                                ),
                                selectedDecoration: BoxDecoration(
                                  color: Colors.lightBlueAccent.shade100, // Lighter accent for selection
                                  shape: BoxShape.circle,
                                ),
                                weekendTextStyle: TextStyle(
                                  color: Colors.red.shade600, // Keep weekend color distinct
                                ),
                                defaultTextStyle: const TextStyle(color: Colors.black87),
                                todayTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                selectedTextStyle: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                                // Remove markers (another way to hide event dots)
                                markersMaxCount: 0,
                                markersAnchor: 0,
                                markerMargin: EdgeInsets.zero,
                                markerDecoration: const BoxDecoration(),
                              ),
                              onFormatChanged: (format) {
                                if (_calendarFormat != format) {
                                  setState(() => _calendarFormat = format);
                                }
                              },
                              onPageChanged: (focusedDay) {
                                _focusedDay = focusedDay; // Update focused day on page change
                                // Optionally fetch doses again if your logic requires it for different months/years
                              },
                              onDaySelected: (selectedDay, focusedDay) {
                                if (!isSameDay(_selectedDay, selectedDay)) {
                                  setState(() {
                                    _selectedDay = selectedDay;
                                    _focusedDay = focusedDay; // Keep focused day in sync
                                  });
                                }
                              },
                              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),

                        // Dose List Section Title - Themed
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                          child: Text(
                            "جرعات يوم: ${DateFormat('EEEE, d MMMM yyyy', 'ar_SA').format(_selectedDay)}",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600, // Bold but not too heavy
                                color: Colors.blue.shade900), // Darker blue for title
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Dose List - Uses themed DoseTile
                        _buildDoseList(),

                        const SizedBox(height: 30), // Bottom Padding
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget to build the list of doses for the selected day.
  Widget _buildDoseList() {
    final events = _getEventsForDay(_selectedDay);
    if (events.isEmpty) {
      // Themed 'No Doses' message
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
        child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.medication_liquid_outlined,
                  size: 50,
                  color: Colors.grey.shade400, // Match MainPage empty state
                ),
                const SizedBox(height: 10),
                Text(
                  "لا توجد جرعات لهذا اليوم",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600, // Match MainPage empty state
                  ),
                ),
              ],
            )
        ),
      );
    } else {
      // Use ListView.separated for better spacing between tiles
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(), // Disable scrolling within the parent scroll view
        itemCount: events.length,
        itemBuilder: (context, index) {
          final dose = events[index];
          final String docId = dose['docId'] ?? 'missing_doc_id_$index';
          final String timeString = dose['timeString'] ?? '??:??';
          final String imageUrl = dose['imageUrl'] ?? '';
          final String imgbbDeleteHash = dose['imgbbDeleteHash'] ?? '';

          // Use the themed DoseTile
          return DoseTile(
            key: ValueKey(docId + timeString + imageUrl), // More robust key
            medicationName: dose['medicationName'] ?? 'غير مسمى',
            nextDose: timeString,
            docId: docId,
            imageUrl: imageUrl,
            imgbbDeleteHash: imgbbDeleteHash,
            onDataChanged: _fetchDoses, // Pass callback to refresh list after changes
          );
        },
        separatorBuilder: (context, index) => const SizedBox(height: 8), // Space between cards
      );
    }
  }
}

// --- Themed DoseTile Widget ---
class DoseTile extends StatefulWidget {
  final String medicationName;
  final String nextDose; // formatted time string
  final String docId;
  final String imageUrl;
  final String imgbbDeleteHash;
  final VoidCallback onDataChanged; // Callback to refresh DoseSchedule

  const DoseTile({
    super.key,
    required this.medicationName,
    required this.nextDose,
    required this.docId,
    required this.imageUrl,
    required this.imgbbDeleteHash,
    required this.onDataChanged,
  });

  @override
  _DoseTileState createState() => _DoseTileState();
}

class _DoseTileState extends State<DoseTile> {
  bool _isExpanded = false;
  String _doseStatus = 'pending'; // Initial status
  bool _isLoadingStatus = true; // Loading indicator for status check

  @override
  void initState() {
    super.initState();
    _checkDoseStatus();
  }

  @override
  void didUpdateWidget(covariant DoseTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check status if docId or time changes (though less likely here)
    if (oldWidget.docId != widget.docId || oldWidget.nextDose != widget.nextDose) {
      _checkDoseStatus();
    }
  }

  Future<void> _checkDoseStatus() async {
    if (!mounted) return;
    setState(() => _isLoadingStatus = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingStatus = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(widget.docId)
          .get();

      if (!doc.exists || !mounted) {
        if (mounted) setState(() => _isLoadingStatus = false);
        return;
      }

      final data = doc.data()!;
      final missedDoses = data['missedDoses'] as List<dynamic>? ?? [];
      final selectedDay = context.findAncestorStateOfType<_DoseScheduleState>()?._selectedDay ?? DateTime.now(); // Get selected day from parent state
      final normalizedSelectedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);

      final doseTime = TimeUtils.parseTime(widget.nextDose);
      if (doseTime == null) {
        if (mounted) setState(() => _isLoadingStatus = false);
        return;
      }

      String currentStatus = 'pending'; // Default to pending
      for (var dose in missedDoses) {
        if (dose is Map<String, dynamic> && dose.containsKey('scheduled') && dose.containsKey('status')) {
          final scheduledTimestamp = dose['scheduled'] as Timestamp?;
          if (scheduledTimestamp != null) {
            final scheduledDate = scheduledTimestamp.toDate();
            final normalizedScheduledDate = DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day);

            // Check if the dose time and date match the current tile's time and selected day
            if (scheduledDate.hour == doseTime.hour &&
                scheduledDate.minute == doseTime.minute &&
                isSameDay(normalizedScheduledDate, normalizedSelectedDay) ) {
              currentStatus = dose['status'] as String? ?? 'pending';
              break; // Found the status for this specific dose instance
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _doseStatus = currentStatus;
          _isLoadingStatus = false;
        });
      }
    } catch (e) {
      print('Error checking dose status for ${widget.docId}: $e');
      if (mounted) {
        setState(() {
          _isLoadingStatus = false; // Stop loading on error
          _doseStatus = 'pending'; // Reset to pending on error
        });
      }
    }
  }

  Future<void> _toggleDoseStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    final selectedDay = context.findAncestorStateOfType<_DoseScheduleState>()?._selectedDay ?? DateTime.now();
    final normalizedSelectedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final doseTime = TimeUtils.parseTime(widget.nextDose);

    if (doseTime == null) {
      print("Error: Could not parse dose time for toggling status.");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("خطأ في تحديث حالة الجرعة."), backgroundColor: Colors.red));
      return;
    }

    final targetDateTime = DateTime(
      normalizedSelectedDay.year,
      normalizedSelectedDay.month,
      normalizedSelectedDay.day,
      doseTime.hour,
      doseTime.minute,
    );
    final targetTimestamp = Timestamp.fromDate(targetDateTime);
    final newStatus = _doseStatus == 'taken' ? 'pending' : 'taken';

    setState(() => _isLoadingStatus = true); // Show loading while updating

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(widget.docId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) {
          throw Exception("Medication document does not exist!");
        }

        final data = snapshot.data()!;
        // Ensure missedDoses is treated as List<Map<String, dynamic>>
        final missedDosesRaw = data['missedDoses'] as List<dynamic>? ?? [];
        final List<Map<String, dynamic>> missedDoses = List<Map<String, dynamic>>.from(
            missedDosesRaw.whereType<Map<String, dynamic>>()
        );


        int foundIndex = -1;
        for (int i = 0; i < missedDoses.length; i++) {
          final dose = missedDoses[i];
          final scheduledTimestamp = dose['scheduled'] as Timestamp?;
          if (scheduledTimestamp != null && scheduledTimestamp == targetTimestamp) {
            foundIndex = i;
            break;
          }
        }

        if (foundIndex != -1) {
          // Update existing entry
          missedDoses[foundIndex]['status'] = newStatus;
          missedDoses[foundIndex]['updatedAt'] = Timestamp.now(); // Add update timestamp
        } else {
          // Add new entry if it wasn't found
          missedDoses.add({
            'scheduled': targetTimestamp,
            'status': newStatus,
            'createdAt': Timestamp.now(), // Add creation timestamp
          });
        }

        transaction.update(docRef, {
          'missedDoses': missedDoses,
          'lastUpdated': Timestamp.now(), // Update medication's last update time
        });
      });

      if (mounted) {
        setState(() {
          _doseStatus = newStatus; // Optimistically update UI
          _isLoadingStatus = false;
        });
        widget.onDataChanged(); // Refresh the main list if needed (e.g., if filtering by status)

        // If status changed to 'taken', reschedule the notification for tomorrow
        if (newStatus == 'taken') {
          // Cancel today's notification and schedule for tomorrow
          final notificationId = widget.docId.hashCode + doseTime.hour * 100 + doseTime.minute;
          DateTime tomorrowTime = DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day + 1,
            doseTime.hour,
            doseTime.minute,
          );

          // FIX: Ensure proper docId is passed for the medication
          print("Rescheduling notification with docId: ${widget.docId}"); // ADDED LOG
          await scheduleNotification(
            id: notificationId,
            title: 'تذكير الدواء',
            body: 'حان وقت تناول ${widget.medicationName}',
            scheduledTime: tomorrowTime,
            docId: widget.docId, // Correctly pass the document ID
          );
        }
      }

    } catch (e) {
      print('Error toggling dose status: $e');
      if (mounted) {
        setState(() {
          _isLoadingStatus = false; // Stop loading on error
          // Revert optimistic update maybe? Or show error.
          _checkDoseStatus(); // Re-fetch the actual status on error
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("فشل تحديث حالة الجرعة: $e"), backgroundColor: Colors.red));
        });
      }
    }
  }

  // Confirmation Dialog - styled
  Future<bool?> _showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    Color confirmButtonColor = Colors.red,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must explicitly choose
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // Rounded corners
        title: Text(title, style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
        content: Text(content, style: TextStyle(color: Colors.black87)),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmButtonColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  // --- Action Handlers (Edit, Finish, Delete) ---
  // These remain logically the same but use the styled confirmation dialog
  // and themed Snackbars.

  Future<void> _handleEdit(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "تعديل الدواء",
      content: "هل تريد الانتقال إلى شاشة تعديل بيانات هذا الدواء؟",
      confirmText: "نعم، تعديل",
      confirmButtonColor: Colors.orange.shade700, // Use theme action colors
    );

    if (confirmed == true && mounted) {
      // Ensure the EditMedicationScreen exists and the route is correct
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditMedicationScreen(docId: widget.docId),
        ),
      );
      // Check if data might have changed (e.g., if Edit screen returns true)
      // or just always refresh
      // if (result == true) {
      widget.onDataChanged();
      // }
    }
  }

  Future<void> _handleFinishMed(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "إنهاء الدواء",
      content: "هل أنت متأكد من إنهاء جدول هذا الدواء؟ سيتم تحديد تاريخ الانتهاء إلى اليوم ولن يظهر في الأيام القادمة.",
      confirmText: "نعم، إنهاء",
      confirmButtonColor: Colors.red.shade700, // Use theme action colors
    );

    if (confirmed == true) {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("خطأ: المستخدم غير مسجل."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
        return;
      }

      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('medicines')
              .doc(widget.docId)
              .update({'endDate': Timestamp.now()});

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: const Text("تم إنهاء الدواء بنجاح"), backgroundColor: Colors.orange.shade700, behavior: SnackBarBehavior.floating), // Orange for finish
            );
            widget.onDataChanged(); // Refresh the list
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("فشل إنهاء الدواء: $e"), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
          }
        }
      }
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "تأكيد الحذف",
      content: "هل أنت متأكد من حذف هذا الدواء؟ سيتم حذف صورته أيضاً إذا كانت مرتبطة (لا يمكن التراجع عن هذا الإجراء).",
      confirmText: "نعم، حذف",
      confirmButtonColor: Colors.red.shade700, // Use theme action colors
    );

    if (confirmed == true) {
      await _deleteMedication(context);
    }
  }

  Future<void> _deleteMedication(BuildContext context) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("خطأ: المستخدم غير مسجل."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      return;
    }

    if (user != null) {
      // Show loading indicator during deletion
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        // Attempt to delete ImgBB image first (if hash exists)
        if (widget.imgbbDeleteHash.isNotEmpty) {
          // IMPORTANT: Handle API Key securely in production!
          // Avoid hardcoding keys directly in the source code.
          // Consider using environment variables or a configuration file.
          await _deleteImgBBImage(widget.imgbbDeleteHash);
        }

        // Delete Firestore document
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('medicines')
            .doc(widget.docId)
            .delete();

        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text("تم حذف الدواء بنجاح"), backgroundColor: Colors.green.shade700, behavior: SnackBarBehavior.floating), // Green for success
          );
          widget.onDataChanged(); // Refresh the list
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("فشل حذف الدواء: $e"), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
        }
      }
    }
  }

  // ImgBB Deletion - Keep logic, add API Key warning
  Future<void> _deleteImgBBImage(String deleteHash) async {
    // --- IMPORTANT SECURITY WARNING ---
    // Hardcoding API keys is insecure. Use environment variables,
    // a secrets manager, or a secure configuration method in production.
    const String imgbbApiKey = '2b30d3479663bc30a70c916363b07c4a'; // Replace with your actual key securely

    if (imgbbApiKey == 'YOUR_IMGBB_API_KEY' || imgbbApiKey.isEmpty || imgbbApiKey == '2b30d3479663bc30a70c916363b07c4a' /* Check for placeholder */) {
      print("WARNING: ImgBB API Key not configured securely or is a placeholder. Skipping image deletion.");
      return; // Skip deletion if key is not configured
    }

    // Construct the deletion URL (Using POST as per potential ImgBB API changes, verify their docs)
    // Check ImgBB documentation for the correct deletion endpoint and method (GET/POST/DELETE)
    final url = Uri.parse('https://api.imgbb.com/1/image/$deleteHash'); // Base URL, add key later

    try {
      // Example using POST (adjust if ImgBB uses DELETE or GET)
      final response = await http.post(
        url,
        body: {'key': imgbbApiKey, 'action': 'delete'}, // Send key and action in body
      );

      // Check ImgBB API documentation for expected success codes (might be 200 or others)
      if (response.statusCode == 200) {
        print("ImgBB image ($deleteHash) deletion request sent successfully. Response: ${response.body}");
        // Note: ImgBB might return success even if the image was already deleted or hash is invalid.
      } else {
        print("Failed to delete image from ImgBB ($deleteHash). Status: ${response.statusCode}, Body: ${response.body}");
        // Log the error, but don't necessarily block Firestore deletion
      }
    } catch (e) {
      print("Error sending delete request to ImgBB ($deleteHash): $e");
      // Log the error
    }
  }
  // --- End Action Handlers ---

  @override
  Widget build(BuildContext context) {
    // Main content of the tile
    Widget tileContent = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Adjust padding
      leading: EnlargeableImage( // Use the styled image widget
        imageUrl: widget.imageUrl,
        width: 55, // Slightly smaller image
        height: 55,
      ),
      title: Text(
        widget.medicationName,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600, // Bold but not too heavy
          color: Colors.blue.shade900, // Darker blue for title
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Row( // Use Row for icon + time
          children: [
            Icon(Icons.access_time_rounded, size: 15, color: Colors.blue.shade700),
            const SizedBox(width: 4),
            Text(
              widget.nextDose,
              style: TextStyle(
                fontSize: 14,
                color: Colors.blue.shade700, // Consistent blue
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      // Trailing section for status and expand icon
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status Indicator / Button
          _isLoadingStatus
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
            icon: Icon(
              _doseStatus == 'taken'
                  ? Icons.check_circle_rounded // Filled check for taken
                  : Icons.radio_button_unchecked_rounded, // Outline for pending/missed
              color: _doseStatus == 'taken'
                  ? Colors.green.shade600 // Success color
                  : Colors.grey.shade500, // Neutral color
              size: 26, // Slightly larger icon
            ),
            onPressed: _toggleDoseStatus,
            tooltip: _doseStatus == 'taken' ? "تم أخذ الجرعة" : "لم تؤخذ الجرعة",
          ),
          const SizedBox(width: 4), // Space before expand icon
          // Expand Icon
          Icon(
            _isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            color: Colors.grey.shade500,
          ),
        ],
      ),
      onTap: () => setState(() => _isExpanded = !_isExpanded), // Toggle expansion on tap
    );

    // Action buttons shown when expanded
    Widget actionButtons = Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 10.0, right: 16.0, left: 16.0), // Adjust padding
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            context: context,
            icon: Icons.edit_note_rounded, // Themed icon
            label: "تعديل",
            color: Colors.orange.shade700, // Theme color
            onPressed: () => _handleEdit(context),
          ),
          _buildActionButton(
            context: context,
            icon: Icons.event_busy_rounded, // Themed icon for finish/stop
            label: "إنهاء",
            color: Colors.red.shade600, // Theme color (use a distinct red)
            onPressed: () => _handleFinishMed(context),
          ),
          _buildActionButton(
            context: context,
            icon: Icons.delete_forever_rounded, // Themed icon
            label: "حذف",
            color: Colors.red.shade800, // Darker red for delete
            onPressed: () => _handleDelete(context),
          ),
        ],
      ),
    );

    // Combine into a Card with themed border and shadow
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 0), // Adjust margin
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Consistent rounding
        side: BorderSide( // Add border based on status
          color: _doseStatus == 'taken'
              ? Colors.green.shade200.withOpacity(0.7)
              : Colors.grey.shade300.withOpacity(0.7),
          width: 1.5,
        ),
      ),
      elevation: 1.5, // Softer elevation
      shadowColor: Colors.blue.shade100.withOpacity(0.2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded), // Toggle on tap
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Apply subtle background highlight if taken
            Container(
              decoration: BoxDecoration(
                color: _doseStatus == 'taken' ? Colors.green.shade50.withOpacity(0.5) : Colors.transparent,
                borderRadius: BorderRadius.vertical(
                    top: const Radius.circular(12),
                    // Apply bottom radius only if not expanded
                    bottom: Radius.circular(_isExpanded ? 0 : 12)
                ),
              ),
              child: tileContent,
            ),
            // Animated expansion for action buttons
            AnimatedCrossFade(
              firstChild: Container(), // Empty container when collapsed
              secondChild: Container( // Container for actions with top border
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
                  ),
                  child: actionButtons
              ),
              crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200), // Faster animation
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      icon: Icon(icon, color: color, size: 20),
      label: Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
// --- End DoseTile Widget ---