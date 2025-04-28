import 'dart:convert';

import 'package:flutter/material.dart';
import '../Pages/Add_Medicaiton/Add_Name_Picture.dart';
import '../Pages/Add_Medicaiton/Add_Dosage.dart';
import '../Pages/Add_Medicaiton/Add_Start_&_End_Date.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/companion_medication_tracker.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

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

class _CompanionMedicationsPageState extends State<CompanionMedicationsPage> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  final GlobalKey<FormState> _formKeyPage1 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyPage2 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyPage3 = GlobalKey<FormState>();
  int _currentPageIndex = 0;

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
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedTimes = List.filled(_frequencyNumber, null, growable: true);
    _medicineNamesFuture = _loadMedicineNames();
    
    _animationController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 300)
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn)
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<List<String>> _loadMedicineNames() async {
    try {
      final String jsonString = await DefaultAssetBundle.of(context)
          .loadString('assets/Mediciens/trade_names.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((item) => item.toString()).toList();
    } catch (e) {
      debugPrint('Error loading medicine names: $e');
      return [];
    }
  }

  void _nextPage() {
    if (_pageController.hasClients) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPageIndex++);
    }
  }

  void _previousPage() {
    if (_pageController.hasClients) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPageIndex--);
    }
  }

  void _goToPage(int page) {
    if (page >= 0 && page <= 2 && page != _currentPageIndex) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPageIndex = page);
    }
  }

  Future<void> _submitForm() async {
    if (!_formKeyPage3.currentState!.validate()) return;
    
    setState(() => _isSubmitting = true);

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

      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      debugPrint("Error adding medication: $e");
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showErrorSnackBar("حدث خطأ أثناء إضافة الدواء: $e");
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline,
                color: Colors.green.shade600,
                size: 60,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "تمت إضافة الدواء بنجاح",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "تمت إضافة الدواء ${_nameController.text} بنجاح إلى جدول ${widget.companionName}",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Close medication page
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  "موافق",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: kErrorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(10),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'حسناً',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  String _getDayName(int day) {
    const days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    return days[day - 1];
  }

  Widget _buildProgressBar() {
    final List<String> pageTitles = [
      'اسم الدواء والصورة',
      'الجرعة والأوقات',
      'تاريخ البدء والإنتهاء'
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                      size: 24,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  pageTitles[_currentPageIndex],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  "${_currentPageIndex + 1}/3",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              _buildNavigationButton(
                icon: Icons.arrow_back_ios_rounded,
                onTap: _currentPageIndex > 0 ? _previousPage : null,
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (_currentPageIndex + 1) / 3,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(3, (index) {
                        return GestureDetector(
                          onTap: () => _goToPage(index),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: index <= _currentPageIndex
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.3),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white,
                                  width: 1.5
                              ),
                              boxShadow: index <= _currentPageIndex ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                )
                              ] : null,
                            ),
                            child: index < _currentPageIndex
                                ? Icon(Icons.check, size: 12, color: Color(0xFF2E86C1))
                                : null,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              _buildNavigationButton(
                icon: Icons.arrow_forward_ios_rounded,
                onTap: _currentPageIndex < 2 ? _nextPage : null,
              ),
            ],
          ),

          Container(
            margin: const EdgeInsets.only(top: 8),
            child: Text(
              "الخطوة ${_currentPageIndex + 1} من 3",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNavigationButton({
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final bool isEnabled = onTap != null;
    
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isEnabled ? Colors.white.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isEnabled ? Colors.white : Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            color: isEnabled ? Colors.white : Colors.white.withOpacity(0.3),
            size: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: null,
      body: Stack(
        children: [
          Container(
            height: MediaQuery.of(context).size.height * 0.12,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  _buildProgressBar(),
                  
                  Expanded(
                    child: Stack(
                      children: [
                        PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          onPageChanged: (index) {
                            setState(() => _currentPageIndex = index);
                          },
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
                              dosageUnits: const ['ملغم', 'غرام', 'مل', 'وحدة'],
                              frequencyType: _frequencyType,
                              frequencyTypes: const ['يومي', 'اسبوعي'],
                              frequencyNumber: _frequencyNumber,
                              frequencyNumbers: const [1, 2, 3, 4, 5, 6],
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
                                  builder: (context, child) {
                                    return Theme(
                                      data: ThemeData.light().copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: kPrimaryColor,
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: Colors.black,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (time != null && mounted) {
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
                                  builder: (context, child) {
                                    return Theme(
                                      data: ThemeData.light().copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: kPrimaryColor,
                                          onPrimary: Colors.white,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (time != null && mounted) {
                                  setState(() => _weeklyTimes[day] = time);
                                }
                              },
                              onApplySameTimeToAllWeekdays: () {
                                if (_selectedWeekdays.isNotEmpty) {
                                  final firstDay = _selectedWeekdays.first;
                                  final time = _weeklyTimes[firstDay];
                                  if (time != null && mounted) {
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
                                  bool allTimesValid = true;
                                  
                                  if (_frequencyType == 'يومي' && _selectedTimes.any((t) => t == null)) {
                                    allTimesValid = false;
                                    _showErrorSnackBar("يرجى تحديد جميع أوقات الجرعات");
                                  } else if (_frequencyType == 'اسبوعي') {
                                    if (_selectedWeekdays.isEmpty) {
                                      allTimesValid = false;
                                      _showErrorSnackBar("يرجى اختيار يوم واحد على الأقل من أيام الأسبوع");
                                    } else if (_selectedWeekdays.any((day) => _weeklyTimes[day] == null)) {
                                      allTimesValid = false;
                                      _showErrorSnackBar("يرجى تحديد وقت لكل يوم مختار");
                                    }
                                  }
                                  
                                  if (allTimesValid) {
                                    _nextPage();
                                  }
                                }
                              },
                              onBack: _previousPage,
                              getDayName: _getDayName,
                            ),
                            
                            AddStartEndDatePage(
                              formKey: _formKeyPage3,
                              startDate: _startDate,
                              endDate: _endDate,
                              onSelectStartDate: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _startDate ?? DateTime.now(),
                                  firstDate: DateTime.now().subtract(const Duration(days: 7)),
                                  lastDate: DateTime(2100),
                                  builder: (context, child) {
                                    return Theme(
                                      data: ThemeData.light().copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: kPrimaryColor,
                                          onPrimary: Colors.white,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (date != null && mounted) {
                                  setState(() => _startDate = date);
                                }
                              },
                              onSelectEndDate: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _endDate ?? _startDate ?? DateTime.now(),
                                  firstDate: _startDate ?? DateTime.now(),
                                  lastDate: DateTime(2100),
                                  builder: (context, child) {
                                    return Theme(
                                      data: ThemeData.light().copyWith(
                                        colorScheme: const ColorScheme.light(
                                          primary: kPrimaryColor,
                                          onPrimary: Colors.white,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (date != null && mounted) {
                                  setState(() => _endDate = date);
                                }
                              },
                              onClearEndDate: () => setState(() => _endDate = null),
                              onSubmit: _submitForm,
                              onBack: _previousPage,
                            ),
                          ],
                        ),
                        
                        if (_isSubmitting)
                          Container(
                            color: Colors.black.withOpacity(0.3),
                            child: Center(
                              child: Card(
                                elevation: 6,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(
                                        color: kPrimaryColor,
                                        strokeWidth: 3,
                                      ),
                                      const SizedBox(height: 20),
                                      const Text(
                                        "جاري إضافة الدواء...",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

