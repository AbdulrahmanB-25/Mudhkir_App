import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mudhkir_app/main.dart'; // Import the notification utility

// --------------------
// Time Utilities
// --------------------
class TimeUtils {
  static TimeOfDay? parseTime(String timeStr) {
    try {
      final DateFormat ampmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      String normalizedTime =
      timeStr.replaceAll('صباحاً', 'AM').replaceAll('مساءً', 'PM').trim();
      final DateFormat arabicAmpmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = arabicAmpmFormat.parseStrict(normalizedTime);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (_) {}
    print("Failed to parse time string: $timeStr");
    return null;
  }

  static String formatTimeOfDay(BuildContext context, TimeOfDay time) {
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }
}

//
// --------------------
// Custom Inline Autocomplete Widget (MedicineAutocomplete)
// --------------------
class MedicineAutocomplete extends StatefulWidget {
  final List<String> suggestions;
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String) onSelected;

  const MedicineAutocomplete({
    Key? key,
    required this.suggestions,
    required this.controller,
    required this.focusNode,
    required this.onSelected,
  }) : super(key: key);

  @override
  _MedicineAutocompleteState createState() => _MedicineAutocompleteState();
}

class _MedicineAutocompleteState extends State<MedicineAutocomplete> {
  List<String> _filteredSuggestions = [];
  final ScrollController _scrollController = ScrollController(); // Add ScrollController

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_filter);
    widget.focusNode.addListener(_handleFocusChange);
    _filter();
  }

  void _filter() {
    final text = widget.controller.text.toLowerCase().trim();
    if (text.isEmpty) {
      setState(() {
        _filteredSuggestions = [];
      });
    } else {
      setState(() {
        _filteredSuggestions = widget.suggestions
            .where((s) => s.toLowerCase().contains(text))
            .take(3) // Limit to 3 suggestions
            .toList();
      });
    }
  }

  void _handleFocusChange() {
    if (!widget.focusNode.hasFocus) {
      setState(() {
        _filteredSuggestions = [];
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_filter);
    widget.focusNode.removeListener(_handleFocusChange);
    _scrollController.dispose(); // Dispose of the ScrollController
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: 'ابحث عن اسم الدواء...',
            prefixIcon: Icon(Icons.search, color: Colors.blue.shade800),
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: Colors.red.shade700),
                    onPressed: () {
                      widget.controller.clear();
                      setState(() {
                        _filteredSuggestions = [];
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.blue.shade800, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          ),
          validator: (value) =>
              (value == null || value.trim().isEmpty) ? 'الرجاء إدخال اسم الدواء' : null,
        ),
        if (_filteredSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            height: _filteredSuggestions.length * 60.0, // Fixed height based on item count
            child: Scrollbar(
              controller: _scrollController, // Attach the ScrollController
              thumbVisibility: true,
              child: ListView.builder(
                controller: _scrollController, // Attach the ScrollController
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: _filteredSuggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _filteredSuggestions[index];
                  return InkWell(
                    onTap: () {
                      widget.onSelected(suggestion);
                      widget.controller.text = suggestion;
                      widget.focusNode.unfocus();
                      setState(() {
                        _filteredSuggestions = [];
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(suggestion, style: const TextStyle(fontSize: 16)),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

//
// --------------------
// AddDose Widget
// --------------------
class AddDose extends StatefulWidget {
  const AddDose({super.key});

  @override
  State<AddDose> createState() => _AddDoseState();
}

class _AddDoseState extends State<AddDose> {
  final String imgbbApiKey = '2b30d3479663bc30a70c916363b07c4a'; // Replace with your actual key

  final PageController _pageController = PageController();
  final GlobalKey<FormState> _formKeyPage1 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyPage2 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyPage3 = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  String _dosageUnit = 'ملغم';
  List<TimeOfDay?> _selectedTimes = [];
  List<bool> _isAutoGeneratedTimes = [];
  String _frequencyType = 'يومي';
  int _frequencyNumber = 1;
  DateTime? _startDate = DateTime.now();
  DateTime? _endDate;
  late Future<List<String>> _medicineNamesFuture;

  File? _capturedImage;
  String? _uploadedImageUrl;

  final List<String> _dosageUnits = ['ملغم', 'غرام', 'مل', 'وحدة'];
  final List<String> _frequencyTypes = ['يومي', 'اسبوعي'];
  final List<int> _frequencyNumbers = [1, 2, 3, 4, 5, 6];

  // For weekly scheduling:
  Map<int, TimeOfDay?> _weeklyTimes = {};
  Map<int, bool> _weeklyAutoGenerated = {};
  Set<int> _selectedWeekdays = {};

  @override
  void initState() {
    super.initState();
    _medicineNamesFuture = _loadMedicineNames();
    _selectedTimes = List.filled(_frequencyNumber, null, growable: true);
    _isAutoGeneratedTimes = List.filled(_frequencyNumber, false, growable: true);
  }

  Future<List<String>> _loadMedicineNames() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/Mediciens/trade_names.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      return List<String>.from(jsonList);
    } catch (e) {
      print('Error loading medicine names: $e');
      return [];
    }
  }

  /// Update daily times and auto-generated flags.
  void _updateTimeFields() {
    setState(() {
      _selectedTimes = List.generate(
          _frequencyNumber,
              (index) =>
          index < _selectedTimes.length ? _selectedTimes[index] : null);
      _isAutoGeneratedTimes = List.generate(
          _frequencyNumber,
              (index) =>
          index < _isAutoGeneratedTimes.length ? _isAutoGeneratedTimes[index] : false);
      if (_frequencyType == 'يومي' && _selectedTimes.isNotEmpty && _selectedTimes[0] != null) {
        _autoFillDosageTimes();
      }
    });
  }

  /// Auto-fill remaining daily dosage times based on the first dose.
  void _autoFillDosageTimes() {
    if (_selectedTimes.isNotEmpty && _selectedTimes[0] != null) {
      final firstDose = _selectedTimes[0]!;
      DateTime base = DateTime(2000, 1, 1, firstDose.hour, firstDose.minute);
      int intervalMinutes = (1440 / _frequencyNumber).round();
      for (int i = 1; i < _frequencyNumber; i++) {
        DateTime newTime = base.add(Duration(minutes: intervalMinutes * i));
        TimeOfDay newTimeOfDay = TimeOfDay(hour: newTime.hour, minute: newTime.minute);
        setState(() {
          _selectedTimes[i] = newTimeOfDay;
          _isAutoGeneratedTimes[i] = true;
        });
      }
    }
  }

  /// Initialize weekly schedule maps for the selected weekdays.
  void _initializeWeeklySchedule() {
    setState(() {
      // Ensure for each selected day, there's an entry.
      for (int day in _selectedWeekdays) {
        if (!_weeklyTimes.containsKey(day)) {
          _weeklyTimes[day] = null;
          _weeklyAutoGenerated[day] = false;
        }
      }
      // Remove any days not selected.
      _weeklyTimes.removeWhere((key, value) => !_selectedWeekdays.contains(key));
      _weeklyAutoGenerated.removeWhere((key, value) => !_selectedWeekdays.contains(key));
    });
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _selectTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimes[index] ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTimes[index] = picked;
        _isAutoGeneratedTimes[index] = false;
        if (index == 0 && _frequencyType == 'يومي') {
          _autoFillDosageTimes();
        }
      });
    }
  }

  Future<void> _selectWeeklyTime(int day) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _weeklyTimes[day] ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _weeklyTimes[day] = picked;
        _weeklyAutoGenerated[day] = false;
        // If this is the first selected day (sorted by day number), auto-fill for the others.
        List<int> sortedDays = _selectedWeekdays.toList()..sort();
        if (sortedDays.isNotEmpty && day == sortedDays.first) {
          for (int otherDay in sortedDays.skip(1)) {
            if (_weeklyTimes[otherDay] == null) {
              _weeklyTimes[otherDay] = picked;
              _weeklyAutoGenerated[otherDay] = true;
            }
          }
        }
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      // Request camera permission before accessing the camera
      final cameraPermission = await Permission.camera.request();
      if (cameraPermission.isDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("يجب السماح بالوصول إلى الكاميرا لالتقاط صورة"))
        );
        return;
      }
      
      final pickedFile = await ImagePicker().pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        setState(() => _capturedImage = File(pickedFile.path));
        _uploadImageToImgBB(_capturedImage!).catchError((e) {
          print("Error initiating image upload: $e");
          _showBlockingAlert("خطأ", "حدث خطأ أثناء بدء تحميل الصورة");
        });
      }
    } catch (e) {
      print("Image picker error: $e");
      _showBlockingAlert("خطأ", "حدث خطأ أثناء التقاط الصورة");
    }
  }

  Future<void> _uploadImageToImgBB(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final url = Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbApiKey');

      final response = await http.post(url, body: {'image': base64Image});
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (mounted) {
          setState(() {
            _uploadedImageUrl = jsonResponse['data']['url'];
          });
        }
        print("Image uploaded to ImgBB: $_uploadedImageUrl");
      } else {
        print("ImgBB upload failed: ${response.body}");
        if (mounted) {
          _showBlockingAlert("خطأ تحميل", "فشل تحميل الصورة. رمز الحالة: ${response.statusCode}");
        }
      }
    } catch (e) {
      print("Error uploading image to ImgBB: $e");
      if (mounted) {
        _showBlockingAlert("خطأ تحميل", "حدث خطأ غير متوقع أثناء تحميل الصورة.");
      }
    }
  }

  void _showBlockingAlert(String title, String message, {VoidCallback? onOk}) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: onOk == null,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text("حسناً"),
              onPressed: () {
                Navigator.of(context).pop();
                if (onOk != null) onOk();
              },
            )
          ],
        );
      },
    );
  }

  Future<void> _submitForm() async {
    if (!_formKeyPage3.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showBlockingAlert("خطأ", "المستخدم غير مسجل الدخول.");
      return;
    }
    if (_capturedImage != null && _uploadedImageUrl == null) {
      _showBlockingAlert("انتظار", "يتم تحميل الصورة حالياً. الرجاء الانتظار لحظات ثم المحاولة مرة أخرى.");
      return;
    }

    dynamic schedule;
    List<Map<String, dynamic>> doseSchedule = [];

    if (_frequencyType == 'اسبوعي') {
      if (_selectedWeekdays.isEmpty || _selectedWeekdays.length > 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرجاء تحديد من 1 إلى 6 أيام')),
        );
        return;
      }
      List<int> sortedDays = _selectedWeekdays.toList()..sort();
      schedule = sortedDays.map((day) {
        final time = _weeklyTimes[day];
        return {
          'day': day,
          'time': time != null ? TimeUtils.formatTimeOfDay(context, time) : ''
        };
      }).toList();
    }

    // Create initial missedDoses array
    List<Map<String, dynamic>> initialMissedDoses = [];
    DateTime now = DateTime.now();

    if (_frequencyType == 'يومي') {
      for (var time in _selectedTimes) {
        if (time != null) {
          DateTime doseTime = DateTime(
            now.year, now.month, now.day, time.hour, time.minute
          );
          initialMissedDoses.add({
            'scheduled': Timestamp.fromDate(doseTime),
            'status': 'pending'
          });
        }
      }
    } else if (_frequencyType == 'اسبوعي') {
      for (var day in _selectedWeekdays) {
        if (_weeklyTimes[day] != null) {
          TimeOfDay time = _weeklyTimes[day]!;
          DateTime doseTime = DateTime(
            now.year, now.month, now.day, time.hour, time.minute
          );
          initialMissedDoses.add({
            'scheduled': Timestamp.fromDate(doseTime),
            'status': 'pending'
          });
        }
      }
    }

    final newMedicine = <String, dynamic>{
      'userId': user.uid,
      'name': _nameController.text.trim(),
      'dosage': '${_dosageController.text.trim()} $_dosageUnit',
      'frequency': '$_frequencyNumber $_frequencyType',
      'times': _frequencyType == 'يومي'
          ? _selectedTimes.map((t) => t?.format(context)).where((t) => t != null).toList()
          : schedule,
      'startDate': _startDate != null ? Timestamp.fromDate(_startDate!) : null,
      'endDate': _endDate != null ? Timestamp.fromDate(_endDate!) : null,
      'createdAt': FieldValue.serverTimestamp(),
      'missedDoses': initialMissedDoses,
      'lastUpdated': Timestamp.now(),
    };

    if (_uploadedImageUrl != null) {
      newMedicine['imageUrl'] = _uploadedImageUrl;
      print("✅ Image URL ready for Firestore: $_uploadedImageUrl");
    }

    try {
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .add(newMedicine);

      // Debug log to confirm dose addition
      print("New medication added with ID: ${docRef.id}");

      // Schedule notifications for the new dose
      int notificationId = docRef.id.hashCode; // Use doc ID hash as notification ID
      if (_frequencyType == 'يومي') {
        for (var time in _selectedTimes) {
          if (time != null) {
            final scheduledTime = DateTime(
              _startDate!.year,
              _startDate!.month,
              _startDate!.day,
              time.hour,
              time.minute,
            );
            if (scheduledTime.isAfter(DateTime.now())) {
              print("Scheduling notification for docId: ${docRef.id}"); // ADDED LOG
              await scheduleNotification(
                id: notificationId++,
                title: 'تذكير الدواء',
                body: 'حان وقت تناول ${_nameController.text.trim()}',
                scheduledTime: scheduledTime,
                docId: docRef.id, // Pass the actual document ID as payload
              );
            }
          }
        }
      }
      // Handle weekly frequency if needed

      _showBlockingAlert("نجاح", "تمت إضافة الدواء بنجاح!", onOk: () {
        if (mounted) Navigator.pop(context, true);
      });
    } catch (e) {
      print("❌ Firestore error: $e");
      _showBlockingAlert("خطأ", "حدث خطأ أثناء إضافة الدواء إلى قاعدة البيانات.");
    }
  }

  String _dayName(int day) {
    switch (day) {
      case 1:
        return "الإثنين";
      case 2:
        return "الثلاثاء";
      case 3:
        return "الأربعاء";
      case 4:
        return "الخميس";
      case 5:
        return "الجمعة";
      case 6:
        return "السبت";
      case 7:
        return "الأحد";
      default:
        return "";
    }
  }

  //
  // --------------------
  // Weekly Schedule Section (Reworked)
  // --------------------
  Widget _buildWeeklyScheduleSection() {
    // Initialize weekly maps if not already initialized.
    _initializeWeeklySchedule();
    // Sort the selected weekdays.
    List<int> sortedDays = _selectedWeekdays.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "جدول الجرعات الأسبوعي",
          style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        // Day selection chips.
        Wrap(
          spacing: 8.0,
          children: List.generate(7, (index) {
            int day = index + 1;
            bool selected = _selectedWeekdays.contains(day);
            return FilterChip(
              label: Text(_dayName(day)),
              selected: selected,
              onSelected: (value) {
                setState(() {
                  if (value) {
                    // Allow selection only if maximum not reached.
                    if (_selectedWeekdays.length < 6) {
                      _selectedWeekdays.add(day);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('يمكنك اختيار 6 أيام فقط')),
                      );
                    }
                  } else {
                    _selectedWeekdays.remove(day);
                    _weeklyTimes.remove(day);
                    _weeklyAutoGenerated.remove(day);
                  }
                });
              },
              selectedColor: Colors.blue.shade300,
              checkmarkColor: Colors.white,
              backgroundColor: Colors.grey.shade200,
            );
          }),
        ),
        if (_selectedWeekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "الرجاء اختيار يوم واحد على الأقل",
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  // Auto fill: If the first sorted day has time, copy to others.
                  if (sortedDays.isNotEmpty && _weeklyTimes[sortedDays.first] != null) {
                    setState(() {
                      for (int day in sortedDays.skip(1)) {
                        _weeklyTimes[day] = _weeklyTimes[sortedDays.first];
                        _weeklyAutoGenerated[day] = true;
                      }
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("حدد وقت اليوم الأول أولاً")));
                  }
                },
                child: const Text("تطبيق نفس الوقت لجميع الأيام"),
              ),
              const SizedBox(height: 10),
              // Display a time picker for each selected day.
              Column(
                children: sortedDays.map((day) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6.0),
                    elevation: 1.0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: Text(
                        _dayName(day),
                        style: const TextStyle(fontSize: 16),
                      ),
                      title: InkWell(
                        onTap: () async {
                          await _selectWeeklyTime(day);
                        },
                        child: Text(
                          _weeklyTimes[day] == null
                              ? "اضغط لاختيار الوقت"
                              : TimeUtils.formatTimeOfDay(context, _weeklyTimes[day]!),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: _weeklyTimes[day] == null ? Colors.grey.shade600 : Colors.black87,
                          ),
                        ),
                      ),
                      trailing: Icon(
                        _weeklyTimes[day] == null
                            ? Icons.edit_calendar_outlined
                            : ((_weeklyAutoGenerated[day] ?? false)
                            ? Icons.smart_toy
                            : Icons.person),
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
      ],
    );
  }

  //
  // --------------------
  // Page 1: Medication Name and Image (with inline autocomplete)
  // --------------------
  Widget _buildMedicationNamePage() {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0;
    return Form(
      key: _formKeyPage1,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        child: Stack(
          children: [
            Positioned(
              top: 15,
              left: -10,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue.shade800, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 50),
                    Text(
                      "إضافة دواء جديد",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: screenWidth * 0.07,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 25.0),
                    _buildImagePicker(screenWidth),
                    const SizedBox(height: 25.0),
                    FutureBuilder<List<String>>(
                      future: _medicineNamesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        } else if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'خطأ في تحميل أسماء الأدوية: ${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                          );
                        } else {
                          final medicineNames = snapshot.data ?? [];
                          return MedicineAutocomplete(
                            suggestions: medicineNames,
                            controller: _nameController,
                            focusNode: FocusNode(),
                            onSelected: (selection) {
                              _nameController.text = selection;
                              FocusScope.of(context).unfocus();
                              debugPrint('Selected: $selection');
                            },
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 30.0),
                    ElevatedButton(
                      onPressed: () {
                        if (_formKeyPage1.currentState!.validate()) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 55),
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      child: const Text('التالي'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  //
  // --------------------
  // Page 2: Dosage and Times
  // --------------------
  Widget _buildDosageAndTimesPage() {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0;
    return Form(
      key: _formKeyPage2,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        child: Stack(
          children: [
            Positioned(
              top: 15,
              left: -10,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue.shade800, size: 28),
                onPressed: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 50),
                    Text(
                      "الجرعة والأوقات",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: screenWidth * 0.07,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 25.0),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.science_outlined, color: Colors.blue.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _dosageController,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                            decoration: InputDecoration(
                              labelText: 'الجرعة',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue.shade800, width: 2.0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'ادخل الجرعة';
                              }
                              if (double.tryParse(value.trim()) == null) {
                                return 'أدخل رقماً صحيحاً';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _dosageUnit,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue.shade800, width: 2.0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (value) {
                              if (value != null) setState(() => _dosageUnit = value);
                            },
                            items: _dosageUnits
                                .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20.0),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Only show frequency number if the frequency type is daily.
                        if (_frequencyType == 'يومي') ...[
                          Icon(Icons.repeat, color: Colors.blue.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _frequencyNumber,
                              decoration: InputDecoration(
                                labelText: 'عدد المرات',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue.shade800, width: 2.0),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _frequencyNumber = value;
                                    _updateTimeFields();
                                  });
                                }
                              },
                              items: _frequencyNumbers
                                  .map((num) => DropdownMenuItem(value: num, child: Text(num.toString())))
                                  .toList(),
                              validator: (value) => value == null ? 'اختر العدد' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        // This widget (and its spacing) always shows, regardless of frequency type.
                        Icon(Icons.calendar_today_outlined, color: Colors.blue.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _frequencyType,
                            decoration: InputDecoration(
                              labelText: 'النوع',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue.shade800, width: 2.0),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _frequencyType = value;
                                  if (value == 'اسبوعي') {
                                    _initializeWeeklySchedule();
                                  } else {
                                    _updateTimeFields();
                                  }
                                });
                              }
                            },
                            items: _frequencyTypes
                                .map((type) =>
                                DropdownMenuItem(value: type, child: Text(type)))
                                .toList(),
                            validator: (value) => value == null ? 'اختر النوع' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25.0),
                    _frequencyType == 'يومي'
                        ? Column(
                      children: [
                        Text(
                          "أوقات تناول الجرعة:",
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _frequencyNumber,
                          itemBuilder: (context, index) {
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6.0),
                              elevation: 1.0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                leading: Icon(Icons.access_time_filled, color: Colors.blue.shade700),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('${index + 1}. ', style: const TextStyle(fontSize: 16)),
                                    Text(
                                      _selectedTimes[index] == null
                                          ? 'اضغط لاختيار الوقت'
                                          : _selectedTimes[index]!.format(context),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: _selectedTimes[index] == null
                                            ? FontWeight.normal
                                            : FontWeight.bold,
                                        color: _selectedTimes[index] == null
                                            ? Colors.grey.shade600
                                            : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    if (_selectedTimes[index] != null)
                                      Icon(
                                        _isAutoGeneratedTimes[index] ? Icons.smart_toy : Icons.person,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                  ],
                                ),
                                trailing: const Icon(Icons.edit_calendar_outlined),
                                onTap: () => _selectTime(index),
                              ),
                            );
                          },
                        ),
                        if (_selectedTimes.any((t) => t == null))
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'الرجاء تحديد جميع الأوقات المطلوبة.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                            ),
                          ),
                      ],
                    )
                        : _buildWeeklyScheduleSection(),
                    const SizedBox(height: 30.0),
                    ElevatedButton(
                      onPressed: () {
                        bool allTimesSelected = _frequencyType == 'يومي'
                            ? !_selectedTimes.any((t) => t == null)
                            : _weeklyTimes.values.every((t) => t != null);
                        if (_formKeyPage2.currentState!.validate() && allTimesSelected) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else if (!allTimesSelected) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('الرجاء تحديد جميع أوقات الجرعات')));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 55),
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      child: const Text('التالي'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  //
  // --------------------
  // Page 3: Start and End Dates
  // --------------------
  Widget _buildStartDateEndDatePage() {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0;
    return Form(
      key: _formKeyPage3,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        child: Stack(
          children: [
            Positioned(
              top: 15,
              left: -10,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue.shade800, size: 28),
                onPressed: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 50),
                    Text(
                      "تاريخ البدء والانتهاء",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: screenWidth * 0.07,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 35.0),
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      elevation: 1.0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: Icon(Icons.calendar_month, color: Colors.blue.shade700),
                        title: Text(
                          _startDate == null
                              ? 'اختر تاريخ البدء (إلزامي)'
                              : "تاريخ البدء: ${_startDate!.day}/${_startDate!.month}/${_startDate!.year}",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _startDate == null ? Colors.grey.shade600 : Colors.black87,
                          ),
                        ),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: _selectStartDate,
                      ),
                    ),
                    FormField<DateTime>(
                      initialValue: _startDate,
                      validator: (value) {
                        if (value == null) {
                          return 'تاريخ البدء مطلوب';
                        }
                        return null;
                      },
                      builder: (FormFieldState<DateTime> state) {
                        return state.hasError
                            ? Padding(
                          padding: const EdgeInsets.only(top: 5.0),
                          child: Text(
                            state.errorText ?? '',
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        )
                            : Container();
                      },
                    ),
                    const SizedBox(height: 15.0),
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      elevation: 1.0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: Icon(Icons.event_busy, color: Colors.orange.shade700),
                        title: Text(
                          _endDate == null
                              ? 'اختر تاريخ الانتهاء (اختياري)'
                              : "تاريخ الانتهاء: ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _endDate == null ? Colors.grey.shade600 : Colors.black87,
                          ),
                        ),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: _selectEndDate,
                      ),
                    ),
                    FormField<DateTime>(
                      initialValue: _endDate,
                      validator: (value) {
                        if (value != null && _startDate != null && value.isBefore(_startDate!)) {
                          return 'تاريخ الانتهاء يجب أن يكون بعد تاريخ البدء';
                        }
                        return null;
                      },
                      builder: (FormFieldState<DateTime> state) {
                        return state.hasError
                            ? Padding(
                          padding: const EdgeInsets.only(top: 5.0),
                          child: Text(
                            state.errorText ?? '',
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        )
                            : Container();
                      },
                    ),
                    const SizedBox(height: 40.0),
                    ElevatedButton(
                      onPressed: _submitForm,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 55),
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      child: const Text('إضافة الدواء إلى خزانتي'),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  //
  // --------------------
  // Image Picker Section
  // --------------------
  Widget _buildImagePicker(double screenWidth) {
    return Center(
      child: GestureDetector(
        onTap: _pickImage,
        child: Container(
          height: screenWidth * 0.45,
          width: screenWidth * 0.7,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(15),
            image: _capturedImage != null
                ? DecorationImage(
              image: FileImage(_capturedImage!),
              fit: BoxFit.cover,
            )
                : null,
          ),
          child: _capturedImage == null
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt_outlined,
                    size: screenWidth * 0.12, color: Colors.blue.shade800),
                const SizedBox(height: 8),
                Text(
                  'اضغط لالتقاط صورة للدواء',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.blue.shade800, fontSize: screenWidth * 0.04),
                ),
              ],
            ),
          )
              : _uploadedImageUrl == null
              ? Center(child: CircularProgressIndicator(color: Colors.white))
              : Container(),
        ),
      ),
    );
  }

  //
  // --------------------
  // Main Build Method (PageView)
  // --------------------
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.white, Colors.grey.shade50],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildMedicationNamePage(),
                _buildDosageAndTimesPage(),
                _buildStartDateEndDatePage(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _pageController.dispose();
    super.dispose();
  }
}

