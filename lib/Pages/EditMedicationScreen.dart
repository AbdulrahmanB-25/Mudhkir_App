import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';



//TODO: FIX HERE THE WEEKYL

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
      String normalizedTime = timeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('مساءً', 'PM')
          .trim();
      final intl.DateFormat arabicAmpmFormat = intl.DateFormat('h:mm a', 'en_US');
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

// ==================================================================
// DoseSchedule Widget
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
        while (endDateDt == null || !currentDate.isAfter(endDateDt)) {
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
// EditMedicationScreen Widget
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
  List<TimeOfDay> _selectedTimes = [];
  String _selectedFrequency = 'يومي';
  Set<int> _selectedWeekdays = {};
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
        final data = docSnapshot.data()!;
        _nameController.text = data['name'] as String? ?? '';
        _selectedStartDate = (data['startDate'] as Timestamp?)?.toDate();
        _selectedEndDate = (data['endDate'] as Timestamp?)?.toDate();
        _selectedFrequency = data['frequencyType'] as String? ?? 'يومي';
        // For weekly, expect times to be a list of maps, and for daily, expect a list of strings
        if (_selectedFrequency == 'اسبوعي') {
          _selectedTimes = (data['times'] as List<dynamic>? ?? [])
              .whereType<Map>()
              .map((m) => TimeUtils.parseTime(m['time'].toString()))
              .whereType<TimeOfDay>()
              .toList();
          _selectedWeekdays = (data['weeklyDays'] as List<dynamic>? ?? [])
              .whereType<int>()
              .toSet();
        } else {
          var rawTimes = data['times'];
          if (rawTimes is List<dynamic> && rawTimes.isNotEmpty) {
            if (rawTimes.first is Map) {
              // If stored as maps mistakenly
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
  Future<void> _pickTime(BuildContext context) async {
    final initialTime = TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: child!,
          ),
        );
      },
    );
    if (pickedTime != null) {
      if (!_selectedTimes.any((t) => t.hour == pickedTime.hour && t.minute == pickedTime.minute)) {
        setState(() {
          _selectedTimes.add(pickedTime);
          _selectedTimes.sort((a, b) {
            if (a.hour != b.hour) return a.hour.compareTo(b.hour);
            return a.minute.compareTo(b.minute);
          });
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("هذا الوقت تم اختياره بالفعل.")),
        );
      }
    }
  }
  void _removeTime(int index) {
    setState(() {
      _selectedTimes.removeAt(index);
    });
  }
  Future<void> _getImage(ImageSource source) async {
    try {
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
  Future<Map<String, String>?> _uploadImageToImgBB(File imageFile) async {
    const String imgbbApiKey = '2b30d3479663bc30a70c916363b07c4a';
    if (imgbbApiKey == '2b30d3479663bc30a70c916363b07c4a' || imgbbApiKey.isEmpty) {
      print("ERROR: ImgBB API Key not configured securely.");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("خطأ في إعدادات رفع الصور.")));
      return null;
    }
    final url = Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbApiKey');
    try {
      var request = http.MultipartRequest('POST', url);
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      var response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final RegExp imageUrlRegExp = RegExp(r'"url":"(.*?)"');
        final RegExp deleteUrlRegExp = RegExp(r'"delete_url":"(.*?)"');
        final imageUrlMatch = imageUrlRegExp.firstMatch(responseData);
        final deleteUrlMatch = deleteUrlRegExp.firstMatch(responseData);
        if (imageUrlMatch?.group(1) != null && deleteUrlMatch?.group(1) != null) {
          final deleteUrl = deleteUrlMatch!.group(1)!;
          final deleteHash = deleteUrl.split('/').last;
          return {
            'imageUrl': imageUrlMatch!.group(1)!,
            'imgbbDeleteHash': deleteHash
          };
        } else {
          print("Failed to parse ImgBB response: $responseData");
          return null;
        }
      } else {
        print("ImgBB upload failed. Status: ${response.statusCode}, Reason: ${await response.stream.bytesToString()}");
      }
    } catch (e) {
      print("Error uploading to ImgBB: $e");
    }
    return null;
  }
  Future<void> _deleteOldImgBBImage(String deleteHash) async {
    if (deleteHash.isEmpty) return;
    const String imgbbApiKey = 'YOUR_IMGBB_API_KEY';
    if (imgbbApiKey == 'YOUR_IMGBB_API_KEY' || imgbbApiKey.isEmpty) {
      print("WARNING: ImgBB API Key not configured securely. Skipping old image deletion.");
      return;
    }
    final url = Uri.parse('https://api.imgbb.com/1/image/$deleteHash?key=$imgbbApiKey');
    try {
      final response = await http.delete(url);
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
    if (_selectedTimes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء إضافة وقت واحد على الأقل للجرعة.")));
      return;
    }
    if (_selectedFrequency == 'اسبوعي' && _selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء تحديد يوم واحد على الأقل في الأسبوع.")));
      return;
    }
    setState(() { _isSaving = true; });
    String? finalImageUrl = _currentImageUrl;
    String? finalDeleteHash = _currentImgbbDeleteHash;
    bool deleteOldImage = false;
    if (_newImageFile != null) {
      final uploadResult = await _uploadImageToImgBB(_newImageFile!);
      if (uploadResult != null) {
        finalImageUrl = uploadResult['imageUrl'];
        finalDeleteHash = uploadResult['imgbbDeleteHash'];
        deleteOldImage = _currentImgbbDeleteHash != null && _currentImgbbDeleteHash!.isNotEmpty;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("فشل رفع الصورة الجديدة. لم يتم حفظ التغييرات.")));
        setState(() { _isSaving = false; });
        return;
      }
    } else if (_imageRemoved) {
      deleteOldImage = _currentImgbbDeleteHash != null && _currentImgbbDeleteHash!.isNotEmpty;
      finalImageUrl = null;
      finalDeleteHash = null;
    }
    if (deleteOldImage) {
      await _deleteOldImgBBImage(_currentImgbbDeleteHash!);
    }
    var timesField;
    if (_selectedFrequency == 'اسبوعي') {
      timesField = _selectedWeekdays.map((day) {
        return {'day': day, 'time': _selectedTimes.isNotEmpty ? TimeUtils.formatTimeOfDay(context, _selectedTimes.first) : ''};
      }).toList();
    } else {
      timesField = _selectedTimes.map((time) => TimeUtils.formatTimeOfDay(context, time)).toList();
    }
    final Map<String, dynamic> updatedData = {
      'name': _nameController.text.trim(),
      'startDate': Timestamp.fromDate(_selectedStartDate!),
      'endDate': _selectedEndDate != null ? Timestamp.fromDate(_selectedEndDate!) : null,
      'times': timesField,
      'frequencyType': _selectedFrequency,
      'weeklyDays': _selectedFrequency == 'اسبوعي' ? _selectedWeekdays.toList() : FieldValue.delete(),
      'imageUrl': finalImageUrl,
      'imgbbDeleteHash': finalDeleteHash,
    };
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('medicines')
          .doc(widget.docId)
          .update(updatedData);
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
      setState(() { _isSaving = false; });
    }
  }
  @override
  Widget build(BuildContext context) {
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
          _buildTimePickerSection(context),
          const SizedBox(height: 16),
          const Divider(height: 24),
          _buildFrequencySection(context),
          const SizedBox(height: 16),
          if (_selectedFrequency == 'اسبوعي') ...[
            _buildWeekdaySelector(context),
            const SizedBox(height: 16),
          ],
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
  Widget _buildTimePickerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("أوقات الجرعات:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
            IconButton(
              icon: Icon(Icons.add_alarm, color: Colors.blue.shade700),
              tooltip: "إضافة وقت",
              onPressed: () => _pickTime(context),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_selectedTimes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text("الرجاء إضافة وقت واحد على الأقل",
                style: TextStyle(fontSize: 12, color: Colors.red)),
          )
        else
          Wrap(
            spacing: 8.0,
            runSpacing: 6.0,
            children: List<Widget>.generate(_selectedTimes.length, (index) {
              return Chip(
                label: Text(TimeUtils.formatTimeOfDay(context, _selectedTimes[index])),
                onDeleted: () => _removeTime(index),
                deleteIcon: Icon(Icons.cancel_outlined, size: 18, color: Colors.blue.shade700.withAlpha(180)),
                backgroundColor: Colors.blue.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                side: BorderSide(color: Colors.blue.shade700.withAlpha(100)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              );
            }),
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
                  if (value != null) setState(() => _selectedFrequency = value);
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
                  if (value != null) setState(() => _selectedFrequency = value);
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
  Widget _buildWeekdaySelector(BuildContext context) {
    const Map<int, String> weekdaysArabic = {
      1: 'الإثنين',
      2: 'الثلاثاء',
      3: 'الاربعاء',
      4: 'الخميس',
      5: 'الجمعة',
      6: 'السبت',
      7: 'الأحد',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("أيام الأسبوع:",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: List<Widget>.generate(7, (index) {
            final day = index + 1;
            final isSelected = _selectedWeekdays.contains(day);
            return FilterChip(
              label: Text(weekdaysArabic[day]!),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected)
                    _selectedWeekdays.add(day);
                  else
                    _selectedWeekdays.remove(day);
                });
              },
              selectedColor: Colors.blue.shade300,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(fontSize: 14, color: isSelected ? Colors.white : Colors.black87),
              backgroundColor: Colors.grey.shade200,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300),
              ),
            );
          }),
        ),
        if (_selectedFrequency == 'اسبوعي' && _selectedWeekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6.0, left: 8.0),
            child: Text("الرجاء تحديد يوم واحد على الأقل",
                style: TextStyle(fontSize: 12, color: Colors.red)),
          )
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
          Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade600, size: 50),
          const SizedBox(height: 8),
          Text("لا توجد صورة", style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}
