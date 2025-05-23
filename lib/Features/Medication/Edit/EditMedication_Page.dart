import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../../Core/Services/AlarmNotificationHelper.dart';
import '../Add/Add_Dosage.dart' show AddDosagePage;
import '../Add/Add_Name_Picture.dart';
import '../Add/Add_Start_&_End_Date.dart' show AddStartEndDatePage;

class TimeUtils {
  // Handles time parsing with Arabic AM/PM normalization and formatting
  static final DateFormat _timeFormat = DateFormat('h:mm a', 'ar');
  static final DateFormat _parsingFormat = DateFormat('h:mm a', 'en_US');

  static TimeOfDay? parseTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      String normalizedTime = timeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('مساءً', 'PM')
          .replaceAll('ص', 'AM')
          .replaceAll('م', 'PM')
          .trim();
      DateTime parsedDt = _parsingFormat.parseStrict(normalizedTime);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (e) {
      try {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          int hour = int.parse(parts[0]);
          int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
          if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
            return TimeOfDay(hour: hour, minute: minute);
          }
        }
      } catch (_) {}
      print("TimeUtils: Failed to parse time string '$timeStr' with any known format.");
      return null;
    }
  }

  // Formats TimeOfDay into Arabic AM/PM for database storage
  static String formatTimeOfDay(TimeOfDay t) {
    final dt = DateTime(2000, 1, 1, t.hour, t.minute);
    String formatted = _timeFormat.format(dt);
    formatted = formatted
        .replaceAll('AM', 'صباحاً')
        .replaceAll('PM', 'مساءً')
        .replaceAll('ص', 'صباحاً')
        .replaceAll('م', 'مساءً');
    return formatted;
  }
}

class EditMedicationUtils {
  // Ensures camera permission is granted, opens app settings if denied
  static Future<void> ensureCameraPermission() async {
    final st = await Permission.camera.request();
    if (!st.isGranted) {
      if (st.isPermanentlyDenied) {
        await openAppSettings();
      }
      throw Exception('Camera permission denied');
    }
  }

  // Uploads an image to ImgBB and returns the image URL and delete hash
  static Future<Map<String, String>> uploadToImgBB(File file, String apiKey) async {
    if (apiKey.isEmpty || apiKey == 'YOUR_IMGBB_API_KEY') {
      throw Exception('ImgBB API Key is not configured.');
    }
    final b64 = base64Encode(await file.readAsBytes());
    final uri = Uri.parse('https://api.imgbb.com/1/upload?key=$apiKey');
    final resp = await http.post(uri, body: {'image': b64});

    if (resp.statusCode == 200) {
      final jsonResponse = json.decode(resp.body);
      if (jsonResponse['success'] == true && jsonResponse['data'] != null) {
        final data = jsonResponse['data'];
        final imageUrl = data['url'] as String?;
        final deleteUrl = data['delete_url'] as String?;
        if (imageUrl != null && deleteUrl != null) {
          final deleteHash = deleteUrl.substring(deleteUrl.lastIndexOf('/') + 1);
          return {'url': imageUrl, 'delete_hash': deleteHash};
        }
      }
    }
    print("ImgBB Upload Failed - Status: ${resp.statusCode}, Body: ${resp.body}");
    throw Exception('ImgBB upload failed');
  }

  // Deletes an image from ImgBB using the delete hash
  static Future<void> deleteImgBBImage(String deleteHash, String apiKey) async {
    if (apiKey.isEmpty || apiKey == 'YOUR_IMGBB_API_KEY' || deleteHash.isEmpty) {
      print("ImgBB delete skipped: API Key or delete hash missing.");
      return;
    }
    final url = Uri.parse('https://api.imgbb.com/1/image/$deleteHash');
    try {
      final response = await http.post(url, body: {'key': apiKey});
      if (response.statusCode == 200) {
        print("ImgBB image deletion successful: $deleteHash");
      } else {
        print("Failed to delete ImgBB image ($deleteHash): ${response.statusCode}, ${response.body}");
      }
    } catch (e) {
      print("Error deleting ImgBB image ($deleteHash): $e");
    }
  }
}

class EditMedicationDataProvider {
  final TextEditingController nameController;
  final TextEditingController dosageController;
  final PageController pageController = PageController();
  final String imgbbApiKey;
  final String? companionId;

  bool _isLoading = true;
  File? _capturedImage;
  String? _uploadedImageUrl;
  String? _originalImageUrl;
  String? _imgbbDeleteHash;
  String? _originalImgbbDeleteHash;
  bool _isUploading = false;
  bool _hasOriginalImage = false;

  List<String> _medicineNames = [];
  String _dosageUnit = 'ملغم';
  String _frequencyType = 'يومي';
  int _frequencyNumber = 1;

  List<TimeOfDay?> _selectedTimes = [];
  List<bool> _isAutoGeneratedTimes = [];

  Set<int> _selectedWeekdays = {};
  Map<int, TimeOfDay?> _weeklyTimes = {};
  Map<int, bool> _weeklyAutoGenerated = {};

  DateTime? _startDate;
  DateTime? _endDate;

  List<int> _originalNotificationIds = [];

  bool get isLoading => _isLoading;
  File? get capturedImage => _capturedImage;
  String? get displayImageUrl => _capturedImage != null ? null : (_uploadedImageUrl ?? _originalImageUrl);
  bool get isUploading => _isUploading;
  List<String> get medicineNames => _medicineNames;
  String get dosageUnit => _dosageUnit;
  String get frequencyType => _frequencyType;
  int get frequencyNumber => _frequencyNumber;
  List<TimeOfDay?> get selectedTimes => _selectedTimes;
  List<bool> get isAutoGeneratedTimes => _isAutoGeneratedTimes;
  Set<int> get selectedWeekdays => _selectedWeekdays;
  Map<int, TimeOfDay?> get weeklyTimes => _weeklyTimes;
  Map<int, bool> get weeklyAutoGenerated => _weeklyAutoGenerated;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;

  EditMedicationDataProvider({
    required this.nameController,
    required this.dosageController,
    required this.imgbbApiKey,
    this.companionId,
  });

  // Initializes the provider by loading medicine names and medication data
  Future<void> init(String docId) async {
    _isLoading = true;
    try {
      await _loadMedicineNames();
      await loadMedicationData(docId);
    } catch (e) {
      print("Error during init: $e");
    } finally {
      _isLoading = false;
    }
  }

  void dispose() {
    nameController.dispose();
    dosageController.dispose();
    pageController.dispose();
  }

  Future<void> _loadMedicineNames() async {
    try {
      final raw = await rootBundle.loadString('assets/Mediciens/trade_names.json');
      final list = json.decode(raw) as List<dynamic>;
      _medicineNames = list.map((e) => e.toString()).toList();
    } catch (e) {
      print("Error loading medicine names: $e");
      _medicineNames = [];
    }
  }

  // Loads medication data from Firestore and parses it into the provider's state
  Future<void> loadMedicationData(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not logged in');

    final ownerId = companionId ?? user.uid;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(ownerId)
        .collection('medicines')
        .doc(docId);

    try {
      final doc = await docRef.get();
      if (!doc.exists) throw Exception('Medicine document $docId not found');

      final data = doc.data()!;
      print("Raw Firestore data: $data");

      nameController.text = data['name'] ?? '';
      _parseDosage(data['dosage'] as String?);
      _startDate = (data['startDate'] as Timestamp?)?.toDate();
      _endDate = (data['endDate'] as Timestamp?)?.toDate();
      _originalImageUrl = data['imageUrl'] as String?;
      _originalImgbbDeleteHash = data['imgbbDeleteHash'] as String?;
      _hasOriginalImage = _originalImageUrl != null && _originalImageUrl!.isNotEmpty;
      _uploadedImageUrl = _originalImageUrl;
      _imgbbDeleteHash = _originalImgbbDeleteHash;

      _originalNotificationIds = List<int>.from(data['notificationIds'] ?? []);

      _frequencyType = 'يومي';
      if (data.containsKey('frequencyType') && data['frequencyType'] == 'اسبوعي') {
        _frequencyType = 'اسبوعي';
      } else if (data.containsKey('frequency')) {
        final String frequencyRaw = data['frequency'] as String? ?? '';
        final List<String> frequencyParts = frequencyRaw.split(" ");
        if (frequencyParts.length > 1 && frequencyParts[1] == 'اسبوعي') {
          _frequencyType = 'اسبوعي';
        }
      }

      final timesList = data['times'] as List<dynamic>? ?? [];
      print("Raw times data: $timesList");

      if (_frequencyType == 'يومي') {
        _frequencyNumber = (data['frequencyDetails']?['timesPerDay'] as int?) ?? 1;
        _loadDailyTimes(timesList);
      } else if (_frequencyType == 'اسبوعي') {
        final freqDetails = data['frequencyDetails'] as Map<String, dynamic>?;
        _loadWeeklyTimesAndDays(timesList, freqDetails);
      } else {
        _frequencyType = 'يومي';
        _frequencyNumber = 1;
        _loadDailyTimes(timesList);
      }

      _updateTimeFields();
      _initializeWeeklySchedule();

      print("Finished loading. StartDate: $_startDate, FreqType: $_frequencyType, DailyTimes: $_selectedTimes, WeeklyTimes: $_weeklyTimes");

    } catch (e, stackTrace) {
      print("Error loading medication data for docId $docId: $e");
      print(stackTrace);
      throw Exception('Failed to load medication data: $e');
    }
  }

  void _parseDosage(String? dosage) {
    if (dosage == null || dosage.isEmpty) {
      dosageController.text = '';
      _dosageUnit = 'ملغم';
      return;
    }
    final parts = dosage.trim().split(' ');
    if (parts.length >= 2) {
      dosageController.text = parts[0];
      _dosageUnit = parts.sublist(1).join(' ');
    } else {
      dosageController.text = dosage.trim();
      _dosageUnit = 'ملغم';
    }
  }

  void _loadDailyTimes(List<dynamic> timesList) {
    _selectedTimes = List<TimeOfDay?>.filled(_frequencyNumber, null, growable: true);
    _isAutoGeneratedTimes = List<bool>.filled(_frequencyNumber, false, growable: true);
    for (var i = 0; i < timesList.length && i < _frequencyNumber; i++) {
      if (timesList[i] is String) {
        final parsedTime = TimeUtils.parseTime(timesList[i] as String);
        if (parsedTime != null) {
          _selectedTimes[i] = parsedTime;
          _isAutoGeneratedTimes[i] = false;
        }
      }
    }
    print("Loaded Daily Times: $_selectedTimes");
  }

  void _loadWeeklyTimesAndDays(List<dynamic> timesList, Map<String, dynamic>? freqDetails) {
    final daysRaw = freqDetails?['selectedWeekdays'] as List<dynamic>? ?? [];
    _selectedWeekdays = daysRaw.map((day) {
      if (day is int && day >= 1 && day <= 7) return day;
      if (day is String) {
        final p = int.tryParse(day);
        if (p != null && p >= 1 && p <= 7) return p;
      }
      return null;
    }).whereType<int>().toSet();

    _weeklyTimes = {};
    _weeklyAutoGenerated = {};

    for (var item in timesList) {
      if (item is Map) {
        final day = item['day'];
        final timeStr = item['time'] as String?;
        int? dayValue;
        if (day is int && day >= 1 && day <= 7) dayValue = day;
        else if (day is String) dayValue = int.tryParse(day);
        else if (day is double) dayValue = day.toInt();

        if (dayValue != null && _selectedWeekdays.contains(dayValue) && timeStr != null) {
          final parsedTime = TimeUtils.parseTime(timeStr);
          if (parsedTime != null) {
            _weeklyTimes[dayValue] = parsedTime;
            _weeklyAutoGenerated[dayValue] = false;
          }
        }
      }
    }
    print("Loaded Selected Weekdays: $_selectedWeekdays");
    print("Loaded Weekly Times: $_weeklyTimes");

    for (int day in _selectedWeekdays) {
      _weeklyTimes.putIfAbsent(day, () => null);
      _weeklyAutoGenerated.putIfAbsent(day, () => true);
    }
  }

  Future<void> pickImage() async {
    try {
      await EditMedicationUtils.ensureCameraPermission();
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);
      if (pickedFile == null) return;

      _capturedImage = File(pickedFile.path);
      _isUploading = true;

      final uploadResult = await EditMedicationUtils.uploadToImgBB(_capturedImage!, imgbbApiKey);
      _uploadedImageUrl = uploadResult['url'];
      _imgbbDeleteHash = uploadResult['delete_hash'];

      print("Image uploaded successfully: URL=$_uploadedImageUrl");
      _isUploading = false;
      _capturedImage = null;

    } catch (e) {
      print("Error picking/uploading image: $e");
      _isUploading = false;
      _capturedImage = null;
    }
  }

  // Updates medication data in Firestore and schedules notifications
  Future<void> updateMedication(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not logged in');

    final ownerId = companionId ?? user.uid;

    if (nameController.text.trim().isEmpty) throw Exception('Medication name cannot be empty.');
    if (dosageController.text.trim().isEmpty) throw Exception('Dosage value cannot be empty.');
    if (_startDate == null) throw Exception('Start date must be selected.');

    if (_frequencyType == 'يومي' && _selectedTimes.any((t) => t == null)) {
      throw Exception('Please select all required daily times.');
    }
    if (_frequencyType == 'اسبوعي' && (_selectedWeekdays.isEmpty || _weeklyTimes.entries.any((e) => !_selectedWeekdays.contains(e.key) || e.value == null))) {
      throw Exception('Please select at least one weekday and set the time for all selected weekdays.');
    }

    if (_uploadedImageUrl != _originalImageUrl && _originalImgbbDeleteHash != null && _originalImgbbDeleteHash!.isNotEmpty) {
      print("Image changed, attempting to delete old image...");
      await EditMedicationUtils.deleteImgBBImage(_originalImgbbDeleteHash!, imgbbApiKey);
    } else {
      print("Image not changed or no original hash, skipping deletion.");
    }

    final Map<String, dynamic> frequencyDetailsData;
    final List<dynamic> timesData;

    if (_frequencyType == 'يومي') {
      frequencyDetailsData = {'timesPerDay': _frequencyNumber};
      timesData = _selectedTimes.where((t) => t != null).map((t) => TimeUtils.formatTimeOfDay(t!)).toList();
    } else {
      frequencyDetailsData = {'selectedWeekdays': _selectedWeekdays.toList()..sort()};
      timesData = _weeklyTimes.entries
          .where((entry) => entry.value != null && _selectedWeekdays.contains(entry.key))
          .map((entry) => {'day': entry.key, 'time': TimeUtils.formatTimeOfDay(entry.value!)})
          .toList();
      timesData.sort((a, b) => (a['day'] as int).compareTo(b['day'] as int));
    }

    final updatedData = <String, dynamic>{
      'name': nameController.text.trim(),
      'dosage': '${dosageController.text.trim()} $_dosageUnit'.trim(),
      'frequencyType': _frequencyType,
      'frequencyDetails': frequencyDetailsData,
      'times': timesData,
      'startDate': _startDate != null ? Timestamp.fromDate(_startDate!) : null,
      'endDate': _endDate != null ? Timestamp.fromDate(_endDate!) : null,
      'imageUrl': _uploadedImageUrl,
      'imgbbDeleteHash': _imgbbDeleteHash,
      'lastUpdated': Timestamp.now(),
    };

    updatedData.removeWhere((key, value) => value == null && key != 'endDate' && key != 'imageUrl' && key != 'imgbbDeleteHash');

    print("Updating Firestore document $docId with data: $updatedData");

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerId)
          .collection('medicines')
          .doc(docId)
          .update(updatedData);
      print("Firestore update successful.");

      // Schedule all medications after editing
      await AlarmNotificationHelper.scheduleAllUserMedications(ownerId);
    } catch (e, stackTrace) {
      print("Error updating Firestore: $e");
      print(stackTrace);
      throw Exception('Failed to save medication changes: $e');
    }
  }

  void updateDosageUnit(String unit) => _dosageUnit = unit;

  void updateFrequencyType(String type) {
    if (_frequencyType == type) return;
    _frequencyType = type;
    _updateTimeFields();
    _initializeWeeklySchedule();
  }

  void updateFrequencyNumber(int number) {
    if (_frequencyNumber == number || _frequencyType != 'يومي') return;
    _frequencyNumber = number;
    _updateTimeFields();
  }

  void selectDailyTime(int index, TimeOfDay time) {
    if (_frequencyType == 'يومي' && index >= 0 && index < _selectedTimes.length) {
      _selectedTimes[index] = time;
      _isAutoGeneratedTimes[index] = false;
      if (index == 0) _autoFillDosageTimes();
    }
  }

  void toggleWeekday(int day, bool isSelected) {
    if (_frequencyType != 'اسبوعي') return;
    if (isSelected) {
      _selectedWeekdays.add(day);
    } else {
      _selectedWeekdays.remove(day);
    }
    _initializeWeeklySchedule();
  }

  void selectWeeklyTime(int day, TimeOfDay time) {
    if (_frequencyType == 'اسبوعي' && _selectedWeekdays.contains(day)) {
      _weeklyTimes[day] = time;
      _weeklyAutoGenerated[day] = false;
    }
  }

  void updateStartDate(DateTime d) => _startDate = d;
  void updateEndDate(DateTime? d) => _endDate = d;

  void _updateTimeFields() {
    if (_frequencyType != 'يومي') return;
    final oldTimes = List<TimeOfDay?>.from(_selectedTimes);
    final oldAuto = List<bool>.from(_isAutoGeneratedTimes);
    _selectedTimes = List.generate(_frequencyNumber, (i) => i < oldTimes.length ? oldTimes[i] : null, growable: true);
    _isAutoGeneratedTimes = List.generate(_frequencyNumber, (i) => i < oldAuto.length ? oldAuto[i] : false, growable: true);
    if (_selectedTimes.isNotEmpty && _selectedTimes[0] != null) _autoFillDosageTimes();
  }

  // Automatically fills daily dosage times based on the first time
  void _autoFillDosageTimes() {
    if (_frequencyType != 'يومي' || _selectedTimes.isEmpty || _selectedTimes[0] == null || _frequencyNumber <= 1) return;
    final firstTime = _selectedTimes[0]!;
    final baseDateTime = DateTime(2000, 1, 1, firstTime.hour, firstTime.minute);
    final intervalMinutes = (24 * 60 / _frequencyNumber).round();
    for (var i = 1; i < _frequencyNumber; i++) {
      if (_selectedTimes[i] == null || (i < _isAutoGeneratedTimes.length && _isAutoGeneratedTimes[i])) {
        final nextDateTime = baseDateTime.add(Duration(minutes: intervalMinutes * i));
        _selectedTimes[i] = TimeOfDay(hour: nextDateTime.hour, minute: nextDateTime.minute);
        if (i < _isAutoGeneratedTimes.length) _isAutoGeneratedTimes[i] = true;
      }
    }
  }

  // Initializes weekly schedule by syncing selected weekdays and times
  void _initializeWeeklySchedule() {
    if (_frequencyType != 'اسبوعي') return;
    final currentTimes = Map<int, TimeOfDay?>.from(_weeklyTimes);
    final currentAuto = Map<int, bool>.from(_weeklyAutoGenerated);
    _weeklyTimes = {};
    _weeklyAutoGenerated = {};
    for (var day in _selectedWeekdays) {
      _weeklyTimes[day] = currentTimes[day];
      _weeklyAutoGenerated[day] = currentAuto[day] ?? (_weeklyTimes[day] == null);
    }
  }

  // Applies the same time to all selected weekdays
  void applySameTimeToAllWeekdays() {
    if (_frequencyType != 'اسبوعي' || _selectedWeekdays.isEmpty) return;
    final sortedDays = _selectedWeekdays.toList()..sort();
    final firstDayTime = _weeklyTimes[sortedDays.first];
    if (firstDayTime != null) {
      for (var day in sortedDays) {
        if (day != sortedDays.first) {
          _weeklyTimes[day] = firstDayTime;
          _weeklyAutoGenerated[day] = false;
        }
      }
    }
  }
}

class EditMedicationScreen extends StatefulWidget {
  final String docId;
  final String? companionId;
  final VoidCallback? onSave;
  final String? buttonText;

  const EditMedicationScreen({
    Key? key,
    required this.docId,
    this.companionId,
    this.onSave,
    this.buttonText,
  }) : super(key: key);

  @override
  _EditMedicationScreenState createState() => _EditMedicationScreenState();
}

class _EditMedicationScreenState extends State<EditMedicationScreen> {
  late final EditMedicationDataProvider dp;
  final GlobalKey<FormState> _page1FormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _page2FormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _page3FormKey = GlobalKey<FormState>();
  int _currentPageIndex = 0;

  bool _isPage1Valid = false;
  bool _isPage2Valid = false;

  @override
  void initState() {
    super.initState();
    dp = EditMedicationDataProvider(
      nameController: TextEditingController(),
      dosageController: TextEditingController(),
      imgbbApiKey: '2b30d3479663bc30a70c916363b07c4a',
      companionId: widget.companionId,
    );
    _initializeData();
  }

  void _initializeData() async {
    await dp.init(widget.docId);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    dp.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  // Validates the first page of the form
  bool _validatePage1() {
    if (_page1FormKey.currentState == null) return false;
    final isValid = _page1FormKey.currentState!.validate();
    setState(() => _isPage1Valid = isValid);
    return isValid;
  }

  // Validates the second page of the form, including time selection
  bool _validatePage2() {
    if (_page2FormKey.currentState == null) return false;
    final isFormValid = _page2FormKey.currentState!.validate();

    bool allTimesValid = false;
    if (dp.frequencyType == 'يومي') {
      allTimesValid = !dp.selectedTimes.any((t) => t == null);
    } else {
      allTimesValid = dp.selectedWeekdays.isNotEmpty &&
          dp.selectedWeekdays.every((day) => dp.weeklyTimes[day] != null);
    }

    final isValid = isFormValid && allTimesValid;
    setState(() => _isPage2Valid = isValid);
    return isValid;
  }

  void _nextPage() {
    if (_currentPageIndex < 2) {
      bool canProceed = false;

      if (_currentPageIndex == 0) {
        canProceed = _validatePage1();
      } else if (_currentPageIndex == 1) {
        canProceed = _validatePage2();
      }

      if (canProceed) {
        dp.pageController.nextPage(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        setState(() => _currentPageIndex++);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("الرجاء إكمال جميع الحقول المطلوبة"),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  void _previousPage() {
    if (_currentPageIndex > 0) {
      dp.pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() => _currentPageIndex--);
    }
  }

  void _goToPage(int page) {
    if (page >= 0 && page <= 2 && page != _currentPageIndex) {
      bool canProceed = true;

      if (page > _currentPageIndex) {
        if (_currentPageIndex == 0) {
          canProceed = _validatePage1();
        } else if (_currentPageIndex == 1 && page == 2) {
          canProceed = _validatePage2();
        }
      }

      if (canProceed) {
        dp.pageController.animateToPage(
          page,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        setState(() => _currentPageIndex = page);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("الرجاء إكمال الخطوة الحالية أولا"),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  // Submits the form and updates the medication in Firestore
  void _submitForm() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await dp.updateMedication(widget.docId);
      widget.onSave?.call();
      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("تم تحديث الدواء بنجاح"),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _showErrorSnackBar("فشل حفظ التغييرات: ${e.toString()}");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dp.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('تعديل الدواء')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Column(
        children: [
          _buildProgressBar(),
          Expanded(
            child: PageView(
              controller: dp.pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _currentPageIndex = index);
              },
              children: [
                AddNamePicturePage(
                  formKey: _page1FormKey,
                  nameController: dp.nameController,
                  medicineNamesFuture: Future.value(dp.medicineNames),
                  capturedImage: dp.capturedImage,
                  uploadedImageUrl: dp.displayImageUrl,
                  onPickImage: () async {
                    await dp.pickImage();
                    if (mounted) setState(() {});
                  },
                  onNext: _nextPage,
                  onBack: () => Navigator.pop(context),
                ),
                AddDosagePage(
                  formKey: _page2FormKey,
                  dosageController: dp.dosageController,
                  dosageUnit: dp.dosageUnit,
                  dosageUnits: const ['ملغم', 'غرام', 'مل', 'وحدة'],
                  frequencyType: dp.frequencyType,
                  frequencyTypes: const ['يومي', 'اسبوعي'],
                  frequencyNumber: dp.frequencyNumber,
                  frequencyNumbers: const [1, 2, 3, 4, 5, 6],
                  selectedTimes: dp.selectedTimes,
                  isAutoGeneratedTimes: dp.isAutoGeneratedTimes,
                  selectedWeekdays: dp.selectedWeekdays,
                  weeklyTimes: dp.weeklyTimes,
                  weeklyAutoGenerated: dp.weeklyAutoGenerated,
                  onDosageUnitChanged: (v) => setState(() => dp.updateDosageUnit(v!)),
                  onFrequencyTypeChanged: (v) => setState(() => dp.updateFrequencyType(v!)),
                  onFrequencyNumberChanged: (v) => setState(() => dp.updateFrequencyNumber(v!)),
                  onSelectTime: (index) async {
                    final initialTime = dp.selectedTimes.length > index && dp.selectedTimes[index] != null
                        ? dp.selectedTimes[index]!
                        : TimeOfDay.now();
                    final t = await showTimePicker(context: context, initialTime: initialTime);
                    if (t != null) setState(() => dp.selectDailyTime(index, t));
                  },
                  onWeekdaySelected: (day, isSelected) => setState(() => dp.toggleWeekday(day, isSelected)),
                  onSelectWeeklyTime: (day) async {
                    final initialTime = dp.weeklyTimes[day] ?? TimeOfDay.now();
                    final t = await showTimePicker(context: context, initialTime: initialTime);
                    if (t != null) setState(() => dp.selectWeeklyTime(day, t));
                  },
                  onApplySameTimeToAllWeekdays: () => setState(() => dp.applySameTimeToAllWeekdays()),
                  onNext: _nextPage,
                  onBack: _previousPage,
                  getDayName: (d) => ['','الإثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'][d],
                ),
                AddStartEndDatePage(
                  formKey: _page3FormKey,
                  startDate: dp.startDate,
                  endDate: dp.endDate,
                  onSelectStartDate: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: dp.startDate ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (d != null) setState(() => dp.updateStartDate(d));
                  },
                  onSelectEndDate: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: dp.endDate ?? dp.startDate ?? DateTime.now(),
                      firstDate: dp.startDate ?? DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (d != null) setState(() => dp.updateEndDate(d));
                  },
                  onClearEndDate: () => setState(() => dp.updateEndDate(null)),
                  onSubmit: _submitForm,
                  onBack: _previousPage,
                  submitButtonText: widget.buttonText ?? 'تعديل الدواء',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Builds the progress bar with navigation between pages
  Widget _buildProgressBar() {
    final List<String> pageTitles = [
      'اسم الدواء والصورة',
      'الجرعة والأوقات',
      'تاريخ البدء والإنتهاء'
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E86C1), Color(0xFF2E86C1).withOpacity(0.8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(10, MediaQuery.of(context).padding.top, 10, 18), // More bottom padding
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.all(10.0), // Larger padding
                    child: Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 28, // Larger icon
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
                    fontSize: 20, // Larger font
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Larger padding
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  "${_currentPageIndex + 1}/3",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16, // Larger font
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16), // More space
          Row(
            children: [
              _buildNavigationButton(
                icon: Icons.arrow_back_ios_rounded,
                onTap: _currentPageIndex > 0 ? _previousPage : null,
              ),
              const SizedBox(width: 14), // More space
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 8, // Increased from 6
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (_currentPageIndex + 1) / 3,
                        child: Container(
                          height: 8, // Increased from 6
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(3, (index) {
                        bool canAccess = index <= _currentPageIndex || 
                            (index == 1 && _isPage1Valid) ||
                            (index == 2 && _isPage1Valid && _isPage2Valid);
                            
                        return GestureDetector(
                          onTap: canAccess ? () => _goToPage(index) : null,
                          child: Container(
                            width: 24, // Increased from 18
                            height: 24, // Increased from 18
                            decoration: BoxDecoration(
                              color: index <= _currentPageIndex
                                  ? Colors.white
                                  : canAccess 
                                      ? Colors.white.withOpacity(0.5)
                                      : Colors.white.withOpacity(0.3),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: canAccess ? Colors.white : Colors.white.withOpacity(0.5),
                                width: 2.0 // Increased from 1.5
                              ),
                            ),
                            child: index < _currentPageIndex
                                ? Icon(Icons.check, size: 14, color: Color(0xFF2E86C1)) // Increased from 10
                                : null,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14), // More space
              _buildNavigationButton(
                icon: Icons.arrow_forward_ios_rounded,
                onTap: _currentPageIndex < 2 
                    ? (_currentPageIndex == 0 && !_isPage1Valid) || (_currentPageIndex == 1 && !_isPage2Valid)
                        ? null 
                        : _nextPage
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 10), // More space at bottom
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
          width: 40, // Increased from 32
          height: 40, // Increased from 32
          decoration: BoxDecoration(
            color: isEnabled ? Colors.white.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isEnabled ? Colors.white : Colors.white.withOpacity(0.2),
              width: 2.0, // Increased from 1.5
            ),
          ),
          child: Icon(
            icon,
            color: isEnabled ? Colors.white : Colors.white.withOpacity(0.3),
            size: 20, // Increased from 16
          ),
        ),
      ),
    );
  }
}
