import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';

class DoseSchedule extends StatefulWidget {
  const DoseSchedule({super.key});

  @override
  _DoseScheduleState createState() => _DoseScheduleState();
}

class _DoseScheduleState extends State<DoseSchedule> {
  late User _user;
  late CalendarFormat _calendarFormat;
  Map<DateTime, List<dynamic>> _doses = {};
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser!;
    _calendarFormat = CalendarFormat.week;
    _fetchDoses();
  }

  /// Converts a date string from "yyyy-M-d" to "yyyy-MM-dd"
  String formatDate(String dateString) {
    List<String> parts = dateString.split('-');
    if (parts.length != 3) return dateString;
    String year = parts[0];
    String month = parts[1].padLeft(2, '0');
    String day = parts[2].padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _fetchDoses() async {
    // Query the medicines collection for the current user.
    final snapshot = await FirebaseFirestore.instance
        .collection('medicines')
        .where('userId', isEqualTo: _user.uid)
        .get();

    final Map<DateTime, List<dynamic>> newDoses = {};

    for (var doc in snapshot.docs) {
      final data = doc.data() ;
      final String medicationName = data['name'] ?? 'No Name';
      final String startDateString = data['startDate']; // e.g. "2025-3-23"
      final String endDateString = data['endDate'];     // e.g. "2025-12-30"
      final List<dynamic> times = data['times'] ?? [];

      // Reformat date strings to proper ISO format
      final DateTime startDate = DateTime.parse(formatDate(startDateString));
      final DateTime endDate = DateTime.parse(formatDate(endDateString));

      // Loop through each day from startDate to endDate (inclusive)
      for (DateTime date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))) {
        final DateTime normalizedDate =
        DateTime(date.year, date.month, date.day);
        newDoses.putIfAbsent(normalizedDate, () => []);

        // Add each time entry as a separate medication entry.
        for (var time in times) {
          newDoses[normalizedDate]!.add({
            'medicationName': medicationName,
            'time': time,
            'docId': doc.id,
          });
        }
      }
    }

    // Sort medications for each day by time (assuming time is in "HH:mm" or similar format)
    newDoses.forEach((date, meds) {
      meds.sort((a, b) {
        final String timeA = a['time'] as String;
        final String timeB = b['time'] as String;
        return timeA.compareTo(timeB);
      });
    });

    setState(() {
      _doses = newDoses;
    });

    print('Fetched doses (grouped by date): $_doses');
  }

  List<dynamic> _getEventsForDay(DateTime day) {
    final DateTime normalizedDay = DateTime(day.year, day.month, day.day);
    return _doses[normalizedDay] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "جدول الأدوية",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade800,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            TableCalendar(
              focusedDay: _focusedDay,
              firstDay: DateTime(2000),
              lastDay: DateTime(2100),
              calendarFormat: _calendarFormat,
              availableCalendarFormats: const {CalendarFormat.week: 'Week'},
              onFormatChanged: (format) {
                setState(() {
                  _calendarFormat = format;
                });
              },
              eventLoader: _getEventsForDay,
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Colors.blue.shade800,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Colors.blue.shade400,
                  shape: BoxShape.circle,
                ),
                todayTextStyle: const TextStyle(color: Colors.white),
                selectedTextStyle: const TextStyle(color: Colors.white),
                defaultTextStyle: TextStyle(color: Colors.blue.shade800),
                weekendTextStyle: TextStyle(color: Colors.blue.shade800),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(color: Colors.blue.shade800),
                weekendStyle: TextStyle(color: Colors.blue.shade800),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: _getEventsForDay(_selectedDay)
                    .map((dose) => DoseTile(
                  dose['medicationName'],
                  dose['time'],
                  dose['docId'],
                ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class DoseTile extends StatelessWidget {
  final String medicationName;
  final String nextDose;
  final String docId;

  const DoseTile(this.medicationName, this.nextDose, this.docId, {super.key});

  Future<void> _removeMedication(BuildContext context) async {
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Deletion"),
          content: const Text("Are you sure you want to delete this medication?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Delete"),
            ),
          ],
        );
      },
    );

    if (confirm) {
      await FirebaseFirestore.instance.collection('medicines').doc(docId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Medication deleted successfully")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicationName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  nextDose,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _removeMedication(context),
          ),
        ],
      ),
    );
  }
}