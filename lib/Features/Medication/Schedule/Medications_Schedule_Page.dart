import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import 'dose_schedule_UI.dart';
import 'dose_schedule_services.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const double kBorderRadius = 16.0;
const double kSpacing = 16.0;

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
  late DoseScheduleServices _services;
  DateTime? _lastFetchStart;
  DateTime? _lastFetchEnd;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _services = DoseScheduleServices(user: _user);

    // Handle case where user is not logged in
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
      _fetchDosesForVisibleRange();
    }
  }

  Future<void> _fetchDosesForVisibleRange() async {
    if (!mounted || _user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Calculate the range of dates to fetch doses for
      final year = _focusedDay.year;
      final month = _focusedDay.month;
      final fetchStart = DateTime(year, month - 1, 1);
      final fetchEnd = DateTime(year, month + 2, 0);

      // Avoid redundant fetches if data is already cached
      if (_lastFetchStart != null && _lastFetchEnd != null) {
        if (!fetchStart.isBefore(_lastFetchStart!) && !fetchEnd.isAfter(_lastFetchEnd!)) {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      final doses = await _services.fetchDoses(
        context,
        startRangeDate: fetchStart,
        endRangeDate: fetchEnd,
      );

      if (mounted) {
        setState(() {
          _doses = doses;
          _isLoading = false;
          _lastFetchStart = fetchStart;
          _lastFetchEnd = fetchEnd;
        });
      }
    } catch (e) {
      print('Error in _fetchDosesForVisibleRange: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
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

  Future<void> _fetchDoses() async {
    // Clear the service cache first to ensure fresh data after edits/deletes
    _services.clearCache(); 
    
    // Reset local fetch range flags
    _lastFetchStart = null;
    _lastFetchEnd = null;
    
    // Proceed to fetch data for the currently focused range
    await _fetchDosesForVisibleRange();
  }

  // Helper method to retrieve events for a specific day
  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    final DateTime normalizedDay = DateTime(day.year, day.month, day.day);
    return _doses[normalizedDay] ?? [];
  }

  Widget _buildDateAndDosesHeader() {
    // Builds the header displaying the selected date and dose count
    final events = _getEventsForDay(_selectedDay);
    final doseCount = events.length;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
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
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    size: 20,
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
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        DateFormat('d MMMM yyyy', 'ar_SA').format(_selectedDay),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.medication_rounded,
                        size: 18,
                        color: kPrimaryColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "$doseCount ${doseCount == 1 ? 'جرعة' : 'جرعات'}",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(kBorderRadius),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 16,
                  color: Colors.white.withOpacity(0.85),
                ),
                const SizedBox(width: 8),
                Text(
                  doseCount > 0
                      ? "الجرعات المجدولة لهذا اليوم"
                      : "لا توجد جرعات مجدولة لهذا اليوم",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Main build method for the DoseSchedule page
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
                            CalendarWidget(
                              focusedDay: _focusedDay,
                              selectedDay: _selectedDay,
                              calendarFormat: _calendarFormat,
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
                                _fetchDosesForVisibleRange();
                              },
                              getEventsForDay: _getEventsForDay,
                            ),

                            // Date and Doses Header Bar
                            _buildDateAndDosesHeader(),

                            _buildDoseList(),

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
    // Builds the list of doses for the selected day
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
            selectedDay: _selectedDay,
          ),
          if (index < events.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}
