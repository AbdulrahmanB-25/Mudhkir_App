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
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("الرجاء تسجيل الدخول أولاً")),
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

  // Fetch doses from Firestore; adjust parsing based on the data format created in add_dose.dart.
  Future<void> _fetchDoses() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final Map<DateTime, List<Map<String, dynamic>>> newDoses = {};
    final String userId = _user.uid;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String medicationName = data['name'] as String? ?? 'دواء غير مسمى';
        final String dosage = data['dosage'] as String? ?? 'غير محددة';
        final Timestamp? startTimestamp = data['startDate'] as Timestamp?;
        final Timestamp? endTimestamp = data['endDate'] as Timestamp?;

        // If no start date, skip document.
        if (startTimestamp == null) {
          print('Document ${doc.id} missing start date. Skipping.');
          continue;
        }

        // Determine frequency type from the 'frequency' field (e.g. "2 يومي" or "2 اسبوعي")
        final String frequencyRaw = data['frequency'] as String? ?? '1 يومي';
        final List<String> frequencyParts = frequencyRaw.split(" ");
        final String frequencyType = frequencyParts.length > 1 ? frequencyParts[1] : 'يومي';

        final List<dynamic> timesRaw = data['times'] ?? [];
        final String imageUrl = data['imageUrl'] as String? ?? '';
        final String imgbbDeleteHash = data['imgbbDeleteHash'] as String? ?? '';

        final DateTime startDate = startTimestamp.toDate();
        final DateTime? endDate = endTimestamp?.toDate();

        DateTime currentDate = startDate;
        // Iterate through dates relevant to the medication schedule.
        while (endDate == null || !currentDate.isAfter(endDate)) {
          final DateTime normalizedDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
          bool shouldAddDoseToday = false;
          List<TimeOfDay> timesParsed = [];

          if (frequencyType == 'يومي') {
            // For daily, timesRaw is a list of strings.
            timesParsed = timesRaw
                .map((t) => t != null ? TimeUtils.parseTime(t.toString()) : null)
                .whereType<TimeOfDay>()
                .toList();
            shouldAddDoseToday = timesParsed.isNotEmpty;
          } else if (frequencyType == 'اسبوعي') {
            // For weekly, timesRaw is a list of maps with keys "day" and "time"
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
                'timeOfDay': time, // Store for sorting
                'timeString': TimeUtils.formatTimeOfDay(context, time),
                'docId': doc.id,
                'imageUrl': imageUrl,
                'imgbbDeleteHash': imgbbDeleteHash,
              });
            }
          }

          currentDate = currentDate.add(const Duration(days: 1));
          if (endDate != null && currentDate.isAfter(endDate)) break;
          if (endDate == null && currentDate.year > DateTime.now().year + 10) {
            print("Warning: Medication ${doc.id} seems to have no end date; stopping iteration after 10 years.");
            break;
          }
        }
      }

      // Sort doses within each day by time and then by medication name.
      newDoses.forEach((date, meds) {
        meds.sort((a, b) {
          final TimeOfDay timeA = a['timeOfDay'];
          final TimeOfDay timeB = b['timeOfDay'];
          final int cmp = timeA.hour != timeB.hour
              ? timeA.hour.compareTo(timeB.hour)
              : timeA.minute.compareTo(timeB.minute);
          if (cmp != 0) return cmp;
          return a['medicationName'].compareTo(b['medicationName']);
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
        setState(() {
          _isLoading = false;
          _doses = {};
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("حدث خطأ أثناء تحميل جدول الأدوية.")),
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
    if (!_isLoading && FirebaseAuth.instance.currentUser == null) {
      return Scaffold(
        body: Center(
          child: Text("الرجاء تسجيل الدخول لعرض الجدول.",
              style: TextStyle(color: Colors.red.shade800)),
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
              // Custom Header.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new,
                          color: Colors.blue.shade800, size: 24),
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
                    const SizedBox(width: 48), // Balance the row.
                  ],
                ),
              ),
              // Scrollable Content Area.
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        // Calendar Card.
                        Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TableCalendar<Map<String, dynamic>>(
                              locale: 'ar_SA', // Arabic locale.
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
                                leftChevronIcon: Icon(Icons.chevron_left,
                                    color: Colors.blue.shade600),
                                rightChevronIcon: Icon(Icons.chevron_right,
                                    color: Colors.blue.shade600),
                              ),
                              calendarBuilders: CalendarBuilders(
                                markerBuilder: (context, date, events) =>
                                const SizedBox.shrink(),
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
                                weekendTextStyle: TextStyle(
                                  color: Colors.red[600],
                                ),
                              ),
                              onFormatChanged: (format) {
                                if (_calendarFormat != format) {
                                  setState(() => _calendarFormat = format);
                                }
                              },
                              onPageChanged: (focusedDay) {
                                _focusedDay = focusedDay;
                              },
                              onDaySelected: (selectedDay, focusedDay) {
                                if (!isSameDay(_selectedDay, selectedDay)) {
                                  setState(() {
                                    _selectedDay = selectedDay;
                                    _focusedDay = focusedDay;
                                  });
                                }
                              },
                              selectedDayPredicate: (day) =>
                                  isSameDay(_selectedDay, day),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Dose List Section Title.
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8.0, vertical: 8.0),
                          child: Text(
                            "جرعات يوم: ${DateFormat('EEEE, d MMMM yyyy', 'ar_SA').format(_selectedDay)}",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        // Dose List.
                        _buildDoseList(),
                        const SizedBox(height: 20), // Bottom Padding.
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
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
        child: Center(
          child: Text(
            "لا توجد جرعات لهذا اليوم",
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ),
      );
    } else {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final dose = events[index];
          final String docId = dose['docId'] ?? 'missing_doc_id_$index';
          final String timeString = dose['timeString'] ?? '??:??';

          return DoseTile(
            key: ValueKey(docId + timeString),
            medicationName: dose['medicationName'] ?? 'غير مسمى',
            nextDose: timeString,
            docId: docId,
            imageUrl: dose['imageUrl'] ?? '',
            imgbbDeleteHash: dose['imgbbDeleteHash'] ?? '',
            onDataChanged: _fetchDoses,
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
  final VoidCallback onDataChanged;

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
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
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

  Future<void> _handleEdit(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "تعديل الدواء",
      content: "هل تريد الانتقال إلى شاشة تعديل بيانات هذا الدواء؟",
      confirmText: "نعم، تعديل",
      confirmButtonColor: Colors.orange.shade700,
    );

    if (confirmed == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditMedicationScreen(docId: widget.docId),
        ),
      ).then((_) {
        widget.onDataChanged();
      });
    }
  }

  Future<void> _handleFinishMed(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "إنهاء الدواء",
      content:
      "هل أنت متأكد من إنهاء جدول هذا الدواء؟ سيتم تحديد تاريخ الانتهاء إلى اليوم ولن يظهر في الأيام القادمة.",
      confirmText: "نعم، إنهاء",
      confirmButtonColor: Colors.red.shade700,
    );

    if (confirmed == true) {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("خطأ: المستخدم غير مسجل.")));
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
              const SnackBar(content: Text("تم إنهاء الدواء بنجاح"), backgroundColor: Colors.orange),
            );
            widget.onDataChanged();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("فشل إنهاء الدواء: $e"), backgroundColor: Colors.red));
          }
        }
      }
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "تأكيد الحذف",
      content:
      "هل أنت متأكد من حذف هذا الدواء؟ سيتم حذف صورته أيضاً إذا كانت مرتبطة (لا يمكن التراجع عن هذا الإجراء).",
      confirmText: "نعم، حذف",
      confirmButtonColor: Colors.red.shade700,
    );

    if (confirmed == true) {
      await _deleteMedication(context);
    }
  }

  Future<void> _deleteMedication(BuildContext context) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("خطأ: المستخدم غير مسجل.")));
      return;
    }

    if (user != null) {
      try {
        if (widget.imgbbDeleteHash.isNotEmpty) {
          await _deleteImgBBImage(widget.imgbbDeleteHash);
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('medicines')
            .doc(widget.docId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("تم حذف الدواء بنجاح"), backgroundColor: Colors.green),
          );
          widget.onDataChanged();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("فشل حذف الدواء: $e"), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _deleteImgBBImage(String deleteHash) async {
    const String imgbbApiKey = '2b30d3479663bc30a70c916363b07c4a';
    if (imgbbApiKey == '2b30d3479663bc30a70c916363b07c4a' || imgbbApiKey.isEmpty) {
      print("WARNING: ImgBB API Key not configured securely. Skipping image deletion.");
      return;
    }

    final url = Uri.parse('https://api.imgbb.com/1/image/$deleteHash?key=$imgbbApiKey');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        print("ImgBB image deleted successfully. Response: ${response.body}");
      } else {
        print("Failed to delete image from ImgBB ($deleteHash). Status: ${response.statusCode}, Body: ${response.body}");
      }
    } catch (e) {
      print("Error deleting image from ImgBB ($deleteHash): $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tileContent = ListTile(
      leading: EnlargeableImage(
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
      trailing: Icon(
        _isExpanded ? Icons.expand_less : Icons.expand_more,
        color: Colors.grey.shade500,
      ),
    );

    Widget actionButtons = Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 8.0, right: 16.0, left: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            context: context,
            icon: Icons.edit_note,
            label: "تعديل",
            color: Colors.orange.shade700,
            onPressed: () => _handleEdit(context),
          ),
          _buildActionButton(
            context: context,
            icon: Icons.check_circle_outline,
            label: "إنهاء",
            color: Colors.red.shade700,
            onPressed: () => _handleFinishMed(context),
          ),
          _buildActionButton(
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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tileContent,
            AnimatedCrossFade(
              firstChild: Container(),
              secondChild: actionButtons,
              crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
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
