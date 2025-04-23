import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:ui' as ui;



const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const double kBorderRadius = 16.0;

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("لم يتم العثور على المرافق")),
        );
      }
    } catch (e) {
      print("Error loading companion data: $e");
    }

    setState(() => isLoading = false);
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
      final times = (data['times'] as List?) ?? [];
      final missedDoses = (data['missedDoses'] as List?) ?? [];
      final start = (data['startDate'] as Timestamp?)?.toDate();
      final end = (data['endDate'] as Timestamp?)?.toDate();
      final frequency = data['frequency'] ?? '1 يومي';

      if (start == null) continue;

      final freqParts = frequency.toString().split(' ');
      final freqType = freqParts.length > 1 ? freqParts[1] : 'يومي';

      DateTime current = start;
      while (end == null || !current.isAfter(end)) {
        final normalized = DateTime(current.year, current.month, current.day);
        List<String> timesToday = [];

        if (freqType == 'يومي') {
          timesToday = times.cast<String>();
        } else if (freqType == 'اسبوعي') {
          timesToday = times
              .whereType<Map>()
              .where((map) => map['day'] == current.weekday)
              .map((map) => map['time'].toString())
              .toList();
        }

        if (timesToday.isNotEmpty) {
          for (var time in timesToday) {
            final isTaken = _isDoseTaken(missedDoses, current, time);
            newDoses.putIfAbsent(normalized, () => []);
            newDoses[normalized]!.add({
              'medication': name,
              'time': time,
              'isTaken': isTaken,
            });
          }
        }

        current = current.add(const Duration(days: 1));
        if (end != null && current.isAfter(end)) break;
        if (end == null && current.difference(start).inDays > 365) break;
      }
    }

    setState(() => _doses = newDoses);
  }

  bool _isDoseTaken(List missedDoses, DateTime date, String timeStr) {
    final TimeOfDay? doseTime = _parseTime(timeStr);
    if (doseTime == null) return false;

    for (var dose in missedDoses) {
      if (dose is Map<String, dynamic>) {
        final scheduled = dose['scheduled'] as Timestamp?;
        final status = dose['status'] as String?;
        if (scheduled != null && status == 'taken') {
          final scheduledDate = scheduled.toDate();
          if (_isSameDay(date, scheduledDate) &&
              scheduledDate.hour == doseTime.hour &&
              scheduledDate.minute == doseTime.minute) {
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
      print("Time parsing failed: $timeStr");
      return null;
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
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
        appBar: AppBar(
          title: Text("جدول ${widget.name}"),
          backgroundColor: kPrimaryColor,
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TableCalendar(
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
                      headerStyle: HeaderStyle(
                        formatButtonVisible: true,
                        titleCentered: true,
                        formatButtonTextStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      calendarStyle: const CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: kPrimaryColor,
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: BoxDecoration(
                          color: kSecondaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "الجرعات لـ ${DateFormat('d MMMM yyyy', 'ar_SA').format(_selectedDay)}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _buildDoseList(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildDoseList() {
    final doses = _getDosesForDay(_selectedDay);

    if (doses.isEmpty) {
      return const Center(
        child: Text("لا توجد جرعات في هذا اليوم"),
      );
    }

    return ListView.builder(
      itemCount: doses.length,
      itemBuilder: (context, index) {
        final dose = doses[index];
        final isTaken = dose['isTaken'] as bool;
        final icon = isTaken
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.radio_button_unchecked, color: Colors.red);

        final statusText = isTaken ? 'تم' : 'لم يؤخذ';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: ListTile(
            leading: const Icon(Icons.medication_outlined, color: kPrimaryColor),
            title: Text(dose['medication']),
            subtitle: Text("الوقت: ${dose['time']}"),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(height: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    color: isTaken ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
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