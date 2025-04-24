import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:ui' as ui;

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const double kBorderRadius = 16.0;
const double kSpacing = 16.0;

class CompanionDetailPage extends StatefulWidget {
  final String email;
  final String name;

  const CompanionDetailPage({super.key, required this.email, required this.name});

  @override
  _CompanionDetailPageState createState() => _CompanionDetailPageState();
}

class _CompanionDetailPageState extends State<CompanionDetailPage> {
  String? companionUid;
  bool isLoading = true;
  Map<DateTime, List<Map<String, dynamic>>> _doses = {};
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  void initState() {
    super.initState();
    _loadCompanionData();
  }

  Future<void> _loadCompanionData() async {
    setState(() => isLoading = true);

    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        companionUid = query.docs.first.id;
        await _fetchDoses();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("لم يتم العثور على المرافق"),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              margin: const EdgeInsets.all(10),
            ),
          );
        }
      }
    } catch (e) {
      print("Error loading companion data: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("حدث خطأ أثناء تحميل البيانات: ${e.toString()}"),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchDoses() async {
    if (companionUid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(companionUid)
        .collection('medicines')
        .get();

    final Map<DateTime, List<Map<String, dynamic>>> newDoses = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final name = data['name'] ?? 'بدون اسم';
      final dosage = data['dosage'] as String? ?? '';
      final times = (data['times'] as List?) ?? [];
      final missedDoses = (data['missedDoses'] as List?) ?? [];
      final start = (data['startDate'] as Timestamp?)?.toDate();
      final end = (data['endDate'] as Timestamp?)?.toDate();

      // Determine frequency type
      String frequencyType = 'يومي';
      if (data.containsKey('frequencyType') && data['frequencyType'] == 'اسبوعي') {
        frequencyType = 'اسبوعي';
      } else if (data.containsKey('frequency')) {
        final String frequencyRaw = data['frequency'] as String? ?? '';
        final List<String> frequencyParts = frequencyRaw.split(" ");
        if (frequencyParts.length > 1 && frequencyParts[1] == 'اسبوعي') {
          frequencyType = 'اسبوعي';
        }
      }

      if (start == null) continue;

      DateTime current = start;
      while (end == null || !current.isAfter(end)) {
        final normalized = DateTime(current.year, current.month, current.day);

        if (frequencyType == 'يومي') {
          // Handle daily medication
          for (var timeValue in times) {
            String timeStr;
            if (timeValue is String) {
              timeStr = timeValue;
            } else if (timeValue is Map && timeValue.containsKey('time')) {
              timeStr = timeValue['time'].toString();
            } else {
              continue; // Skip invalid time format
            }

            final isTaken = _isDoseTaken(missedDoses, current, timeStr);
            newDoses.putIfAbsent(normalized, () => []);
            newDoses[normalized]!.add({
              'medication': name,
              'dosage': dosage,
              'time': timeStr,
              'isTaken': isTaken,
              'docId': doc.id,
            });
          }
        } else if (frequencyType == 'اسبوعي') {
          // Handle weekly medication
          for (var item in times) {
            if (item is Map && item.containsKey('day') && item.containsKey('time')) {
              int? dayValue;
              if (item['day'] is int) {
                dayValue = item['day'];
              } else if (item['day'] is String) {
                dayValue = int.tryParse(item['day']);
              } else if (item['day'] is double) {
                dayValue = (item['day'] as double).toInt();
              }

              if (dayValue == current.weekday) {
                String timeStr = item['time'].toString();
                final isTaken = _isDoseTaken(missedDoses, current, timeStr);
                newDoses.putIfAbsent(normalized, () => []);
                newDoses[normalized]!.add({
                  'medication': name,
                  'dosage': dosage,
                  'time': timeStr,
                  'isTaken': isTaken,
                  'docId': doc.id,
                });
              }
            }
          }
        }

        current = current.add(const Duration(days: 1));
        if (end != null && current.isAfter(end)) break;
        if (end == null && current.difference(start).inDays > 365 * 5) break; // 5-year safety limit
      }
    }

    // Sort doses by time
    newDoses.forEach((date, doseList) {
      doseList.sort((a, b) {
        final timeA = _parseTime(a['time'].toString());
        final timeB = _parseTime(b['time'].toString());
        if (timeA == null || timeB == null) return 0;
        if (timeA.hour != timeB.hour) return timeA.hour.compareTo(timeB.hour);
        return timeA.minute.compareTo(timeB.minute);
      });
    });

    if (mounted) {
      setState(() => _doses = newDoses);
    }
  }

  bool _isDoseTaken(List missedDoses, DateTime date, String timeStr) {
    final TimeOfDay? doseTime = _parseTime(timeStr);
    if (doseTime == null) return false;

    final dateNormalized = DateTime(date.year, date.month, date.day);

    for (var dose in missedDoses) {
      if (dose is Map<String, dynamic>) {
        final scheduled = dose['scheduled'] as Timestamp?;
        final status = dose['status'] as String?;

        if (scheduled != null && status == 'taken') {
          final scheduledDateTime = scheduled.toDate();
          final scheduledDate = DateTime(scheduledDateTime.year, scheduledDateTime.month, scheduledDateTime.day);

          if (scheduledDate.isAtSameMomentAs(dateNormalized) &&
              scheduledDateTime.hour == doseTime.hour &&
              scheduledDateTime.minute == doseTime.minute) {
            return true;
          }
        }
      }
    }
    return false;
  }

  TimeOfDay? _parseTime(String timeStr) {
    try {
      String normalizedTime = timeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('مساءً', 'PM')
          .trim();
      final DateFormat format = DateFormat('h:mm a', 'en_US');
      final date = format.parse(normalizedTime);
      return TimeOfDay.fromDateTime(date);
    } catch (e) {
      try {
        final parts = timeStr.split(':');
        if(parts.length >= 2) {
          int hour = int.parse(parts[0]);
          int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
          if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
            return TimeOfDay(hour: hour, minute: minute);
          }
        }
      } catch (_) {}
      print("Time parsing failed: $timeStr");
      return null;
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat.jm('ar').format(dt);
  }

  List<Map<String, dynamic>> _getDosesForDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    return _doses[normalized] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(
            "جدول ${widget.name}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              shadows: [Shadow(color: Colors.white, blurRadius: 15)],
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: kPrimaryColor),
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
            child: isLoading
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: kPrimaryColor),
                  const SizedBox(height: 16),
                  Text(
                    "جاري تحميل جدول الأدوية...",
                    style: TextStyle(
                      color: kPrimaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
                : Padding(
              padding: const EdgeInsets.all(kSpacing),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryColor.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      child: TableCalendar(
                        locale: 'ar_SA',
                        firstDay: DateTime.utc(DateTime.now().year - 1, 1, 1),
                        lastDay: DateTime.utc(DateTime.now().year + 1, 12, 31),
                        focusedDay: _focusedDay,
                        calendarFormat: _calendarFormat,
                        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                        eventLoader: _getDosesForDay,
                        onDaySelected: (selected, focused) {
                          setState(() {
                            _selectedDay = selected;
                            _focusedDay = focused;
                          });
                        },
                        onFormatChanged: (format) {
                          setState(() => _calendarFormat = format);
                        },
                        onPageChanged: (focusedDay) {
                          _focusedDay = focusedDay;
                        },
                        availableCalendarFormats: const {
                          CalendarFormat.month: 'شهر',
                          CalendarFormat.week: 'اسبوع',
                        },
                        headerStyle: HeaderStyle(
                          formatButtonVisible: true,
                          titleCentered: true,
                          formatButtonDecoration: BoxDecoration(
                            color: kSecondaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          formatButtonTextStyle: const TextStyle(
                            color: kPrimaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                          titleTextStyle: const TextStyle(
                            color: kPrimaryColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          leftChevronIcon: const Icon(Icons.chevron_left, color: kPrimaryColor),
                          rightChevronIcon: const Icon(Icons.chevron_right, color: kPrimaryColor),
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
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle: const TextStyle(fontWeight: FontWeight.bold),
                          weekendStyle: TextStyle(
                            color: Colors.red.shade300,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: BoxDecoration(
                            color: kSecondaryColor.withOpacity(0.05),
                          ),
                        ),
                        calendarStyle: CalendarStyle(
                          outsideDaysVisible: false,
                          defaultDecoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.transparent,
                          ),
                          weekendDecoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.transparent,
                          ),
                          todayDecoration: BoxDecoration(
                            color: kPrimaryColor.withOpacity(0.8),
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: const BoxDecoration(
                            color: kSecondaryColor,
                            shape: BoxShape.circle,
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
                        calendarBuilders: CalendarBuilders(
                          markerBuilder: (context, date, events) {
                            if (events.isEmpty) return const SizedBox();

                            return Positioned(
                              bottom: 1,
                              child: Container(
                                width: events.length > 2 ? 16 : 12,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: events.any((e) => (e as Map?)?['isTaken'] == true ? false : true)
                                      ? Colors.orange.shade400
                                      : Colors.green.shade400,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 20),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.event_note_rounded,
                          size: 20,
                          color: kPrimaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('EEEE, d MMMM yyyy', 'ar_SA').format(_selectedDay),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _buildDoseList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDoseList() {
    final doses = _getDosesForDay(_selectedDay);

    if (doses.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                "لا توجد جرعات في هذا اليوم",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: kPrimaryColor.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "تظهر هنا جرعات أدوية ${widget.name} لهذا اليوم",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: doses.length,
      itemBuilder: (context, index) {
        final dose = doses[index];
        final isTaken = dose['isTaken'] as bool;
        final medication = dose['medication'] as String;
        final timeStr = dose['time'] as String;
        final dosage = dose['dosage'] as String? ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shadowColor: kPrimaryColor.withOpacity(0.15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius),
            side: BorderSide(
              color: isTaken
                  ? Colors.green.shade300.withOpacity(0.5)
                  : kSecondaryColor.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isTaken
                        ? Colors.green.shade100
                        : kSecondaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isTaken ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: isTaken ? Colors.green.shade600 : Colors.grey.shade500,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medication,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dosage.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          dosage,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: kSecondaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 14,
                              color: kSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isTaken
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isTaken
                          ? Colors.green.shade200
                          : Colors.red.shade200,
                    ),
                  ),
                  child: Text(
                    isTaken ? "تم أخذها" : "لم تؤخذ",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isTaken
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
