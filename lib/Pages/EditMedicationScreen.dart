import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:mudhkir_app/main.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

import 'EditMedicationScreen.dart' as add_dose; // Import the notification utility

/// Helper function to normalize URLs by removing extra slashes,
/// while keeping the protocol part intact.
String normalizeUrl(String url) {
  // Look for the protocol portion ("http:" or "https:") followed by extra slashes.
  final RegExp protocolRegex = RegExp(r'^(https?:)\/+');
  final match = protocolRegex.firstMatch(url);
  if (match != null) {
    String scheme = match.group(1)!; // e.g., "https:"
    // Remove the matched protocol and extra slashes.
    String remaining = url.substring(match.end);
    // Replace multiple slashes in the remainder with a single slash.
    remaining = remaining.replaceAll(RegExp(r'/+'), '/');
    return '$scheme//$remaining';
  }
  return url.replaceAll(RegExp(r'/+'), '/'); // Fallback.
}

// ==================================================================
// Time Utilities
// ==================================================================
class TimeUtils {
  static TimeOfDay? parseTime(String timeStr) {
    try {
      final intl.DateFormat ampmFormat = intl.DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      String normalizedTime =
      timeStr.replaceAll('صباحاً', 'AM').replaceAll('مساءً', 'PM').trim();
      final intl.DateFormat arabicAmpmFormat =
      intl.DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = arabicAmpmFormat.parseStrict(normalizedTime);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        int minute =
        int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
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

// ==================================================================
// EnlargeableImage Widget
// ==================================================================
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
    // Normalize the URL to remove extra slashes.
    String normalizedUrl = normalizeUrl(url);
    final uri = Uri.tryParse(normalizedUrl);
    if (normalizedUrl.isEmpty || uri == null || !uri.isAbsolute) {
      print("Invalid or empty URL for download: $normalizedUrl");
      return null;
    }
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final Directory directory = await getTemporaryDirectory();
        final String filePath = '${directory.path}/${normalizedUrl.hashCode}.png';
        File file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      } else {
        print("Failed to download image ($normalizedUrl). Status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error downloading image ($normalizedUrl): $e");
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

// ==================================================================
// DoseSchedule Widget (Calendar & Dose List)
// ==================================================================
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
          if (Navigator.canPop(context)) Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("الرجاء تسجيل الدخول أولاً")));
        }
      });
      _isLoading = false;
    } else {
      _user = currentUser;
      _fetchDoses();
    }
  }
  Future<void> _fetchDoses() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });
    final Map<DateTime, List<Map<String, dynamic>>> newDoses = {};
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() { _isLoading = false; _doses = {}; });
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String medicationName = data['name'] ?? 'دواء غير مسمى';
        final String dosage = data['dosage'] ?? 'غير محددة';
        final Timestamp? startTimestamp = data['startDate'];
        final Timestamp? endTimestamp = data['endDate'];
        final String frequency = data['frequency'] ?? '1 يومي';
        final List<dynamic> timesRaw = data['times'] ?? [];
        final String imageUrl = data['imageUrl'] ?? '';
        final String imgbbDeleteHash = data['imgbbDeleteHash'] ?? '';
        if (startTimestamp == null) continue;
        final DateTime startDate = startTimestamp.toDate();
        final DateTime? endDateDt = endTimestamp?.toDate();
        final List<String> parts = frequency.split(" ");
        final String frequencyType = parts.length > 1 ? parts[1] : 'يومي';
        DateTime currentDate = startDate;
        while (true) {
          final DateTime normalizedDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
          bool shouldAddDose = false;
          List<Map<String, dynamic>> dosesForDay = [];
          if (frequencyType == 'يومي') {
            List<TimeOfDay> timesParsed = [];
            if (timesRaw.isNotEmpty && timesRaw.first is Map) {
              timesParsed = timesRaw
                  .whereType<Map>()
                  .map((m) => TimeUtils.parseTime(m['time'].toString()))
                  .whereType<TimeOfDay>()
                  .toList();
            } else {
              timesParsed = timesRaw
                  .map((t) => t != null ? TimeUtils.parseTime(t.toString()) : null)
                  .whereType<TimeOfDay>()
                  .toList();
            }
            for (var time in timesParsed) {
              dosesForDay.add({
                'medicationName': medicationName,
                'dosage': dosage,
                'timeOfDay': time,
                'timeString': TimeUtils.formatTimeOfDay(context, time),
                'docId': doc.id,
                'imageUrl': imageUrl,
                'imgbbDeleteHash': imgbbDeleteHash,
              });
            }
            shouldAddDose = dosesForDay.isNotEmpty;
          } else if (frequencyType == 'اسبوعي') {
            for (var map in timesRaw.whereType<Map>()) {
              final int? day = map['day'];
              final String? timeStr = map['time']?.toString();
              if (day != null && day == currentDate.weekday && timeStr != null) {
                final time = TimeUtils.parseTime(timeStr);
                if (time != null) {
                  dosesForDay.add({
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
            }
            shouldAddDose = dosesForDay.isNotEmpty;
          }
          if (shouldAddDose) {
            newDoses.putIfAbsent(normalizedDate, () => []);
            newDoses[normalizedDate]!.addAll(dosesForDay);
          }
          // Increment day and break conditions.
          currentDate = currentDate.add(const Duration(days: 1));
          if (endDateDt != null && currentDate.isAfter(endDateDt)) break;
          if (endDateDt == null && currentDate.year > DateTime.now().year + 10) break;
        }
      }
      newDoses.forEach((date, meds) {
        meds.sort((a, b) {
          final TimeOfDay timeA = a['timeOfDay'];
          final TimeOfDay timeB = b['timeOfDay'];
          final cmp = timeA.hour != timeB.hour
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
      print('Error fetching doses: $e\n$stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _doses = {};
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("حدث خطأ أثناء تحميل جدول الأدوية.")));
      }
    }
  }
  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final DateTime normalizedDay = DateTime(day.year, day.month, day.day);
    return _doses[normalizedDay] ?? [];
  }
  @override
  Widget build(BuildContext context) {
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
              // Header
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
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Content Area
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TableCalendar<Map<String, dynamic>>(
                              locale: 'ar_SA',
                              focusedDay: _focusedDay,
                              firstDay: DateTime.utc(DateTime.now().year - 2, 1, 1),
                              lastDay: DateTime.utc(DateTime.now().year + 5, 12, 31),
                              calendarFormat: _calendarFormat,
                              availableCalendarFormats: const {
                                CalendarFormat.month: 'شهر',
                                CalendarFormat.twoWeeks: 'اسبوعين',
                                CalendarFormat.week: 'أسبوع',
                              },
                              eventLoader: _getEventsForDay,
                              headerStyle: HeaderStyle(
                                formatButtonVisible: true,
                                titleCentered: true,
                                titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                leftChevronIcon: Icon(Icons.chevron_left, color: Colors.blue.shade600),
                                rightChevronIcon: Icon(Icons.chevron_right, color: Colors.blue.shade600),
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
                                weekendTextStyle: TextStyle(color: Colors.red[600]),
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
                              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                          child: Text(
                            "جرعات يوم: ${intl.DateFormat('EEEE, d MMMM yyyy', 'ar_SA').format(_selectedDay)}",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        _buildDoseList(),
                        const SizedBox(height: 20),
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
  Widget _buildDoseList() {
    final events = _getEventsForDay(_selectedDay);
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0),
        child: Center(
          child: Text("لا توجد جرعات لهذا اليوم",
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
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

// ==================================================================
// DoseTile Widget
// ==================================================================
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
      print("Navigating to edit screen for docId: ${widget.docId}");
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditMedicationScreen(docId: widget.docId),
        ),
      ).then((_) {
        print("Returned from Edit screen, refreshing data...");
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("خطأ: المستخدم غير مسجل.")));
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
          print("Error finishing medication (${widget.docId}): $e");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("فشل إنهاء الدواء: $e"), backgroundColor: Colors.red),
            );
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
      confirmButtonColor: Colors.red.shade700,
    );
    if (confirmed == true) {
      await _deleteMedication(context);
    }
  }
  Future<void> _deleteMedication(BuildContext context) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("خطأ: المستخدم غير مسجل.")));
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
        print("Error deleting medication (${widget.docId}): $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("فشل حذف الدواء: $e"), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
  Future<void> _deleteImgBBImage(String deleteHash) async {
    final String imgbbApiKey = dotenv.env['IMGBB_API_KEY'] ?? '';

    // Basic validation
    if (imgbbApiKey.isEmpty) {
      print("ERROR: ImgBB API Key not found in .env. Cannot delete image.");
      return;
    }
    if (deleteHash.isEmpty) {
      print("WARNING: Attempted to delete ImgBB image with an empty deleteHash.");
      return; // Don't proceed with an empty hash
    }

    // Construct the URL: API key in query parameter, delete hash in the path
    final url = Uri.parse('https://api.imgbb.com/1/image/$deleteHash?key=$imgbbApiKey');

    print("Attempting ImgBB deletion via DELETE. Hash: $deleteHash, URL: $url");

    try {
      final response = await http.delete(url); // Using DELETE method

      // Check status code FIRST
      if (response.statusCode == 200) {
        // Even with 200, check response body for success confirmation if possible
        try {
          final responseBody = jsonDecode(response.body);
          if (responseBody is Map &&
              ((responseBody.containsKey('success') && responseBody['success'] == true) ||
                  (responseBody.containsKey('status_code') && responseBody['status_code'] == 200))) {
            print("ImgBB image ($deleteHash) deleted successfully via DELETE. Response: ${response.body}");
          } else {
            // Status 200 but response body indicates potential failure
            print("ImgBB image ($deleteHash) deletion via DELETE returned status 200 but response suggests failure: ${response.body}");
          }
        } catch (e) {
          // Status 200 but couldn't parse body or unknown format
          print("ImgBB image ($deleteHash) deletion via DELETE returned status 200 but response body parsing failed or format unknown: ${response.body}. Error: $e");
        }
      } else {
        // Log the failure details clearly
        print("Failed to delete image from ImgBB ($deleteHash) using DELETE. Status: ${response.statusCode}, Body: ${response.body}");
        // If this fails with "Invalid API Action", the POST method might be needed.
      }
    } catch (e) {
      print("Error occurred during ImgBB image ($deleteHash) DELETE deletion attempt: $e");
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
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        "الوقت: ${widget.nextDose}",
        style: TextStyle(fontSize: 14, color: Colors.blue.shade600),
      ),
      trailing: Icon(
        _isExpanded ? Icons.expand_less : Icons.expand_more,
        color: Colors.grey.shade500,
      ),
    );
    Widget actionButtons = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
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

// ==================================================================
// EditMedicationScreen Widget (Updated Daily & Weekly UI)
// ==================================================================
class EditMedicationScreen extends StatefulWidget {
  final String docId;
  const EditMedicationScreen({super.key, required this.docId});
  @override
  _EditMedicationScreenState createState() => _EditMedicationScreenState();
}
class _EditMedicationScreenState extends State<EditMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  DocumentSnapshot? medicationDoc; // Add this field to store the medication document
  // Daily mode: list of dose times.
  List<TimeOfDay> _selectedTimes = [];
  // For tracking whether each daily time was auto-generated.
  List<bool> _dailyAutoGenerated = [];
  // Frequency selection – default set to daily.
  String _selectedFrequency = 'يومي';
  // For weekly mode only:
  Set<int> _selectedWeekdays = {};
  Map<int, TimeOfDay> _weeklyTimes = {};
  Map<int, bool> _weeklyAutoGenerated = {};
  String? _currentImageUrl;
  String? _currentImgbbDeleteHash;
  File? _newImageFile;
  bool _imageRemoved = false;
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = "المستخدم غير مسجل الدخول.";
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      });
    } else {
      _loadMedicationData();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadMedicationData() async {
    if (_user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "خطأ: المستخدم غير متوفر.";
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('medicines')
          .doc(widget.docId)
          .get();
      if (!mounted) return;
      if (docSnapshot.exists) {
        medicationDoc = docSnapshot; // Populate the medicationDoc field
        final data = docSnapshot.data()!;
        _nameController.text = data['name'] as String? ?? '';
        _selectedStartDate = (data['startDate'] as Timestamp?)?.toDate();
        _selectedEndDate = (data['endDate'] as Timestamp?)?.toDate();
        // Determine frequency mode:
        String? storedFrequency = data['frequencyType'] as String?;
        // If frequencyType is weekly or the "times" field is a list of maps, use weekly UI.
        if (storedFrequency == 'اسبوعي' ||
            (data['times'] is List &&
                (data['times'] as List).isNotEmpty &&
                (data['times'][0] is Map))) {
          _selectedFrequency = 'اسبوعي';
          _weeklyTimes = {};
          List<dynamic> timesList = data['times'] as List<dynamic>? ?? [];
          for (var item in timesList) {
            if (item is Map) {
              int? day = item['day'];
              String? timeStr = item['time']?.toString();
              if (day != null && timeStr != null) {
                final time = TimeUtils.parseTime(timeStr);
                if (time != null) {
                  _weeklyTimes[day] = time;
                }
              }
            }
          }
          _selectedWeekdays = _weeklyTimes.keys.toSet();
          _weeklyAutoGenerated = { for (var day in _selectedWeekdays) day: false };
        } else {
          _selectedFrequency = 'يومي';
          var rawTimes = data['times'];
          if (rawTimes is List<dynamic> && rawTimes.isNotEmpty) {
            if (rawTimes.first is Map) {
              _selectedTimes = rawTimes
                  .where((element) => element is Map)
                  .map((m) => TimeUtils.parseTime(m['time'].toString()))
                  .whereType<TimeOfDay>()
                  .toList();
            } else {
              _selectedTimes = rawTimes
                  .map((t) => t != null ? TimeUtils.parseTime(t.toString()) : null)
                  .whereType<TimeOfDay>()
                  .toList();
            }
          } else {
            _selectedTimes = [];
          }
          // Initialize daily auto-generated flags.
          _dailyAutoGenerated = List<bool>.filled(_selectedTimes.length, false, growable: true);
        }
        _currentImageUrl = data['imageUrl'] as String?;
        _currentImgbbDeleteHash = data['imgbbDeleteHash'] as String?;
        _newImageFile = null;
        _imageRemoved = false;
      } else {
        _errorMessage = "لم يتم العثور على بيانات الدواء.";
      }
    } catch (e, stackTrace) {
      print("Error loading medication data: $e\n$stackTrace");
      if (mounted) _errorMessage = "حدث خطأ أثناء تحميل البيانات.";
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _pickDate(BuildContext context, bool isStartDate) async {
    final initialDate = (isStartDate ? _selectedStartDate : _selectedEndDate) ?? DateTime.now();
    final firstDate = DateTime(DateTime.now().year - 5);
    final lastDate = DateTime(DateTime.now().year + 20);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('ar', 'SA'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate != null) {
      setState(() {
        if (isStartDate) {
          _selectedStartDate = pickedDate;
          if (_selectedEndDate != null && _selectedEndDate!.isBefore(_selectedStartDate!)) {
            _selectedEndDate = null;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("تم مسح تاريخ الانتهاء لأنه كان قبل تاريخ البدء الجديد."),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          if (_selectedStartDate != null && pickedDate.isBefore(_selectedStartDate!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("تاريخ الانتهاء لا يمكن أن يكون قبل تاريخ البدء.")),
            );
          } else {
            _selectedEndDate = pickedDate;
          }
        }
      });
    }
  }

  Future<void> _getImage(ImageSource source) async {
    try {
      // Request camera permission if camera is being used
      if (source == ImageSource.camera) {
        final cameraPermission = await Permission.camera.request();
        if (cameraPermission.isDenied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("يجب السماح بالوصول إلى الكاميرا لالتقاط صورة"))
          );
          return;
        }
      }

      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (image != null) {
        setState(() {
          _newImageFile = File(image.path);
          _imageRemoved = false;
        });
      }
    } catch (e) {
      print("Error getting image from $source: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("حدث خطأ أثناء ${source == ImageSource.camera ? 'التقاط الصورة' : 'اختيار الصورة'}."),
        ),
      );
    }
  }

  void _removeImage() {
    setState(() {
      _newImageFile = null;
      _imageRemoved = true;
    });
  }

  /// Uploads an image file to ImgBB and returns the image URL and delete hash.
  Future<Map<String, String>?> _uploadImageToImgBB(BuildContext context, File imageFile) async {
    final String imgbbApiKey = dotenv.env['IMGBB_API_KEY'] ?? '';

    // Validate API Key
    if (imgbbApiKey.isEmpty) {
      print("ERROR: ImgBB API Key not found in .env. Cannot upload image.");
      // Use mounted check if this is inside a StatefulWidget's State class
      // if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("خطأ في إعدادات رفع الصور.")),
      );
      // }
      return null;
    }

    // Prepare the upload request
    final url = Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbApiKey');
    print("Attempting ImgBB upload to: $url");

    try {
      var request = http.MultipartRequest('POST', url);
      // Attach the file to the request
      request.files.add(
        await http.MultipartFile.fromPath(
          'image', // API expects the file field name to be 'image'
          imageFile.path,
          // You might want to specify filename and content type if needed by API
          // filename: imageFile.path.split('/').last,
          // contentType: MediaType('image', 'jpeg'), // Or png, etc.
        ),
      );

      // Send the request and get the streamed response
      var streamedResponse = await request.send();

      // Get the full response body
      final response = await http.Response.fromStream(streamedResponse);

      // Check the status code
      if (response.statusCode == 200) {
        print("ImgBB upload successful (Status 200). Parsing response...");
        // Parse the JSON response body robustly
        try {
          final Map<String, dynamic> jsonResponse = jsonDecode(response.body);

          // Check if the response indicates success and contains data
          if (jsonResponse['success'] == true && jsonResponse.containsKey('data')) {
            final Map<String, dynamic> data = jsonResponse['data'];
            final String? imageUrl = data['url']; // URL of the displayed image
            final String? deleteUrl = data['delete_url']; // URL to delete the image

            if (imageUrl != null && deleteUrl != null) {
              // Extract the delete hash from the delete_url
              final deleteHash = deleteUrl.split('/').last;
              print("ImgBB parsing successful. ImageURL: $imageUrl, DeleteHash: $deleteHash");
              return {
                'imageUrl': imageUrl,
                'imgbbDeleteHash': deleteHash,
              };
            } else {
              print("Failed to parse ImgBB response: 'url' or 'delete_url' missing in data. Body: ${response.body}");
              return null;
            }
          } else {
            print("Failed to parse ImgBB response: 'success' not true or 'data' missing. Body: ${response.body}");
            return null;
          }
        } catch (e) {
          print("Error decoding ImgBB JSON response: $e. Body: ${response.body}");
          return null;
        }
      } else {
        // Log upload failure
        print("ImgBB upload failed. Status: ${response.statusCode}, Reason: ${response.body}");
        // Optionally show specific error to user based on status code/body
        // if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("فشل رفع الصورة. الرمز: ${response.statusCode}")),
        );
        // }
        return null;
      }
    } catch (e) {
      // Handle network errors or other exceptions during upload
      print("Error uploading to ImgBB: $e");
      // if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("حدث خطأ في الشبكة أثناء رفع الصورة.")),
      );
      // }
      return null;
    }
  }

  Future<void> _deleteOldImgBBImage(String deleteHash) async {
    final String imgbbApiKey = dotenv.env['IMGBB_API_KEY'] ?? '';
    if (imgbbApiKey.isEmpty) {
      print("WARNING: ImgBB API Key not configured securely. Skipping old image deletion.");
      return;
    }
    final url = Uri.parse('https://api.imgbb.com/1/delete?key=$imgbbApiKey&delete_hash=$deleteHash');
    try {
      final response = await http.get(url); // Changed from http.delete(url)
      if (response.statusCode == 200) {
        print("Old ImgBB image deleted successfully. Response: ${response.body}");
      } else {
        print("Failed to delete image from ImgBB ($deleteHash). Status: ${response.statusCode}, Body: ${response.body}");
      }
    } catch (e) {
      print("Error deleting image from ImgBB ($deleteHash): $e");
    }
  }

  Future<void> _saveChanges() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("خطأ: المستخدم غير متوفر لحفظ البيانات.")),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStartDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء تحديد تاريخ البدء.")));
      return;
    }
    if (_selectedFrequency == 'يومي' && _selectedTimes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء إضافة وقت واحد على الأقل للجرعة.")));
      return;
    }
    if (_selectedFrequency == 'اسبوعي' && _selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء اختيار يوم واحد على الأقل وضبط الوقت له.")));
      return;
    }
    setState(() { _isSaving = true; });

    // Preserve existing alarm times unless explicitly updated
    final existingTimes = (medicationDoc?.data() as Map<String, dynamic>?)?['times'] ?? [];
    var timesField = _selectedFrequency == 'اسبوعي'
        ? _selectedWeekdays.toList().map((day) {
            return {
              'day': day,
              'time': _weeklyTimes[day] != null
                  ? TimeUtils.formatTimeOfDay(context, _weeklyTimes[day]!)
                  : ''
            };
          }).toList()
        : (_selectedTimes.isNotEmpty
            ? _selectedTimes.map((time) => TimeUtils.formatTimeOfDay(context, time)).toList()
            : existingTimes); // Use existing times if no changes

    final Map<String, dynamic> updatedData = {
      'name': _nameController.text.trim(),
      'startDate': Timestamp.fromDate(_selectedStartDate!),
      'endDate': _selectedEndDate != null ? Timestamp.fromDate(_selectedEndDate!) : null,
      'times': timesField,
      'frequency': '${_selectedTimes.length} $_selectedFrequency',
      'frequencyType': _selectedFrequency,
      'weeklyDays': _selectedFrequency == 'اسبوعي' ? _selectedWeekdays.toList() : FieldValue.delete(),
      'imageUrl': _currentImageUrl,
      'imgbbDeleteHash': _currentImgbbDeleteHash,
      'missedTime': FieldValue.delete(), // Reset missedTime if modified
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('medicines')
          .doc(widget.docId)
          .update(updatedData);

      // Reschedule notifications only for updated times
      if (_selectedTimes.isNotEmpty || _selectedWeekdays.isNotEmpty) {
        await _rescheduleNotifications(timesField);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم حفظ التغييرات بنجاح"), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    } catch (e) {
      print("Error saving medication changes: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("فشل حفظ التغييرات: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

Future<void> _rescheduleNotifications(List<dynamic> timesField) async {
    await flutterLocalNotificationsPlugin.cancel(widget.docId.hashCode); // Cancel existing notifications
    final now = DateTime.now();
    int notificationId = widget.docId.hashCode;

    for (var timeStr in timesField) {
      final time = TimeUtils.parseTime(timeStr.toString());
      if (time != null) {
        final scheduledTime = DateTime(
          now.year,
          now.month,
          now.day,
          time.hour,
          time.minute,
        );
        if (scheduledTime.isAfter(now)) {
          await flutterLocalNotificationsPlugin.zonedSchedule(
            notificationId++,
            'تذكير الدواء',
            'حان وقت تناول ${_nameController.text.trim()}',
            tz.TZDateTime.from(scheduledTime, tz.local),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'medication_channel',
                'Medication Reminders',
                channelDescription: 'This channel is used for medication reminders.',
                importance: Importance.high,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.time,
          );
        }
      }
    }
  }

  Future<void> rescheduleAllNotifications() async {
    // Fetch all medications from Firestore and reschedule notifications
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final medsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('medicines')
        .get();

    await flutterLocalNotificationsPlugin.cancelAll(); // Clear existing notifications

    int notificationId = 0; // Unique ID for each notification
    final now = DateTime.now();

    for (var doc in medsSnapshot.docs) {
      final data = doc.data();
      final String medicationName = data['name'] ?? 'دواء غير مسمى';
      final List<dynamic> timesRaw = data['times'] ?? [];
      final String frequencyType = data['frequencyType'] ?? 'يومي';

      if (frequencyType == 'يومي') {
        for (var timeStr in timesRaw) {
          final time = add_dose.TimeUtils.parseTime(timeStr.toString());
          if (time != null) {
            final scheduledTime = DateTime(
              now.year,
              now.month,
              now.day,
              time.hour,
              time.minute,
            );
            if (scheduledTime.isAfter(now)) {
              await scheduleNotification(
                id: notificationId++,
                title: 'تذكير الدواء',
                body: 'حان وقت تناول $medicationName',
                scheduledTime: scheduledTime, docId: '',
              );
            }
          }
        }
      }
      // Handle weekly frequency if needed
    }
  }

  // ----------------------
  // Daily Time Picker UI (Card-based, similar to weekly UI)
  // ----------------------
  Widget _buildDailyTimePickerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "أوقات الجرعات اليومية:",
          style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        if (_selectedTimes.isNotEmpty && _selectedTimes[0] != null)
          ElevatedButton(
            onPressed: () {
              setState(() {
                for (int i = 1; i < _selectedTimes.length; i++) {
                  _selectedTimes[i] = _selectedTimes[0];
                  _dailyAutoGenerated[i] = true;
                }
              });
            },
            child: const Text("تطبيق نفس الوقت لجميع الجرعات"),
          ),
        const SizedBox(height: 10),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _selectedTimes.length,
          itemBuilder: (context, index) {
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6.0),
              elevation: 1.0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: Icon(Icons.access_time_filled, color: Colors.blue.shade700),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${index + 1}. ', style: const TextStyle(fontSize: 16)),
                    Text(
                      _selectedTimes[index] == null
                          ? 'اضغط لاختيار الوقت'
                          : TimeUtils.formatTimeOfDay(context, _selectedTimes[index]),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: _selectedTimes[index] == null ? FontWeight.normal : FontWeight.bold,
                        color: _selectedTimes[index] == null ? Colors.grey.shade600 : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (_selectedTimes[index] != null && index > 0)
                      Icon(
                        _dailyAutoGenerated[index] ? Icons.smart_toy : Icons.person,
                        size: 16,
                        color: Colors.grey,
                      ),
                  ],
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final TimeOfDay? picked = await showTimePicker(
                    context: context,
                    initialTime: _selectedTimes[index] ?? TimeOfDay.now(),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedTimes[index] = picked;
                      _dailyAutoGenerated[index] = false;
                    });
                  }
                },
              ),
            );
          },
        ),
        ElevatedButton.icon(
          icon: Icon(Icons.add_alarm, color: Colors.white),
          label: const Text("إضافة جرعة جديدة"),
          onPressed: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
            );
            if (picked != null) {
              setState(() {
                _selectedTimes.add(picked);
                _dailyAutoGenerated.add(false);
              });
            }
          },
        ),
        if (_selectedTimes.any((t) => t == null))
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'الرجاء تحديد جميع أوقات الجرعات المطلوبة.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          ),
      ],
    );
  }

  // ----------------------
  // Weekly Schedule UI (as before)
  // ----------------------
  // Helper to return Arabic name for weekday.
  String _dayName(int day) {
    switch (day) {
      case 1:
        return "الإثنين";
      case 2:
        return "الثلاثاء";
      case 3:
        return "الأربعاء";
      case 4:
        return "الخميس";
      case 5:
        return "الجمعة";
      case 6:
        return "السبت";
      case 7:
        return "الأحد";
      default:
        return "";
    }
  }

  // Ensure weekly maps exist for selected days.
  void _initializeWeeklySchedule() {
    if (_selectedWeekdays.isEmpty && _weeklyTimes.isNotEmpty) {
      _selectedWeekdays = _weeklyTimes.keys.toSet();
    }
    for (int day in _selectedWeekdays) {
      _weeklyAutoGenerated.putIfAbsent(day, () => false);
    }
  }

  Future<void> _selectWeeklyTime(int day) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _weeklyTimes[day] ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _weeklyTimes[day] = picked;
        _weeklyAutoGenerated[day] = false;
        List<int> sortedDays = _selectedWeekdays.toList()..sort();
        if (sortedDays.isNotEmpty && day == sortedDays.first) {
          for (int otherDay in sortedDays.skip(1)) {
            if (_weeklyTimes[otherDay] == null) {
              _weeklyTimes[otherDay] = picked;
              _weeklyAutoGenerated[otherDay] = true;
            }
          }
        }
      });
    }
  }

  Widget _buildWeeklyScheduleSection() {
    _initializeWeeklySchedule();
    List<int> sortedDays = _selectedWeekdays.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "جدول الجرعات الأسبوعي",
          style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          children: List.generate(7, (index) {
            int day = index + 1;
            bool selected = _selectedWeekdays.contains(day);
            return FilterChip(
              label: Text(_dayName(day)),
              selected: selected,
              onSelected: (value) {
                setState(() {
                  if (value) {
                    if (_selectedWeekdays.length < 6) {
                      _selectedWeekdays.add(day);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('يمكنك اختيار 6 أيام فقط')),
                      );
                    }
                  } else {
                    _selectedWeekdays.remove(day);
                    _weeklyTimes.remove(day);
                    _weeklyAutoGenerated.remove(day);
                  }
                });
              },
              selectedColor: Colors.blue.shade300,
              checkmarkColor: Colors.white,
              backgroundColor: Colors.grey.shade200,
            );
          }),
        ),
        if (_selectedWeekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "الرجاء اختيار يوم واحد على الأقل",
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  List<int> sortedDays = _selectedWeekdays.toList()..sort();
                  if (sortedDays.isNotEmpty && _weeklyTimes[sortedDays.first] != null) {
                    setState(() {
                      for (int day in sortedDays.skip(1)) {
                        _weeklyTimes[day] = _weeklyTimes[sortedDays.first]!;
                        _weeklyAutoGenerated[day] = true;
                      }
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("حدد وقت اليوم الأول أولاً")));
                  }
                },
                child: const Text("تطبيق نفس الوقت لجميع الأيام"),
              ),
              const SizedBox(height: 10),
              Column(
                children: sortedDays.map((day) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6.0),
                    elevation: 1.0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: Text(
                        _dayName(day),
                        style: const TextStyle(fontSize: 16),
                      ),
                      title: InkWell(
                        onTap: () async {
                          await _selectWeeklyTime(day);
                        },
                        child: Text(
                          _weeklyTimes[day] == null
                              ? "اضغط لاختيار الوقت"
                              : TimeUtils.formatTimeOfDay(context, _weeklyTimes[day]!),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: _weeklyTimes[day] == null ? Colors.grey.shade600 : Colors.black87,
                          ),
                        ),
                      ),
                      trailing: Icon(
                        _weeklyTimes[day] == null
                            ? Icons.edit_calendar_outlined
                            : ((_weeklyAutoGenerated[day] ?? false)
                            ? Icons.smart_toy
                            : Icons.person),
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildFrequencySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("التكرار:",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: const Text('يومي'),
                value: 'يومي',
                groupValue: _selectedFrequency,
                onChanged: (value) {
                  if (value != null) setState(() {
                    _selectedFrequency = value;
                    if (value == 'يومي') {
                      // Reset daily schedule.
                      _selectedTimes = _selectedTimes.isNotEmpty ? _selectedTimes : [];
                      _dailyAutoGenerated = List<bool>.filled(_selectedTimes.length, false, growable: true);
                    } else {
                      // Reset weekly schedule.
                      _selectedWeekdays = {};
                      _weeklyTimes = {};
                      _weeklyAutoGenerated = {};
                    }
                  });
                },
                activeColor: Colors.blue.shade700,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: const Text('اسبوعي'),
                value: 'اسبوعي',
                groupValue: _selectedFrequency,
                onChanged: (value) {
                  if (value != null) setState(() {
                    _selectedFrequency = value;
                    _selectedWeekdays = {};
                    _weeklyTimes = {};
                    _weeklyAutoGenerated = {};
                  });
                },
                activeColor: Colors.blue.shade700,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImageSection(BuildContext context) {
    Widget imageDisplay;
    if (_newImageFile != null) {
      imageDisplay = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          _newImageFile!,
          height: 150,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else if (!_imageRemoved && _currentImageUrl != null && _currentImageUrl!.isNotEmpty) {
      try {
        imageDisplay = EnlargeableImage(
          key: ValueKey(_currentImageUrl!),
          imageUrl: _currentImageUrl!,
          width: double.infinity,
          height: 150,
        );
      } catch (e) {
        print("EnlargeableImage not available, falling back to Image.network.");
        imageDisplay = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            _currentImageUrl!,
            height: 150,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, st) => _buildImagePlaceholder(context),
            loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : Center(child: CircularProgressIndicator()),
          ),
        );
      }
    } else {
      imageDisplay = _buildImagePlaceholder(context);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("صورة الدواء (اختياري):",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
        const SizedBox(height: 10),
        imageDisplay,
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: Icon(Icons.photo_library_outlined, color: Colors.blue.shade700),
              label: Text("اختر من المعرض", style: TextStyle(color: Colors.blue.shade700)),
              onPressed: () => _getImage(ImageSource.gallery),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
            ),
            TextButton.icon(
              icon: Icon(Icons.camera_alt_outlined, color: Colors.blue.shade700),
              label: Text("التقط صورة", style: TextStyle(color: Colors.blue.shade700)),
              onPressed: () => _getImage(ImageSource.camera),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
            ),
          ],
        ),
        if (((_currentImageUrl != null && _currentImageUrl!.isNotEmpty && !_imageRemoved) || _newImageFile != null))
          Center(
            child: TextButton.icon(
              icon: Icon(Icons.delete_outline, color: Colors.red, size: 20),
              label: Text("إزالة الصورة", style: TextStyle(color: Colors.red)),
              onPressed: _removeImage,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
            ),
          ),
      ],
    );
  }

  Widget _buildImagePlaceholder(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade400),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            color: Colors.grey.shade600, 
            size: 50, // Changed from widget.width * 0.5 to fixed size 50
          ),
          const SizedBox(height: 8),
          Text("لا توجد صورة", style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      "تعديل الدواء",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildForm(),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("اسم الدواء", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: "مثال: بنادول أدفانس",
              border: const OutlineInputBorder(),
              prefixIcon: Icon(Icons.medication_liquid, color: Colors.blue.shade800),
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return "الرجاء إدخال اسم الدواء";
              return null;
            },
          ),
          const SizedBox(height: 24),
          Text("فترة الاستخدام", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildDateButton(context, "تاريخ البدء", true)),
              const SizedBox(width: 12),
              Expanded(child: _buildDateButton(context, "الانتهاء (اختياري)", false)),
            ],
          ),
          if (_selectedEndDate != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => setState(() => _selectedEndDate = null),
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                label: Text("مسح تاريخ الانتهاء", style: TextStyle(color: Colors.red, fontSize: 12)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(height: 24),
          _buildFrequencySection(context),
          const SizedBox(height: 16),
          _selectedFrequency == 'يومي'
              ? _buildDailyTimePickerSection(context)
              : _buildWeeklyScheduleSection(),
          const SizedBox(height: 16),
          const Divider(height: 24),
          _buildImageSection(context),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            icon: _isSaving
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.save_alt_outlined),
            label: Text(_isSaving ? "جارٍ الحفظ..." : "حفظ التغييرات"),
            onPressed: _isSaving ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildDateButton(BuildContext context, String label, bool isStartDate) {
    final DateTime? dateToShow = isStartDate ? _selectedStartDate : _selectedEndDate;
    final String buttonText = dateToShow == null ? label : intl.DateFormat('yyyy/MM/dd', 'ar_SA').format(dateToShow);
    return OutlinedButton.icon(
      icon: Icon(
        isStartDate ? Icons.calendar_today_outlined : Icons.event_available_outlined,
        size: 20,
        color: dateToShow == null ? Colors.grey.shade600 : Colors.blue.shade800,
      ),
      label: Text(buttonText,
          style: TextStyle(
            color: dateToShow == null ? Colors.grey.shade600 : Colors.blue.shade800,
          )),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        side: BorderSide(color: dateToShow == null && isStartDate ? Colors.red : Colors.grey.shade400, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () => _pickDate(context, isStartDate),
    );
  }
}



