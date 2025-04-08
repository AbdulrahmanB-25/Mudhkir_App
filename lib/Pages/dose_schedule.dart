import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DoseSchedule extends StatefulWidget {
  const DoseSchedule({super.key});

  @override
  _DoseScheduleState createState() => _DoseScheduleState();
}

class _DoseScheduleState extends State<DoseSchedule>
    with SingleTickerProviderStateMixin {
  late User _user;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  Map<DateTime, List<dynamic>> _doses = {};
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  // Dummy resources for demonstration.
  final FocusNode myFocusNode = FocusNode();
  late AnimationController myAnimationController;
  StreamSubscription? myStreamSubscription;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser!;
    _fetchDoses();
    myAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    myFocusNode.dispose();
    myAnimationController.dispose();
    myStreamSubscription?.cancel();
    super.dispose();
  }

  String formatDate(String dateString) {
    try {
      final DateTime parsedDate = DateTime.parse(dateString);
      return '${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _fetchDoses() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .collection('medicines')
        .get();

    final Map<DateTime, List<dynamic>> newDoses = {};

    for (var doc in snapshot.docs) {
      try {
        final data = doc.data();
        final String medicationName = data['name'] ?? 'No Name';
        final String? startDateString = data['startDate'];
        final String? endDateString = data['endDate'];
        final List<dynamic> times = List<dynamic>.from(data['times'] ?? []);
        // Retrieve the image URL and the delete hash.
        final String imageUrl = data['imageUrl'] ?? '';
        final String imgbbDeleteHash = data['imgbbDeleteHash'] ?? '';

        if (startDateString == null || endDateString == null) {
          print('Document ${doc.id} missing dates');
          continue;
        }

        final DateTime startDate = DateTime.parse(formatDate(startDateString));
        final DateTime endDate = DateTime.parse(formatDate(endDateString));

        for (DateTime date = startDate;
        !date.isAfter(endDate);
        date = date.add(const Duration(days: 1))) {
          final DateTime normalizedDate =
          DateTime(date.year, date.month, date.day);
          newDoses.putIfAbsent(normalizedDate, () => []);

          for (var time in times) {
            if (time != null) {
              newDoses[normalizedDate]!.add({
                'medicationName': medicationName,
                'time': time.toString(),
                'docId': doc.id,
                'imageUrl': imageUrl,
                'imgbbDeleteHash': imgbbDeleteHash,
              });
            }
          }
        }
      } catch (e) {
        print('Error processing document ${doc.id}: $e');
        continue;
      }
    }

    newDoses.forEach((date, meds) {
      meds.sort((a, b) {
        final String timeA = a['time']?.toString() ?? '';
        final String timeB = b['time']?.toString() ?? '';
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
      // Instead of an AppBar, we build a custom top tile.
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Top Tile mimicking the style from AddDose:
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button.
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.blue.shade800),
                      onPressed: () => Navigator.pop(context),
                    ),
                    // Title text.
                    Text(
                      "جدول الأدوية",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                      textAlign: TextAlign.right,
                    ),
                    // (Spacer: an empty Container to balance the Row.)
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 30),
                // Calendar Section.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
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
                        selectedDayPredicate: (day) =>
                            isSameDay(_selectedDay, day),
                        calendarStyle: CalendarStyle(
                          todayDecoration: BoxDecoration(
                            color: Colors.blue.shade800,
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: BoxDecoration(
                            color: Colors.blue.shade400,
                            shape: BoxShape.circle,
                          ),
                          todayTextStyle:
                          const TextStyle(color: Colors.white),
                          selectedTextStyle:
                          const TextStyle(color: Colors.white),
                          defaultTextStyle:
                          TextStyle(color: Colors.blue.shade800),
                          weekendTextStyle:
                          TextStyle(color: Colors.blue.shade800),
                        ),
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle:
                          TextStyle(color: Colors.blue.shade800),
                          weekendStyle:
                          TextStyle(color: Colors.blue.shade800),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                // Dose List Section.
                Container(
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
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _getEventsForDay(_selectedDay).length,
                    itemBuilder: (context, index) {
                      final dose = _getEventsForDay(_selectedDay)[index];
                      return DoseTile(
                        medicationName: dose['medicationName'],
                        nextDose: dose['time'],
                        docId: dose['docId'],
                        imageUrl: dose['imageUrl'],
                        imgbbDeleteHash: dose['imgbbDeleteHash'] ?? '',
                        onDelete: _fetchDoses,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// DoseTile displays medication info.
/// (Deletion functionality still exists here—adjust or remove as needed.)
class DoseTile extends StatefulWidget {
  final String medicationName;
  final String nextDose;
  final String docId;
  final String imageUrl;
  final String imgbbDeleteHash;
  final VoidCallback onDelete;

  const DoseTile({
    super.key,
    required this.medicationName,
    required this.nextDose,
    required this.docId,
    required this.imageUrl,
    required this.imgbbDeleteHash,
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
    final User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // If an ImgBB delete hash exists, call the deletion helper.
      if (widget.imgbbDeleteHash.isNotEmpty) {
        await _deleteImgBBImage(widget.imgbbDeleteHash);
      }
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

  Future<void> _deleteImgBBImage(String deleteHash) async {
    // Use your imgbb API key here.
    const String imgbbApiKey = '2b30d3479663bc30a70c916363b07c4a';
    final url = Uri.parse(
        'https://api.imgbb.com/1/delete?key=$imgbbApiKey&deletehash=$deleteHash');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        print("ImgBB image deleted successfully.");
      } else {
        print("Failed to delete image from ImgBB. Status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error deleting image from ImgBB: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget tile = Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      elevation: 4,
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: widget.imageUrl.isNotEmpty
              ? Image.network(
            widget.imageUrl,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
          )
              : Container(
            width: 60,
            height: 60,
            color: Colors.grey.shade300,
            alignment: Alignment.center,
            child: const Text(
              'No Image',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
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
    );

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
      child: tile,
    );
  }
}

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

  Future<File?> _downloadAndSaveImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final Directory directory = await getTemporaryDirectory();
        final String filePath = '${directory.path}/${url.hashCode}.png';
        File file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }
    } catch (e) {
      print("Error downloading image: $e");
    }
    return null;
  }

  void _openEnlargedImage(File imageFile) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white), // Back button white
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.file(imageFile),
          ),
        ),
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _imageFileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey.shade300,
            child: const Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasData && snapshot.data != null) {
          return GestureDetector(
            onTap: () => _openEnlargedImage(snapshot.data!),
            child: Image.file(
              snapshot.data!,
              width: widget.width,
              height: widget.height,
              fit: BoxFit.cover,
            ),
          );
        } else {
          return Container(
            width: widget.width,
            height: widget.height,
            color: Colors.grey.shade300,
            alignment: Alignment.center,
            child: const Text(
              'No Image',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          );
        }
      },
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
