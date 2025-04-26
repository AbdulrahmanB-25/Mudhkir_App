import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

import '../MedicationsSchedule_Utility/dose_schedule_UI.dart';
import '../MedicationsSchedule_Utility/dose_schedule_services.dart';

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

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _services = DoseScheduleServices(user: _user);

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

    try {
      final doses = await _services.fetchDoses(context);

      if (mounted) {
        setState(() {
          _doses = doses;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print('Error in _fetchDoses: $e');
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
                        },
                        getEventsForDay: _getEventsForDay,
                      ),

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
    style: TextStyle(                fontSize: 14,
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