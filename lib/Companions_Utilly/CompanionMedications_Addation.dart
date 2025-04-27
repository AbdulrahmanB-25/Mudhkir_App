import 'dart:convert';

import 'package:flutter/material.dart';
import '../Pages/Add_Medicaiton/Add_Name_Picture.dart';
import '../Pages/Add_Medicaiton/Add_Dosage.dart';
import '../Pages/Add_Medicaiton/Add_Start_&_End_Date.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/companion_medication_tracker.dart';

class CompanionMedicationsPage extends StatefulWidget {
  final String companionId;
  final String companionName;

  const CompanionMedicationsPage({
    Key? key,
    required this.companionId,
    required this.companionName,
  }) : super(key: key);

  @override
  State<CompanionMedicationsPage> createState() => _CompanionMedicationsPageState();
}

class _CompanionMedicationsPageState extends State<CompanionMedicationsPage> {
  final PageController _pageController = PageController();
  final GlobalKey<FormState> _formKeyPage1 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyPage2 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyPage3 = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  String _dosageUnit = 'ملغم';
  String _frequencyType = 'يومي';
  int _frequencyNumber = 1;
  DateTime? _startDate = DateTime.now();
  DateTime? _endDate;
  List<TimeOfDay?> _selectedTimes = [];
  Set<int> _selectedWeekdays = {};
  Map<int, TimeOfDay?> _weeklyTimes = {};
  late Future<List<String>> _medicineNamesFuture;

  @override
  void initState() {
    super.initState();
    _selectedTimes = List.filled(_frequencyNumber, null, growable: true);
    _medicineNamesFuture = _loadMedicineNames();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<List<String>> _loadMedicineNames() async {
    try {
      final String jsonString = await DefaultAssetBundle.of(context)
          .loadString('assets/Mediciens/trade_names.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((item) => item.toString()).toList();
    } catch (e) {
      print('Error loading medicine names: $e');
      return [];
    }
  }

  void _nextPage() {
    if (_pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_pageController.hasClients) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _submitForm() async {
    if (!_formKeyPage3.currentState!.validate()) return;

    final medicationData = {
      'name': _nameController.text.trim(),
      'dosage': '${_dosageController.text.trim()} $_dosageUnit',
      'frequencyType': _frequencyType,
      'frequencyDetails': _frequencyType == 'يومي'
          ? {'timesPerDay': _frequencyNumber}
          : {'selectedWeekdays': _selectedWeekdays.toList()},
      'times': _frequencyType == 'يومي'
          ? _selectedTimes.map((t) => t?.format(context)).toList()
          : _weeklyTimes.entries
          .where((entry) => entry.value != null)
          .map((entry) => {'day': entry.key, 'time': entry.value!.format(context)})
          .toList(),
      'startDate': _startDate,
      'endDate': _endDate,
      'createdAt': FieldValue.serverTimestamp(),
      'missedDoses': [], // Initialize the missedDoses array
    };

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.companionId)
          .collection('medicines')
          .add(medicationData);

      final medicationId = docRef.id;
      final medicationName = _nameController.text.trim();

      debugPrint("Medication added successfully: $medicationName (ID: $medicationId)");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("تمت إضافة الدواء بنجاح"),
          backgroundColor: Colors.green.shade700,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      debugPrint("Error adding medication: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("حدث خطأ أثناء إضافة الدواء: $e"),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String _getDayName(int day) {
    const days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    return days[day - 1];
  }

  // Helper to combine a date and time
  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("إضافة دواء لـ ${widget.companionName}"),
        backgroundColor: const Color(0xFF2E86C1),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          AddNamePicturePage(
            formKey: _formKeyPage1,
            nameController: _nameController,
            medicineNamesFuture: _medicineNamesFuture,
            capturedImage: null,
            uploadedImageUrl: null,
            onPickImage: () {},
            onNext: () {
              if (_formKeyPage1.currentState!.validate()) {
                _nextPage();
              }
            },
            onBack: () => Navigator.pop(context),
          ),
          AddDosagePage(
            formKey: _formKeyPage2,
            dosageController: _dosageController,
            dosageUnit: _dosageUnit,
            dosageUnits: ['ملغم', 'غرام', 'مل', 'وحدة'],
            frequencyType: _frequencyType,
            frequencyTypes: ['يومي', 'اسبوعي'],
            frequencyNumber: _frequencyNumber,
            frequencyNumbers: [1, 2, 3, 4, 5, 6],
            selectedTimes: _selectedTimes,
            isAutoGeneratedTimes: List.filled(_frequencyNumber, false),
            selectedWeekdays: _selectedWeekdays,
            weeklyTimes: _weeklyTimes,
            weeklyAutoGenerated: {},
            onDosageUnitChanged: (value) {
              if (value != null) setState(() => _dosageUnit = value);
            },
            onFrequencyNumberChanged: (value) {
              if (value != null) {
                setState(() {
                  _frequencyNumber = value;
                  _selectedTimes = List.filled(_frequencyNumber, null, growable: true);
                });
              }
            },
            onFrequencyTypeChanged: (value) {
              if (value != null) {
                setState(() {
                  _frequencyType = value;
                  if (value == 'يومي') {
                    _selectedWeekdays.clear();
                    _weeklyTimes.clear();
                  } else {
                    _selectedTimes = [];
                  }
                });
              }
            },
            onSelectTime: (index) async {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (time != null) {
                setState(() => _selectedTimes[index] = time);
              }
            },
            onWeekdaySelected: (day, isSelected) {
              setState(() {
                if (isSelected) {
                  _selectedWeekdays.add(day);
                } else {
                  _selectedWeekdays.remove(day);
                  _weeklyTimes.remove(day);
                }
              });
            },
            onSelectWeeklyTime: (day) async {
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (time != null) {
                setState(() => _weeklyTimes[day] = time);
              }
            },
            onApplySameTimeToAllWeekdays: () {
              if (_selectedWeekdays.isNotEmpty) {
                final firstDay = _selectedWeekdays.first;
                final time = _weeklyTimes[firstDay];
                if (time != null) {
                  setState(() {
                    for (var day in _selectedWeekdays) {
                      _weeklyTimes[day] = time;
                    }
                  });
                }
              }
            },
            onNext: () {
              if (_formKeyPage2.currentState!.validate()) {
                _nextPage();
              }
            },
            onBack: _previousPage,
            getDayName: (day) {
              const days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
              return days[day - 1];
            },
          ),
          AddStartEndDatePage(
            formKey: _formKeyPage3,
            startDate: _startDate,
            endDate: _endDate,
            onSelectStartDate: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _startDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime(2100),
              );
              if (date != null) {
                setState(() => _startDate = date);
              }
            },
            onSelectEndDate: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _endDate ?? _startDate ?? DateTime.now(),
                firstDate: _startDate ?? DateTime.now(),
                lastDate: DateTime(2100),
              );
              if (date != null) {
                setState(() => _endDate = date);
              }
            },
            onClearEndDate: () => setState(() => _endDate = null),
            onSubmit: _submitForm,
            onBack: _previousPage,
          ),
        ],
      ),
    );
  }
}
