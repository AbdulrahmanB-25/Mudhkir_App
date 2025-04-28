import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:ui' as ui;
import '../Companions_Utilly/CompanionMedications_Addation.dart';
import '../Pages/EditMedication_Page.dart';
import '../services/companion_medication_tracker.dart';

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

class _CompanionDetailPageState extends State<CompanionDetailPage> with SingleTickerProviderStateMixin {
  String? companionUid;
  bool isLoading = true;
  Map<DateTime, List<Map<String, dynamic>>> _doses = {};
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _loadCompanionData();
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanionData() async {
    setState(() => isLoading = true);
    try {
      final query = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: widget.email).limit(1).get();
      if (query.docs.isNotEmpty) {
        companionUid = query.docs.first.id;
        await _fetchDoses();
      } else {
        if (mounted) {
          _showSnackBar("لم يتم العثور على المرافق", isError: true);
        }
      }
    } catch (e) {
      print("Error loading companion data: $e");
      if (mounted) {
        _showSnackBar("حدث خطأ أثناء تحميل البيانات: ${e.toString()}", isError: true);
      }
    }
    if (mounted) setState(() => isLoading = false);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'تم',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  Future<void> _fetchDoses() async {
    if (companionUid == null) return;
    final snapshot = await FirebaseFirestore.instance.collection('users').doc(companionUid).collection('medicines').get();
    final Map<DateTime, List<Map<String, dynamic>>> newDoses = {};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      final name = data['name'] ?? 'بدون اسم';
      final dosage = data['dosage'] as String? ?? '';
      final times = (data['times'] as List?) ?? [];
      final missedDoses = (data['missedDoses'] as List?) ?? [];
      final start = (data['startDate'] as Timestamp?)?.toDate();
      final end = (data['endDate'] as Timestamp?)?.toDate();
      String frequencyType = 'يومي';
      if (data.containsKey('frequencyType') && data['frequencyType'] == 'اسبوعي') {
        frequencyType = 'اسبوعي';
      } else if (data.containsKey('frequency')) {
        final String frequencyRaw = data['frequency'] as String? ?? '';
        final List<String> frequencyParts = frequencyRaw.split(" ");
        if (frequencyParts.length > 1 && frequencyParts[1] == 'اسبوعي') frequencyType = 'اسبوعي';
      }
      if (start == null) continue;
      DateTime current = start;
      while (end == null || !current.isAfter(end)) {
        final normalized = DateTime(current.year, current.month, current.day);
        if (frequencyType == 'يومي') {
          for (var timeValue in times) {
            String timeStr;
            if (timeValue is String)
              timeStr = timeValue;
            else if (timeValue is Map && timeValue.containsKey('time'))
              timeStr = timeValue['time'].toString();
            else
              continue;
            final isTaken = _isDoseTaken(missedDoses, current, timeStr);
            newDoses.putIfAbsent(normalized, () => []);
            newDoses[normalized]!.add({'medication': name, 'dosage': dosage, 'time': timeStr, 'isTaken': isTaken, 'docId': doc.id});
          }
        } else if (frequencyType == 'اسبوعي') {
          for (var item in times) {
            if (item is Map && item.containsKey('day') && item.containsKey('time')) {
              int? dayValue;
              if (item['day'] is int)
                dayValue = item['day'];
              else if (item['day'] is String)
                dayValue = int.tryParse(item['day']);
              else if (item['day'] is double)
                dayValue = (item['day'] as double).toInt();
              if (dayValue == current.weekday) {
                String timeStr = item['time'].toString();
                final isTaken = _isDoseTaken(missedDoses, current, timeStr);
                newDoses.putIfAbsent(normalized, () => []);
                newDoses[normalized]!.add({'medication': name, 'dosage': dosage, 'time': timeStr, 'isTaken': isTaken, 'docId': doc.id});
              }
            }
          }
        }
        current = current.add(const Duration(days: 1));
        if (end != null && current.isAfter(end)) break;
        if (end == null && current.difference(start).inDays > 365 * 5) break;
      }
    }
    newDoses.forEach((date, doseList) {
      doseList.sort((a, b) {
        final timeA = _parseTime(a['time'].toString());
        final timeB = _parseTime(b['time'].toString());
        if (timeA == null || timeB == null) return 0;
        if (timeA.hour != timeB.hour) return timeA.hour.compareTo(timeB.hour);
        return timeA.minute.compareTo(timeB.minute);
      });
    });
    if (mounted) setState(() => _doses = newDoses);
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
          if (scheduledDate.isAtSameMomentAs(dateNormalized) && scheduledDateTime.hour == doseTime.hour && scheduledDateTime.minute == doseTime.minute) {
            return true;
          }
        }
      }
    }
    return false;
  }

  TimeOfDay? _parseTime(String timeStr) {
    try {
      String normalizedTime = timeStr.replaceAll('صباحاً', 'AM').replaceAll('مساءً', 'PM').trim();
      final DateFormat format = DateFormat('h:mm a', 'en_US');
      final date = format.parse(normalizedTime);
      return TimeOfDay.fromDateTime(date);
    } catch (e) {
      try {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          int hour = int.parse(parts[0]);
          int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
          if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) return TimeOfDay(hour: hour, minute: minute);
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
    final hasDoses = _getDosesForDay(_selectedDay).isNotEmpty;

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        extendBodyBehindAppBar: true,
        appBar: null,
        floatingActionButton: hasDoses ? FloatingActionButton(
          onPressed: _navigateToAddMedication,
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          tooltip: "إضافة دواء جديد",
          child: const Icon(Icons.add),
        ) : null,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor,
                kPrimaryColor.withOpacity(0.8),
                kBackgroundColor.withOpacity(0.9),
                kBackgroundColor
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.15, 0.3, 1.0],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeInAnimation,
              child: isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 50,
                            height: 50,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              "جاري تحميل جدول الأدوية...",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Row(
                            children: [
                              Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => Navigator.pop(context),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Icon(
                                      Icons.arrow_back,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  "جدول ${widget.name}",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                    color: Colors.white,
                                    shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
                                  ),
                                ),
                              ),
                              SizedBox(width: 38),
                            ],
                          ),
                        ),
                        Expanded(child: _buildMainContent()),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          children: [
            _buildSelectedDateHeader(),
            _buildCalendarCard(),
            _buildDoseList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Card(
        elevation: 4,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kBorderRadius)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kBorderRadius),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.1),
                  border: Border(bottom: BorderSide(color: kSecondaryColor.withOpacity(0.2))),
                ),
              ),
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
                onFormatChanged: (format) => setState(() => _calendarFormat = format),
                onPageChanged: (focusedDay) => _focusedDay = focusedDay,
                availableCalendarFormats: const {CalendarFormat.month: 'شهر', CalendarFormat.week: 'اسبوع'},
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
                    border: Border(bottom: BorderSide(color: kSecondaryColor.withOpacity(0.1), width: 1)),
                  ),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: const TextStyle(fontWeight: FontWeight.bold),
                  weekendStyle: TextStyle(color: Colors.red.shade300, fontWeight: FontWeight.bold),
                  decoration: BoxDecoration(color: kSecondaryColor.withOpacity(0.05)),
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  defaultDecoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.transparent),
                  weekendDecoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.transparent),
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

                    final hasMissedDoses = events.any((e) => (e as Map?)?['isTaken'] == false);
                    final allTaken = events.every((e) => (e as Map?)?['isTaken'] == true);

                    Color markerColor = Colors.orange.shade400;
                    if (allTaken) markerColor = Colors.green.shade400;
                    else if (hasMissedDoses) markerColor = Colors.red.shade400;

                    // Move marker to top of cell
                    return Positioned(
                      top: 1,
                      right: 1,
                      left: 1,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          events.length > 3 ? 3 : events.length,
                              (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: markerColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: markerColor.withOpacity(0.5),
                                  blurRadius: 1,
                                  offset: const Offset(0, 0),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedDateHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryColor, kSecondaryColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.event_note_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEEE', 'ar_SA').format(_selectedDay),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  DateFormat('d MMMM yyyy', 'ar_SA').format(_selectedDay),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              "${_getDosesForDay(_selectedDay).length} جرعات",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: kPrimaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoseList() {
    final doses = _getDosesForDay(_selectedDay);

    if (doses.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kBorderRadius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                border: Border(bottom: BorderSide(color: kSecondaryColor.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  Icon(Icons.medication_liquid_rounded, size: 20, color: kPrimaryColor),
                  const SizedBox(width: 8),
                  Text(
                    "جرعات اليوم",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kPrimaryColor,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: kSecondaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      doses.length.toString(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: doses.length,
              itemBuilder: (context, index) => _buildDoseItem(doses[index]),
              separatorBuilder: (context, index) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Colors.grey.shade200,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoseItem(Map<String, dynamic> dose) {
    final isTaken = dose['isTaken'] as bool;
    final medication = dose['medication'] as String;
    final timeStr = dose['time'] as String;
    final dosage = dose['dosage'] as String? ?? '';
    final docId = dose['docId'] as String;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kBorderRadius),
          onTap: () {
            _showMedicationOptionsBottomSheet(docId, medication, timeStr, isTaken);
          },
          splashColor: kPrimaryColor.withOpacity(0.1),
          highlightColor: kPrimaryColor.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildDoseStatusIndicator(isTaken),
                const SizedBox(width: 16),
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 14, color: kSecondaryColor),
                          const SizedBox(width: 6),
                          Text(
                            timeStr,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (dosage.isNotEmpty) ...[
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Text(
                              dosage,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isTaken ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isTaken ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isTaken ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
                        size: 14,
                        color: isTaken ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isTaken ? "تم أخذها" : "لم تؤخذ",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isTaken ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMedicationOptionsBottomSheet(String medicationId, String medicationName, String timeStr, bool isTaken) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        // Take up to 80% of screen height
        heightFactor: 0.8,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),

              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPrimaryColor.withOpacity(0.8), kSecondaryColor.withOpacity(0.8)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kPrimaryColor.withOpacity(0.1),
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      )
                    ]
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.medication_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                medicationName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 2,
                                      color: Colors.black26,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "الوقت: $timeStr",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        "حالة الجرعة: ${isTaken ? "تم أخذها" : "لم تؤخذ"}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Title
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "خيارات إدارة الدواء",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryColor,
                  ),
                ),
              ),

              // Divider
              Divider(height: 1, color: Colors.grey.shade200),

              // Options
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isTaken)
                        _buildOptionTile(
                          icon: Icons.check_circle_rounded,
                          iconColor: Colors.green.shade700,
                          title: "تأكيد تناول الجرعة",
                          subtitle: "تأكيد أن المرافق تناول هذه الجرعة",
                          onTap: () {
                            Navigator.pop(context);
                            _confirmDoseTaken(medicationId, timeStr);
                          },
                        ),

                      if (isTaken)
                        _buildOptionTile(
                          icon: Icons.cancel_outlined,
                          iconColor: Colors.orange.shade700,
                          title: "إلغاء تأكيد تناول الجرعة",
                          subtitle: "إلغاء تأكيد تناول هذه الجرعة",
                          onTap: () {
                            Navigator.pop(context);
                            _unconfirmDoseTaken(medicationId, timeStr);
                          },
                        ),

                      _buildOptionTile(
                        icon: Icons.edit_outlined,
                        iconColor: kPrimaryColor,
                        title: "تعديل الدواء",
                        subtitle: "تعديل معلومات الدواء والجرعات",
                        onTap: () {
                          Navigator.pop(context);
                          _navigateToEditMedication(medicationId);
                        },
                      ),

                      _buildOptionTile(
                        icon: Icons.event_busy_outlined,
                        iconColor: Colors.orange.shade700,
                        title: "إنهاء الدواء",
                        subtitle: "إنهاء جدول هذا الدواء",
                        onTap: () {
                          Navigator.pop(context);
                          _confirmEndMedication(medicationId, medicationName);
                        },
                      ),

                      _buildOptionTile(
                        icon: Icons.delete_outlined,
                        iconColor: Colors.red.shade700,
                        title: "حذف الدواء",
                        subtitle: "حذف هذا الدواء وجميع سجلاته",
                        onTap: () {
                          Navigator.pop(context);
                          _confirmDeleteMedication(medicationId, medicationName);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Close button
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("إغلاق",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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

  Widget _buildDoseStatusIndicator(bool isTaken) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isTaken
              ? [Colors.green.shade400, Colors.green.shade600]
              : [Colors.grey.shade300, Colors.grey.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isTaken ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          isTaken ? Icons.check_rounded : Icons.circle_outlined,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: child,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.medication_liquid_outlined,
                  size: 80,
                  color: kPrimaryColor.withOpacity(0.7),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              "لا توجد جرعات في هذا اليوم",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: kPrimaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              "تظهر هنا جرعات أدوية ${widget.name} لهذا اليوم",
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text("إضافة دواء جديد"),
              onPressed: _navigateToAddMedication,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey.shade400,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToAddMedication() {
    if (companionUid == null) {
      _showSnackBar("لم يتم العثور على معلومات المرافق", isError: true);
      return;
    }

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => CompanionMedicationsPage(
                companionId: companionUid!,
                companionName: widget.name
            )
        )
    ).then((_) => _fetchDoses());
  }

  Future<void> _confirmDoseTaken(String medicationId, String timeStr) async {
    final doseTime = _parseTime(timeStr);
    if (doseTime == null) return;

    final scheduled = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        doseTime.hour,
        doseTime.minute
    );

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(companionUid)
          .collection('medicines')
          .doc(medicationId)
          .update({
        "missedDoses": FieldValue.arrayUnion([
          {
            'scheduled': Timestamp.fromDate(scheduled),
            'status': 'taken',
            'confirmedAt': Timestamp.fromDate(DateTime.now())
          }
        ])
      });

      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          final checkId = CompanionMedicationTracker.generateCompanionCheckId(
              companionUid!,
              medicationId,
              scheduled
          );

          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('companion_dose_checks')
              .doc(checkId.toString())
              .update({'processed': true});

          debugPrint("Marked companion check as processed");
        }
      } catch (e) {
        debugPrint("Error updating companion check status: $e");
      }

      _showSnackBar("تم تأكيد تناول الجرعة");
      _fetchDoses();
    } catch (e) {
      debugPrint("Error confirming dose: $e");
      _showSnackBar("حدث خطأ أثناء تأكيد الجرعة: $e", isError: true);
    }
  }

  Future<void> _unconfirmDoseTaken(String medicationId, String timeStr) async {
    final doseTime = _parseTime(timeStr);
    if (doseTime == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(companionUid)
          .collection('medicines')
          .doc(medicationId);

      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) return;

      final data = docSnapshot.data()!;
      final missedDoses = List.from(data['missedDoses'] ?? []);

      int indexToUpdate = -1;
      final selectedDate = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);

      for (int i = 0; i < missedDoses.length; i++) {
        final dose = missedDoses[i];
        if (dose is Map<String, dynamic>) {
          final scheduled = dose['scheduled'] as Timestamp?;
          final status = dose['status'] as String?;

          if (scheduled != null && status == 'taken') {
            final scheduledDateTime = scheduled.toDate();
            final scheduledDate = DateTime(scheduledDateTime.year, scheduledDateTime.month, scheduledDateTime.day);

            if (scheduledDate.isAtSameMomentAs(selectedDate) &&
                scheduledDateTime.hour == doseTime.hour &&
                scheduledDateTime.minute == doseTime.minute) {
              indexToUpdate = i;
              break;
            }
          }
        }
      }

      if (indexToUpdate != -1) {
        missedDoses[indexToUpdate]['status'] = 'pending';

        await docRef.update({'missedDoses': missedDoses});

        _showSnackBar("تم إلغاء تأكيد تناول الجرعة", isError: false);
        _fetchDoses();
      }
    } catch (e) {
      print("Error unconfirming dose: $e");
      _showSnackBar("حدث خطأ أثناء إلغاء تأكيد الجرعة: ${e.toString()}", isError: true);
    }
  }

  void _navigateToEditMedication(String medicationId) {
    if (companionUid == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCompanionMedicationPage(
          companionId: companionUid!,
          medicationId: medicationId,
          companionName: widget.name,
        ),
      ),
    ).then((_) => _fetchDoses());
  }

  void _confirmEndMedication(String medicationId, String medicationName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kBorderRadius)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_busy_outlined, color: Colors.orange.shade700),
            ),
            const SizedBox(width: 16),
            const Text("إنهاء الدواء"),
          ],
        ),
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          color: kPrimaryColor,
          fontSize: 20,
        ),
        content: Text(
          "هل أنت متأكد من إنهاء دواء $medicationName؟\nسيتم وضع تاريخ اليوم كآخر يوم لجدول هذا الدواء.",
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 15,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء"),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text("إنهاء الدواء"),
            onPressed: () {
              Navigator.pop(context);
              _endMedication(medicationId);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _endMedication(String medicationId) async {
    if (companionUid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(companionUid)
          .collection('medicines')
          .doc(medicationId)
          .update({
        'endDate': Timestamp.fromDate(_selectedDay),
        'lastUpdated': FieldValue.serverTimestamp(),
        'status': 'ended'
      });
      _showSnackBar("تم إنهاء الدواء بنجاح");
      _fetchDoses();
    } catch (e) {
      print("Error ending medication: $e");
      _showSnackBar("حدث خطأ أثناء إنهاء الدواء: ${e.toString()}", isError: true);
    }
  }

  void _confirmDeleteMedication(String medicationId, String medicationName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kBorderRadius)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.delete_outline, color: Colors.red.shade700),
            ),
            const SizedBox(width: 16),
            const Text("حذف الدواء"),
          ],
        ),
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          color: kPrimaryColor,
          fontSize: 20,
        ),
        content: Text(
          "هل أنت متأكد من حذف دواء $medicationName؟\nهذا الإجراء لا يمكن التراجع عنه.",
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 15,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إلغاء"),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: const Text("حذف"),
            onPressed: () {
              Navigator.pop(context);
              _deleteMedication(medicationId);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMedication(String medicationId) async {
    if (companionUid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(companionUid)
          .collection('medicines')
          .doc(medicationId)
          .delete();
      _showSnackBar("تم حذف الدواء بنجاح");
      _fetchDoses();
    } catch (e) {
      print("Error deleting medication: $e");
      _showSnackBar("حدث خطأ أثناء حذف الدواء: ${e.toString()}", isError: true);
    }
  }
}

class EditCompanionMedicationPage extends StatelessWidget {
  final String companionId;
  final String medicationId;
  final String companionName;

  const EditCompanionMedicationPage({
    Key? key,
    required this.companionId,
    required this.medicationId,
    required this.companionName
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        appBar: AppBar(
          title: Text(
            "تعديل دواء لـ $companionName",
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Colors.white,
            ),
          ),
          backgroundColor: kPrimaryColor,
          elevation: 0,
          centerTitle: true,
        ),
        body: EditMedicationScreen(docId: medicationId, companionId: companionId),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final bool confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_forever_rounded,
                color: Colors.red.shade700,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "حذف الدواء",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "هل أنت متأكد من حذف هذا الدواء؟\nهذا الإجراء لا يمكن التراجع عنه.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      "إلغاء",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "نعم، حذف",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ) ?? false;

    if (confirm) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(companionId)
            .collection('medicines')
            .doc(medicationId)
            .delete();
        Navigator.of(context).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 10),
                const Text("تم حذف الدواء بنجاح"),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(10),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(child: Text("حدث خطأ أثناء حذف الدواء: ${e.toString()}")),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(10),
          ),
        );
      }
    }
  }
}

