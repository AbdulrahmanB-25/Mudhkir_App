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
  // Force the calendar to show full month view.
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<dynamic>> _doses = {};
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser!;
    _fetchDoses();
  }

  String formatDate(String dateString) {
    List<String> parts = dateString.split('-');
    if (parts.length != 3) return dateString;
    String year = parts[0];
    String month = parts[1].padLeft(2, '0');
    String day = parts[2].padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _fetchDoses() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .collection('medicines')
        .get();

    final Map<DateTime, List<dynamic>> newDoses = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final String medicationName = data['name'] ?? 'No Name';
      final String startDateString = data['startDate'];
      final String endDateString = data['endDate'];
      final List<dynamic> times = data['times'] ?? [];
      final String imageUrl = data['imageUrl'] ?? '';

      if (startDateString == null || endDateString == null) continue;

      final DateTime startDate = DateTime.parse(formatDate(startDateString));
      final DateTime endDate = DateTime.parse(formatDate(endDateString));

      for (DateTime date = startDate;
      !date.isAfter(endDate);
      date = date.add(const Duration(days: 1))) {
        final DateTime normalizedDate = DateTime(date.year, date.month, date.day);
        newDoses.putIfAbsent(normalizedDate, () => []);

        for (var time in times) {
          newDoses[normalizedDate]!.add({
            'medicationName': medicationName,
            'time': time,
            'docId': doc.id,
            'imageUrl': imageUrl,
          });
        }
      }
    }

    // Sort doses for each day by time.
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
          style: TextStyle(color: Colors.blue),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
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
            // Calendar Section.
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TableCalendar(
                    focusedDay: _focusedDay,
                    firstDay: DateTime(2000),
                    lastDay: DateTime(2100),
                    calendarFormat: _calendarFormat,
                    headerStyle: HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    eventLoader: _getEventsForDay,
                    calendarBuilders: CalendarBuilders(
                      markerBuilder: (context, date, events) =>
                      const SizedBox.shrink(),
                    ),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _selectedDay = selectedDay;
                        _focusedDay = selectedDay;
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
                      markerDecoration: const BoxDecoration(
                        color: Colors.transparent,
                      ),
                    ),
                    daysOfWeekStyle: DaysOfWeekStyle(
                      weekdayStyle: TextStyle(color: Colors.blue.shade800),
                      weekendStyle: TextStyle(color: Colors.blue.shade800),
                    ),
                  ),
                ),
              ),
            ),
            // Dose List Section.
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _getEventsForDay(_selectedDay).isEmpty
                    ? Center(
                  child: Text(
                    "لا يوجد جرعات لهذا اليوم",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.blue.shade800,
                    ),
                  ),
                )
                    : ListView.builder(
                  itemCount: _getEventsForDay(_selectedDay).length,
                  itemBuilder: (context, index) {
                    final dose = _getEventsForDay(_selectedDay)[index];
                    return DoseTile(
                      medicationName: dose['medicationName'],
                      nextDose: dose['time'],
                      docId: dose['docId'],
                      imageUrl: dose['imageUrl'], // pass imageUrl here
                      onDelete: _fetchDoses,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DoseTile extends StatefulWidget {
  final String medicationName;
  final String nextDose;
  final String docId;
  final String imageUrl;
  final VoidCallback onDelete;

  const DoseTile({
    super.key,
    required this.medicationName,
    required this.nextDose,
    required this.docId,
    required this.imageUrl,
    required this.onDelete,
  });

  @override
  _DoseTileState createState() => _DoseTileState();
}

class _DoseTileState extends State<DoseTile> {
  Future<bool?> _confirmDismiss(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("تأكيد الحذف"),
        content: const Text("هل أنت متأكد من حذف هذا الدواء؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("حذف"),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMedication(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(widget.docId)
          .delete();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("تم حذف الدواء بنجاح")),
    );
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(widget.docId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white, size: 30),
      ),
      confirmDismiss: (direction) => _confirmDismiss(context),
      onDismissed: (direction) async {
        await _deleteMedication(context);
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 4,
        child: ListTile(
          // Display the image if imageUrl is provided; otherwise, show default icon.
          leading: widget.imageUrl.isNotEmpty
              ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              widget.imageUrl,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
          )
              : Icon(
            Icons.medication_liquid,
            color: Colors.blue.shade800,
            size: 40,
          ),
          title: Text(
            widget.medicationName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade800,
            ),
          ),
          subtitle: Text(
            widget.nextDose,
            style: TextStyle(
              fontSize: 14,
              color: Colors.blue.shade600,
            ),
          ),
        ),
      ),
    );
  }
}

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
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, 5)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 50, color: Colors.blue.shade800),
              const SizedBox(width: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
