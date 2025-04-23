import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

// Import your Edit screen
import 'package:mudhkir_app/pages/EditMedication_Page.dart';
import '../main.dart';
import 'Main_Page.dart';

// --- Theme constants ---
const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const double kBorderRadius = 16.0;
const double kSpacing = 16.0;

// --- Time Utilities ---
class TimeUtils {
  static TimeOfDay? parseTime(dynamic timeInput) {
    // Handle case where input is a Map with 'time' key
    if (timeInput is Map) {
      if (timeInput.containsKey('time')) {
        return parseTime(timeInput['time']);
      }
      print("Failed to parse time from map: $timeInput");
      return null;
    }

    // Now we should have a string
    final String? timeStr = timeInput?.toString();
    if (timeStr == null || timeStr.isEmpty) {
      print("Empty or null time string");
      return null;
    }

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

// --- EnlargeableImage Widget (Styled to match theme) ---
class EnlargeableImage extends StatefulWidget {
  final String imageUrl;
  final double width;
  final double height;
  final String docId;

  const EnlargeableImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.docId,
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
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: animation,
            child: Directionality(
              textDirection: ui.TextDirection.rtl,
              child: Scaffold(
                backgroundColor: Colors.black.withOpacity(0.85),
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  iconTheme: IconThemeData(color: kSecondaryColor),
                  leading: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                body: Center(
                  child: Hero(
                    tag: 'medication_image_${widget.docId}_${widget.imageUrl.hashCode}',
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.file(imageFile),
                    ),
                  ),
                ),
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
              color: kSecondaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(kBorderRadius),
            ),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kPrimaryColor,
                ),
              ),
            ),
          );
        } else if (snapshot.hasData && snapshot.data != null) {
          return Hero(
            tag: 'medication_image_${widget.docId}_${widget.imageUrl.hashCode}',
            child: GestureDetector(
              onTap: () => _openEnlargedImage(context, snapshot.data!),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kBorderRadius),
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
        color: kSecondaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: kSecondaryColor.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            showErrorText ? Icons.broken_image_rounded : Icons.medication_rounded,
            color: kSecondaryColor.withOpacity(0.5),
            size: widget.width * 0.4,
          ),
          if (showErrorText) const SizedBox(height: 4),
          if (showErrorText)
            Text(
              "لا توجد صورة",
              style: TextStyle(
                fontSize: 10,
                color: kSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

// --- DoseSchedule Main Widget ---
class DoseSchedule extends StatefulWidget {
  const DoseSchedule({super.key});

  @override
  _DoseScheduleState createState() => _DoseScheduleState();
}

class _DoseScheduleState extends State<DoseSchedule> {
  User? _user;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<Map<String, dynamic>>> _doses = {};
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user == null) {
      print("Error: User not logged in for DoseSchedule.");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("الرجاء تسجيل الدخول أولاً لعرض الجدول"),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(10),
            ),
          );
        }
      });
      setState(() => _isLoading = false);
    } else {
      _fetchDoses();
    }
  }

  Future<void> _fetchDoses() async {
    if (!mounted || _user == null) return;
    setState(() {
      _isLoading = true;
    });

    final Map<DateTime, List<Map<String, dynamic>>> newDoses = {};
    final String userId = _user!.uid;

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

        if (startTimestamp == null) {
          print('Document ${doc.id} missing start date. Skipping.');
          continue;
        }

        final String frequencyRaw = data['frequency'] as String? ?? '1 يومي';
        final List<String> frequencyParts = frequencyRaw.split(" ");
        final String frequencyType = frequencyParts.length > 1 ? frequencyParts[1] : 'يومي';

        final String resolvedFrequencyType = frequencyType;
        print('Processing medication ${doc.id}: $medicationName, frequency type: $resolvedFrequencyType');

        final List<dynamic> timesRaw = data['times'] ?? [];
        final String imageUrl = data['imageUrl'] as String? ?? '';
        final String imgbbDeleteHash = data['imgbbDeleteHash'] as String? ?? '';

        if (resolvedFrequencyType == 'اسبوعي') {
          print('Weekly medication found: $medicationName');
          print('Times raw data: $timesRaw');
        }

        final DateTime startDate = startTimestamp.toDate();
        final DateTime? endDate = endTimestamp?.toDate();

        DateTime currentDate = startDate;
        while (endDate == null || !currentDate.isAfter(endDate)) {
          final DateTime normalizedDate = DateTime(currentDate.year, currentDate.month, currentDate.day);
          bool shouldAddDoseToday = false;
          List<TimeOfDay> timesParsed = [];

          if (resolvedFrequencyType == 'يومي') {
            // Daily medication - parse all time entries for each day
            timesParsed = timesRaw
                .map((t) => TimeUtils.parseTime(t))
                .whereType<TimeOfDay>()
                .toList();
            shouldAddDoseToday = timesParsed.isNotEmpty;
          } else if (resolvedFrequencyType == 'اسبوعي') {
            print('Processing weekly medication for ${currentDate.toIso8601String()}, weekday: ${currentDate.weekday}');

            // Process weekly medication times
            timesParsed = [];
            for (var item in timesRaw) {
              print('Processing weekly item type: ${item.runtimeType}, value: $item');

              if (item is Map) {
                // Extract day and time values considering different possible structures
                int dayValue = -1;
                dynamic timeValue;

                // Handle direct map format or nested format
                if (item.containsKey('day')) {
                  var day = item['day'];
                  if (day is int) dayValue = day;
                  else if (day is String) dayValue = int.tryParse(day) ?? -1;
                  else if (day is double) dayValue = day.toInt();

                  timeValue = item['time'];
                }

                // Handle case where item itself has nested 'time' object with 'day' inside
                if (item.containsKey('time') && item['time'] is Map) {
                  var nestedTime = item['time'] as Map;
                  if (nestedTime.containsKey('day')) {
                    var day = nestedTime['day'];
                    if (day is int) dayValue = day;
                    else if (day is String) dayValue = int.tryParse(day) ?? -1;
                    else if (day is double) dayValue = day.toInt();
                  }
                  timeValue = nestedTime['time'];
                }

                print('Weekly item: day=$dayValue, current weekday=${currentDate.weekday}, time=$timeValue');

                if (dayValue == currentDate.weekday) {
                  final parsedTime = TimeUtils.parseTime(timeValue);
                  if (parsedTime != null) {
                    timesParsed.add(parsedTime);
                    print('Added weekly time: $parsedTime for day $dayValue');
                  }
                }
              } else if (item is String) {
                final parts = item.split(':');
                if (parts.length >= 2) {
                  final dayPart = int.tryParse(parts[0]);
                  if (dayPart == currentDate.weekday) {
                    final timePart = parts.sublist(1).join(':');
                    final parsedTime = TimeUtils.parseTime(timePart);
                    if (parsedTime != null) {
                      timesParsed.add(parsedTime);
                      print('Added legacy weekly time: $parsedTime for day $dayPart');
                    }
                  }
                }
              }
            }
            shouldAddDoseToday = timesParsed.isNotEmpty;
            if (shouldAddDoseToday) {
              print('Added weekly dose for ${currentDate.toIso8601String()} with ${timesParsed.length} times');
            }
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
          return (a['medicationName'] as String).compareTo(b['medicationName'] as String);
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
          SnackBar(
            content: const Text("حدث خطأ أثناء تحميل جدول الأدوية."),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final DateTime normalizedDay = DateTime(day.year, day.month, day.day);
    return _doses[normalizedDay] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading && _user == null) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor.withOpacity(0.2),
                kBackgroundColor,
                Colors.white,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.login_rounded, size: 60, color: kPrimaryColor.withOpacity(0.7)),
                const SizedBox(height: 20),
                Text(
                  "الرجاء تسجيل الدخول لعرض الجدول",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: kPrimaryColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text("العودة"),
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            "جدول الأدوية",
            style: TextStyle(
              color: kPrimaryColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: Colors.white.withOpacity(0.7),
                  blurRadius: 15,
                )
              ],
            ),
          ),
          centerTitle: true,
          iconTheme: IconThemeData(
            color: kPrimaryColor,
            size: 28,
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor.withOpacity(0.2),
                kBackgroundColor,
                Colors.white,
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: _isLoading
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: kPrimaryColor),
                  const SizedBox(height: 16),
                  Text(
                    "جاري تحميل الجدول...",
                    style: TextStyle(
                      color: kPrimaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: _fetchDoses,
              color: kPrimaryColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(kSpacing),
                  child: Column(
                    children: [
                      // Calendar Card with shadow and rounded corners
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          boxShadow: [
                            BoxShadow(
                              color: kPrimaryColor.withOpacity(0.1),
                              blurRadius: 10,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          child: TableCalendar<Map<String, dynamic>>(
                            locale: 'ar_SA',
                            firstDay: DateTime.utc(DateTime.now().year - 1, 1, 1),
                            lastDay: DateTime.utc(DateTime.now().year + 2, 12, 31),
                            focusedDay: _focusedDay,
                            calendarFormat: _calendarFormat,
                            eventLoader: _getEventsForDay,
                            selectedDayPredicate: (day) =>
                                isSameDay(_selectedDay, day),
                            onDaySelected: (selectedDay, focusedDay) {
                              if (!isSameDay(_selectedDay, selectedDay)) {
                                setState(() {
                                  _selectedDay = selectedDay;
                                  _focusedDay = focusedDay;
                                });
                              }
                            },
                            onFormatChanged: (format) {
                              if (_calendarFormat != format) {
                                setState(() => _calendarFormat = format);
                              }
                            },
                            onPageChanged: (focusedDay) {
                              _focusedDay = focusedDay;
                            },
                            availableCalendarFormats: const {
                              CalendarFormat.month: 'اسبوع',
                              CalendarFormat.week: 'شهر',
                            },

                            // Styled Calendar Header
                            headerStyle: HeaderStyle(
                              titleCentered: true,
                              formatButtonVisible: true,
                              formatButtonDecoration: BoxDecoration(
                                color: kSecondaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              formatButtonTextStyle: TextStyle(
                                color: kPrimaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                              titleTextStyle: TextStyle(
                                color: kPrimaryColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              leftChevronIcon: Icon(Icons.chevron_left, color: kPrimaryColor),
                              rightChevronIcon: Icon(Icons.chevron_right, color: kPrimaryColor),
                              headerPadding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  bottom: BorderSide(
                                    color: kSecondaryColor.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),

                            // Styled Calendar Days
                            daysOfWeekStyle: DaysOfWeekStyle(
                              weekdayStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              weekendStyle: TextStyle(
                                color: Colors.red.shade300,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: BoxDecoration(
                                color: kSecondaryColor.withOpacity(0.05),
                              ),
                            ),

                            // Styled Calendar
                            calendarStyle: CalendarStyle(
                              outsideDaysVisible: false,
                              defaultDecoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.transparent,
                              ),
                              weekendDecoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.transparent,
                              ),
                              todayDecoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: kPrimaryColor,
                              ),
                              selectedDecoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: kSecondaryColor,
                              ),
                              markerDecoration: BoxDecoration(
                                color: Colors.orange.shade400,
                                shape: BoxShape.circle,
                              ),
                              markerSize: 5,
                              markersMaxCount: 3,
                              cellMargin: const EdgeInsets.all(6),
                              todayTextStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              selectedTextStyle: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            // Custom builders for more control
                            calendarBuilders: CalendarBuilders(
                              markerBuilder: (context, date, events) {
                                if (events.isEmpty) return const SizedBox();

                                return Positioned(
                                  bottom: 1,
                                  child: Container(
                                    width: events.length > 2 ? 16 : 12,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: events.any((e) => e['isImportant'] == true)
                                          ? Colors.orange.shade400
                                          : kSecondaryColor,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                );
                              },

                              // Add subtle fills to days with events
                              defaultBuilder: (context, day, focusedDay) {
                                final events = _getEventsForDay(day);
                                if (events.isNotEmpty) {
                                  return Container(
                                    margin: const EdgeInsets.all(5),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: kSecondaryColor.withOpacity(0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        color: kPrimaryColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }
                                return null;
                              },
                            ),
                          ),
                        ),
                      ),

                      // Date display with styled container
                      Container(
                        margin: const EdgeInsets.only(top: 24, bottom: 12),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.event_note_rounded,
                              size: 20,
                              color: kPrimaryColor,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('EEEE, d MMMM yyyy', 'ar_SA').format(_selectedDay),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Dose list with improved spacing
                      _buildDoseList(),

                      // Add bottom padding for scrolling
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoseList() {
    final events = _getEventsForDay(_selectedDay);

    if (events.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kSecondaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.medication_liquid_outlined,
                size: 48,
                color: kSecondaryColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "لا توجد جرعات لهذا اليوم",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: kPrimaryColor.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "أضف دواءً جديدًا باستخدام زر الإضافة",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (int index = 0; index < events.length; index++) ...[
          DoseTile(
            key: ValueKey('${events[index]['docId']}_${events[index]['timeString']}'),
            medicationName: events[index]['medicationName'],
            nextDose: events[index]['timeString'],
            docId: events[index]['docId'],
            imageUrl: events[index]['imageUrl'],
            imgbbDeleteHash: events[index]['imgbbDeleteHash'],
            onDataChanged: _fetchDoses,
          ),
          if (index < events.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

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

class _DoseTileState extends State<DoseTile> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  String _doseStatus = 'pending';
  bool _isLoadingStatus = true;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _checkDoseStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DoseTile oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      final selectedDay = context.findAncestorStateOfType<_DoseScheduleState>()?._selectedDay ?? DateTime.now();
      final normalizedSelectedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);

      final doseTime = TimeUtils.parseTime(widget.nextDose);
      if (doseTime == null) {
        if (mounted) setState(() => _isLoadingStatus = false);
        return;
      }

      String currentStatus = 'pending';
      for (var dose in missedDoses) {
        if (dose is Map<String, dynamic> && dose.containsKey('scheduled') && dose.containsKey('status')) {
          final scheduledTimestamp = dose['scheduled'] as Timestamp?;
          if (scheduledTimestamp != null) {
            final scheduledDate = scheduledTimestamp.toDate();
            final normalizedScheduledDate = DateTime(scheduledDate.year, scheduledDate.month, scheduledDate.day);

            if (scheduledDate.hour == doseTime.hour &&
                scheduledDate.minute == doseTime.minute &&
                isSameDay(normalizedScheduledDate, normalizedSelectedDay)) {
              currentStatus = dose['status'] as String? ?? 'pending';
              break;
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
          _isLoadingStatus = false;
          _doseStatus = 'pending';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("خطأ في تحديث حالة الجرعة."),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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

    setState(() => _isLoadingStatus = true);

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
          missedDoses[foundIndex]['status'] = newStatus;
          missedDoses[foundIndex]['updatedAt'] = Timestamp.now();
        } else {
          missedDoses.add({
            'scheduled': targetTimestamp,
            'status': newStatus,
            'createdAt': Timestamp.now(),
          });
        }

        transaction.update(docRef, {
          'missedDoses': missedDoses,
          'lastUpdated': Timestamp.now(),
        });
      });

      if (mounted) {
        setState(() {
          _doseStatus = newStatus;
          _isLoadingStatus = false;
        });
        widget.onDataChanged();

        if (newStatus == 'taken') {
          final notificationId = widget.docId.hashCode + doseTime.hour * 100 + doseTime.minute;
          debugPrint("Rescheduling notification skipped (notification system removed).");
        }
      }

    } catch (e) {
      print('Error toggling dose status: $e');
      if (mounted) {
        setState(() {
          _isLoadingStatus = false;
          _checkDoseStatus();
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("فشل تحديث حالة الجرعة: $e"),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ));
        });
      }
    }
  }

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.right,
        ),
        content: Text(
          content,
          style: const TextStyle(color: Colors.black87),
          textAlign: TextAlign.right,
        ),
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

  Future<void> _handleEdit(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "تعديل الدواء",
      content: "هل تريد الانتقال إلى شاشة تعديل بيانات هذا الدواء؟",
      confirmText: "نعم، تعديل",
      confirmButtonColor: Colors.blue.shade700,
    );

    if (confirmed == true && mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditMedicationScreen(docId: widget.docId),
        ),
      );
      widget.onDataChanged();
    }
  }

  Future<void> _handleFinishMed(BuildContext context) async {
    // Get the selected day from the parent DoseSchedule widget
    final _DoseScheduleState? parentState = context.findAncestorStateOfType<_DoseScheduleState>();
    final DateTime selectedDay = parentState?._selectedDay ?? DateTime.now();

    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "إنهاء الدواء",
      content: "هل أنت متأكد من إنهاء جدول هذا الدواء؟ سيتم تحديد تاريخ الانتهاء إلى ${DateFormat('EEEE, d MMMM yyyy', 'ar_SA').format(selectedDay)} ولن يظهر في الأيام التالية.",
      confirmText: "نعم، إنهاء",
      confirmButtonColor: Colors.orange.shade700,
    );

    if (confirmed == true) {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("خطأ: المستخدم غير مسجل."),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
        return;
      }

      if (user != null) {
        try {
          // Create timestamp at end of selected day (23:59:59)
          final DateTime endOfSelectedDay = DateTime(
            selectedDay.year,
            selectedDay.month,
            selectedDay.day,
            23,
            59,
            59,
          );

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('medicines')
              .doc(widget.docId)
              .update({'endDate': Timestamp.fromDate(endOfSelectedDay)});

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("تم إنهاء الدواء بتاريخ ${DateFormat('d MMMM', 'ar_SA').format(selectedDay)}"),
                backgroundColor: Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
            widget.onDataChanged();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("فشل إنهاء الدواء: $e"),
                  backgroundColor: Colors.red.shade700,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ));
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
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("خطأ: المستخدم غير مسجل."),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
      return;
    }

    if (user != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: kPrimaryColor),
                const SizedBox(height: 16),
                const Text("جاري حذف الدواء..."),
              ],
            ),
          ),
        ),
      );

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
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("تم حذف الدواء بنجاح"),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          widget.onDataChanged();
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("فشل حذف الدواء: $e"),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ));
        }
      }
    }
  }

  Future<void> _deleteImgBBImage(String deleteHash) async {
    const String imgbbApiKey = 'YOUR_IMGBB_API_KEY';

    if (imgbbApiKey == 'YOUR_IMGBB_API_KEY' || imgbbApiKey.isEmpty) {
      print("WARNING: ImgBB API Key not configured. Skipping image deletion.");
      return;
    }

    final url = Uri.parse('https://api.imgbb.com/1/image/$deleteHash');

    try {
      final response = await http.post(
        url,
        body: {'key': imgbbApiKey, 'action': 'delete'},
      );

      if (response.statusCode == 200) {
        print("ImgBB image deletion successful: $deleteHash");
      } else {
        print("Failed to delete ImgBB image: ${response.statusCode}, ${response.body}");
      }
    } catch (e) {
      print("Error deleting ImgBB image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Toggle animation when expansion state changes
    if (_isExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }

    return Card(
      elevation: 2,
      shadowColor: kPrimaryColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kBorderRadius),
        side: BorderSide(
          color: _doseStatus == 'taken'
              ? Colors.green.shade300.withOpacity(0.5)
              : kSecondaryColor.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kBorderRadius),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        splashColor: kPrimaryColor.withOpacity(0.05),
        highlightColor: kPrimaryColor.withOpacity(0.05),
        child: Column(
          children: [
            // Main tile content
            Container(
              decoration: BoxDecoration(
                color: _doseStatus == 'taken'
                    ? Colors.green.shade50.withOpacity(0.3)
                    : Colors.transparent,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(kBorderRadius),
                  bottom: _isExpanded ? Radius.zero : Radius.circular(kBorderRadius),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Left: Dose Status Indicator
                  _isLoadingStatus
                      ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimaryColor,
                    ),
                  )
                      : IconButton(
                    icon: Icon(
                      _doseStatus == 'taken'
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 28,
                      color: _doseStatus == 'taken'
                          ? Colors.green.shade600
                          : Colors.grey.shade400,
                    ),
                    onPressed: _toggleDoseStatus,
                    padding: EdgeInsets.zero,
                    tooltip: _doseStatus == 'taken' ? "تم أخذ الجرعة" : "لم تؤخذ الجرعة بعد",
                  ),
                  const SizedBox(width: 12),

                  // Middle: Medication Image
                  EnlargeableImage(
                    imageUrl: widget.imageUrl,
                    width: 50,
                    height: 50,
                    docId: widget.docId,
                  ),
                  const SizedBox(width: 12),

                  // Right: Medication Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.medicationName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: kSecondaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.nextDose,
                              style: TextStyle(
                                fontSize: 14,
                                color: kSecondaryColor,
                              ),
                            ),
                            if (_doseStatus == 'taken')
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "تم",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Expand/Collapse Icon
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5)
                        .animate(_animationController),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: kPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),

            // Expandable actions section
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: Container(
                decoration: BoxDecoration(
                  color: kSecondaryColor.withOpacity(0.05),
                  border: Border(
                    top: BorderSide(
                      color: kSecondaryColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(kBorderRadius),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      label: "تعديل",
                      icon: Icons.edit_rounded,
                      color: kPrimaryColor,
                      onPressed: () => _handleEdit(context),
                    ),
                    _buildActionButton(
                      label: "إنهاء",
                      icon: Icons.event_busy_rounded,
                      color: Colors.orange.shade700,
                      onPressed: () => _handleFinishMed(context),
                    ),
                    _buildActionButton(
                      label: "حذف",
                      icon: Icons.delete_rounded,
                      color: Colors.red.shade700,
                      onPressed: () => _handleDelete(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 18),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
