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
import 'package:mudhkir_app/pages/EditMedicationScreen.dart'; // <-- ADJUST PATH AS NEEDED

// --- Time Utilities (Ideally move to a separate utils file) ---
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


// --- EnlargeableImage Widget (Keep here or import if moved) ---
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
    // Use tryParse for better handling of invalid URLs
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
            backgroundColor: Colors.black87,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
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
    if (widget.imageUrl.isEmpty || uri == null || !uri.isAbsolute) {
      return _buildPlaceholder(showErrorText: false);
    }

    return FutureBuilder<File?>(
      future: _imageFileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        } else if (snapshot.hasData && snapshot.data != null) {
          return GestureDetector(
            onTap: () => _openEnlargedImage(context, snapshot.data!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                snapshot.data!,
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  print("Error displaying file image: $error");
                  return _buildPlaceholder(showErrorText: true);
                },
              ),
            ),
          );
        } else {
          return _buildPlaceholder(showErrorText: true);
        }
      },
    );
  }

  Widget _buildPlaceholder({required bool showErrorText}) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(
        showErrorText ? Icons.broken_image : Icons.image_not_supported,
        color: Colors.grey.shade600,
        size: widget.width * 0.6,
      ),
    );
  }
}
// --- End EnlargeableImage Widget ---


// --- DoseSchedule Widget ---
class DoseSchedule extends StatefulWidget {
  const DoseSchedule({super.key});

  @override
  _DoseScheduleState createState() => _DoseScheduleState();
}

class _DoseScheduleState extends State<DoseSchedule> {
  late User _user;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<Map<String, dynamic>>> _doses = {};
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print("Error: User not logged in for DoseSchedule.");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Avoid popping if already disposed or not part of navigator
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("الرجاء تسجيل الدخول أولاً"))
          );
        }
      });
      _isLoading = false;
    } else {
      _user = currentUser;
      _fetchDoses(); // Fetch doses only if user is logged in
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // Fetch doses from Firestore
  Future<void> _fetchDoses() async {
    if (!mounted) return; // Check if widget is still mounted
    setState(() { _isLoading = true; });

    final Map<DateTime, List<Map<String, dynamic>>> newDoses = {};

    // Defensive check: Ensure _user is initialized (should be if logic is correct)
    if (FirebaseAuth.instance.currentUser == null) {
      print("Error in _fetchDoses: User became null.");
      if (mounted) {
        setState(() { _isLoading = false; _doses = {}; });
        // Optionally navigate back or show persistent error
      }
      return;
    }
    // Use the initialized _user variable
    final String userId = _user.uid;


    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId) // Use stored user ID
          .collection('medicines')
          .get();

      if (!mounted) return; // Check again after async gap

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String medicationName = data['name'] as String? ?? 'دواء غير مسمى';
        final Timestamp? startTimestamp = data['startDate'] as Timestamp?;
        final Timestamp? endTimestamp = data['endDate'] as Timestamp?;

        if (startTimestamp == null) {
          print('Document ${doc.id} missing start date. Skipping.');
          continue;
        }

        final DateTime startDate = startTimestamp.toDate();
        final DateTime? endDate = endTimestamp?.toDate();
        final List<dynamic> timesRaw = data['times'] ?? [];
        final List<TimeOfDay> timesParsed = timesRaw
            .map((t) => t != null ? TimeUtils.parseTime(t.toString()) : null) // Use TimeUtils
            .whereType<TimeOfDay>()
            .toList();

        if (timesParsed.isEmpty) {
          print('Document ${doc.id} has no valid times. Skipping.');
          continue;
        }

        final String frequencyType = data['frequencyType'] as String? ?? 'يومي';
        final List<int> weeklyDays = (data['weeklyDays'] as List<dynamic>?)
            ?.whereType<int>()
            ?.toList() ?? [];
        final String imageUrl = data['imageUrl'] as String? ?? '';
        final String imgbbDeleteHash = data['imgbbDeleteHash'] as String? ?? '';

        DateTime currentDate = startDate;
        // Iterate through dates relevant to the medication schedule
        while (endDate == null || !currentDate.isAfter(endDate)) {
          // Normalize date to ignore time component for map key
          final DateTime normalizedDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
          bool shouldAddDoseToday = false;

          // Determine if the dose should be added based on frequency
          if (frequencyType == 'يومي') {
            shouldAddDoseToday = true;
          } else if (frequencyType == 'اسبوعي') {
            if (weeklyDays.contains(currentDate.weekday)) {
              shouldAddDoseToday = true;
            }
          }
          // Add logic for other frequency types if needed

          if (shouldAddDoseToday) {
            newDoses.putIfAbsent(normalizedDate, () => []);
            for (var time in timesParsed) {
              newDoses[normalizedDate]!.add({
                'medicationName': medicationName,
                'timeOfDay': time, // Store TimeOfDay for sorting
                'timeString': TimeUtils.formatTimeOfDay(context, time), // Use TimeUtils
                'docId': doc.id,
                'imageUrl': imageUrl,
                'imgbbDeleteHash': imgbbDeleteHash,
              });
            }
          }

          currentDate = currentDate.add(const Duration(days: 1));
          // Safety break for potentially long loops
          if (endDate != null && currentDate.isAfter(endDate)) break;
          if (endDate == null && currentDate.year > DateTime.now().year + 10) {
            print("Warning: Medication ${doc.id} seems to have no end date, stopping iteration after 10 years.");
            break;
          }
        }
      }

      // Sort doses within each day by time
      newDoses.forEach((date, meds) {
        meds.sort((a, b) {
          final TimeOfDay timeA = a['timeOfDay'];
          final TimeOfDay timeB = b['timeOfDay'];
          if (timeA.hour != timeB.hour) return timeA.hour.compareTo(timeB.hour);
          return timeA.minute.compareTo(timeB.minute);
        });
      });

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
        setState(() { _isLoading = false; _doses = {}; }); // Clear doses on error
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("حدث خطأ أثناء تحميل جدول الأدوية."))
        );
      }
    }
  }

  // Get events for a specific day (used by TableCalendar)
  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final DateTime normalizedDay = DateTime(day.year, day.month, day.day);
    return _doses[normalizedDay] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    // Handle case where user wasn't logged in or became logged out
    if (!_isLoading && FirebaseAuth.instance.currentUser == null) {
      return Scaffold(
        body: Center(
          child: Text("الرجاء تسجيل الدخول لعرض الجدول.", style: TextStyle(color: Colors.red.shade800)),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: Colors.blue.shade800, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      "جدول الأدوية",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(width: 48), // Balance the row
                  ],
                ),
              ),
              // Scrollable Content Area
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        // Calendar Card
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TableCalendar<Map<String, dynamic>>(
                              locale: 'ar_SA', // Arabic locale
                              focusedDay: _focusedDay,
                              firstDay: DateTime.utc(DateTime.now().year - 2, 1, 1),
                              lastDay: DateTime.utc(DateTime.now().year + 5, 12, 31),
                              calendarFormat: _calendarFormat,
                              availableCalendarFormats: const {
                                CalendarFormat.month: 'أسبوع',
                                CalendarFormat.twoWeeks: 'شهر',
                                CalendarFormat.week: 'اسبوعين',
                              },
                              eventLoader: _getEventsForDay,
                              headerStyle: HeaderStyle(
                                formatButtonVisible: true,
                                titleCentered: true,
                                titleTextStyle: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                ),
                                leftChevronIcon: Icon(Icons.chevron_left, color: Colors.blue.shade600),
                                rightChevronIcon: Icon(Icons.chevron_right, color: Colors.blue.shade600),
                              ),
                              calendarBuilders: CalendarBuilders(
                                  markerBuilder: (context, date, events) => const SizedBox.shrink(),
                              ),
                              calendarStyle: CalendarStyle(
                                outsideDaysVisible: false,
                                todayDecoration: BoxDecoration(
                                  color: Colors.blue.shade700,
                                  shape: BoxShape.circle,
                                ),
                                selectedDecoration: BoxDecoration(
                                  color: Colors.lightBlueAccent,
                                  shape: BoxShape.circle,
                                ),
                                // Ensure weekend style is subtle or match default
                                weekendTextStyle: TextStyle(color: Colors.red[600]), // Example
                              ),
                              onFormatChanged: (format) {
                                if (_calendarFormat != format) {
                                  setState(() => _calendarFormat = format);
                                }
                              },
                              onPageChanged: (focusedDay) {
                                // No need to call setState for focusedDay changes triggered by page change
                                _focusedDay = focusedDay;
                              },
                              onDaySelected: (selectedDay, focusedDay) {
                                if (!isSameDay(_selectedDay, selectedDay)) {
                                  setState(() {
                                    _selectedDay = selectedDay;
                                    _focusedDay = focusedDay; // Update focused day as well
                                  });
                                }
                              },
                              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Dose List Section Title
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                          child: Text(
                            // Use intl DateFormat for localized date string
                            "جرعات يوم: ${DateFormat('EEEE, d MMMM yyyy', 'ar_SA').format(_selectedDay)}",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
                            textAlign: TextAlign.center,
                          ),
                        ),

                        // Dose List
                        _buildDoseList(),

                        const SizedBox(height: 20), // Padding at the bottom
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

  // Helper widget to build the list of doses for the selected day
  Widget _buildDoseList() {
    final events = _getEventsForDay(_selectedDay);
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
        child: Center(
          child: Text(
            "لا توجد جرعات لهذا اليوم",
            style: TextStyle( fontSize: 16, color: Colors.grey.shade600,),
          ),
        ),
      );
    } else {
      return ListView.builder(
        shrinkWrap: true, // Essential inside SingleChildScrollView
        physics: const NeverScrollableScrollPhysics(), // Disable its own scrolling
        itemCount: events.length,
        itemBuilder: (context, index) {
          final dose = events[index];
          // Ensure all required fields exist before creating DoseTile
          final String docId = dose['docId'] ?? 'missing_doc_id_${index}';
          final String timeString = dose['timeString'] ?? '??:??';

          return DoseTile(
            key: ValueKey(docId + timeString), // Unique key for the tile
            medicationName: dose['medicationName'] ?? 'غير مسمى',
            nextDose: timeString,
            docId: docId,
            imageUrl: dose['imageUrl'] ?? '',
            imgbbDeleteHash: dose['imgbbDeleteHash'] ?? '',
            onDataChanged: _fetchDoses, // Pass the refresh callback
          );
        },
      );
    }
  }
}
// --- End DoseSchedule Widget ---


// --- MODIFIED DoseTile Widget ---
class DoseTile extends StatefulWidget {
  final String medicationName;
  final String nextDose;
  final String docId;
  final String imageUrl;
  final String imgbbDeleteHash;
  final VoidCallback onDataChanged; // Callback to refresh list after actions

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
  bool _isExpanded = false; // State to track if the tile is expanded

  // --- Reusable Confirmation Dialog ---
  Future<bool?> _showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    Color confirmButtonColor = Colors.red,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(color: Colors.blue.shade800)),
        content: Text(content),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Cancel
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true), // Confirm
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmButtonColor,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  // --- Action Handlers ---

  // Navigate to Edit Screen
  Future<void> _handleEdit(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "تعديل الدواء",
      content: "هل تريد الانتقال إلى شاشة تعديل بيانات هذا الدواء؟",
      confirmText: "نعم، تعديل",
      confirmButtonColor: Colors.orange.shade700,
    );

    if (confirmed == true && mounted) {
      print("Navigating to edit screen for docId: ${widget.docId}");
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditMedicationScreen(docId: widget.docId),
        ),
      ).then((_) {
        // After returning from Edit screen, refresh the schedule data
        print("Returned from Edit screen, refreshing data...");
        widget.onDataChanged();
      });
    }
  }

  // Mark Medication as Finished (Update endDate in Firestore)
  Future<void> _handleFinishMed(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "إنهاء الدواء",
      content: "هل أنت متأكد من إنهاء جدول هذا الدواء؟ سيتم تحديد تاريخ الانتهاء إلى اليوم ولن يظهر في الأيام القادمة.",
      confirmText: "نعم، إنهاء",
      confirmButtonColor: Colors.red.shade700,
    );

    if (confirmed == true) {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("خطأ: المستخدم غير مسجل."))
        );
        return;
      }

      if (user != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('medicines')
              .doc(widget.docId)
              .update({'endDate': Timestamp.now()}); // Set end date to now

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("تم إنهاء الدواء بنجاح"), backgroundColor: Colors.orange),
            );
            widget.onDataChanged(); // Refresh the list
          }
        } catch (e) {
          print("Error finishing medication (${widget.docId}): $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("فشل إنهاء الدواء: $e"), backgroundColor: Colors.red)
            );
          }
        }
      }
    }
  }

  // Trigger Deletion after Confirmation
  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "تأكيد الحذف",
      content: "هل أنت متأكد من حذف هذا الدواء؟ سيتم حذف صورته أيضاً إذا كانت مرتبطة (لا يمكن التراجع عن هذا الإجراء).",
      confirmText: "نعم، حذف",
      confirmButtonColor: Colors.red.shade700,
    );

    if (confirmed == true) {
      // Call the actual deletion logic only if confirmed
      await _deleteMedication(context);
    }
  }

  // Actual Deletion Logic (Firestore & ImgBB)
  Future<void> _deleteMedication(BuildContext context) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("خطأ: المستخدم غير مسجل."))
      );
      return;
    }

    if (user != null) {
      // Indicate deletion in progress (optional)
      // ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("جارٍ الحذف...")));

      try {
        // 1. Delete ImgBB image *first* if hash exists (INSECURE KEY HANDLING)
        if (widget.imgbbDeleteHash.isNotEmpty) {
          await _deleteImgBBImage(widget.imgbbDeleteHash); // Pass only hash
        }

        // 2. Delete Firestore document
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('medicines')
            .doc(widget.docId)
            .delete();

        // 3. Show success message and trigger list refresh via callback
        if (mounted) { // Check if widget is still in the tree
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم حذف الدواء بنجاح"), backgroundColor: Colors.green),
          );
          widget.onDataChanged(); // Refresh the list in the parent widget
        }

      } catch (e) {
        print("Error deleting medication (${widget.docId}): $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("فشل حذف الدواء: $e"), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  // Helper to delete image from ImgBB (INSECURE KEY HANDLING)
  Future<void> _deleteImgBBImage(String deleteHash) async {
    // CRITICAL SECURITY WARNING: API Key should not be hardcoded.
    // Replace with a secure method (e.g., call a Cloud Function).
    const String imgbbApiKey = 'YOUR_IMGBB_API_KEY';
    if (imgbbApiKey == 'YOUR_IMGBB_API_KEY' || imgbbApiKey.isEmpty) {
      print("WARNING: ImgBB API Key not configured securely. Skipping image deletion.");
      return; // Stop deletion if key isn't configured
    }

    final url = Uri.parse('https://api.imgbb.com/1/image/$deleteHash?key=$imgbbApiKey');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        print("ImgBB image deleted successfully. Response: ${response.body}");
      } else {
        print("Failed to delete image from ImgBB ($deleteHash). Status: ${response.statusCode}, Body: ${response.body}");
        // Optionally, inform the user that the document was deleted but the image might remain.
      }
    } catch (e) {
      print("Error deleting image from ImgBB ($deleteHash): $e");
      // Optionally, inform the user about the image deletion failure.
    }
  }


  @override
  Widget build(BuildContext context) {
    // Main visual content of the tile
    Widget tileContent = ListTile(
      leading: EnlargeableImage( // Use the EnlargeableImage widget defined above
        imageUrl: widget.imageUrl,
        width: 60,
        height: 60,
      ),
      title: Text(
        widget.medicationName,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blue.shade800,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        "الوقت: ${widget.nextDose}",
        style: TextStyle(
          fontSize: 14,
          color: Colors.blue.shade600,
        ),
      ),
      trailing: Icon( // Icon indicates expand/collapse state
        _isExpanded ? Icons.expand_less : Icons.expand_more,
        color: Colors.grey.shade500,
      ),
    );

    // Action buttons shown when expanded
    Widget actionButtons = Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 8.0, right: 16.0, left: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton( // Edit Button
            context: context,
            icon: Icons.edit_note,
            label: "تعديل",
            color: Colors.orange.shade700,
            onPressed: () => _handleEdit(context),
          ),
          _buildActionButton( // Finish Button
            context: context,
            icon: Icons.check_circle_outline,
            label: "إنهاء",
            color: Colors.red.shade700, // Use a distinct color for stop/finish
            onPressed: () => _handleFinishMed(context),
          ),
          _buildActionButton( // Delete Button
            context: context,
            icon: Icons.delete_forever_outlined,
            label: "حذف",
            color: Colors.red.shade700,
            onPressed: () => _handleDelete(context),
          ),
        ],
      ),
    );


    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
      // Use InkWell for tap detection and ripple effect on the whole card
      child: InkWell(
        borderRadius: BorderRadius.circular(12), // Match card shape
        onTap: () => setState(() => _isExpanded = !_isExpanded), // Toggle expansion
        child: Column(
          mainAxisSize: MainAxisSize.min, // Fit content height
          children: [
            tileContent, // Always visible part
            // Animated transition for showing/hiding action buttons
            AnimatedCrossFade(
              firstChild: Container(), // Empty container when collapsed
              secondChild: actionButtons, // Action buttons row when expanded
              crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250), // Animation speed
            ),
          ],
        ),
      ),
    );
  }

  // Helper to build consistently styled action buttons
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
        tapTargetSize: MaterialTapTargetSize.shrinkWrap, // Minimize padding
      ),
    );
  }
}
// --- End DoseTile Widget ---