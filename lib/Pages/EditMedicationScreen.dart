import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// --- Time Utilities ---
class TimeUtils {
  static TimeOfDay? parseTime(String timeStr) {
    try {
      final intl.DateFormat ampmFormat = intl.DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      String normalizedTime = timeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('مساءً', 'PM')
          .trim();
      final intl.DateFormat arabicAmpmFormat = intl.DateFormat('h:mm a', 'en_US');
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

// --- EnlargeableImage Widget (Keep here or import if defined separately) ---
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

  @override
  void didUpdateWidget(covariant EnlargeableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _imageFileFuture = _downloadAndSaveImage(widget.imageUrl);
    }
  }

  Future<File?> _downloadAndSaveImage(String url) async {
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.isAbsolute) {
      print("Invalid or empty URL for download: $url");
      return null;
    }
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final Directory directory = await getTemporaryDirectory();
        final String filePath = '${directory.path}/${url.hashCode}.png';
        File file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return file;
      } else {
        print("Failed to download image ($url). Status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error downloading image ($url): $e");
    }
    return null;
  }

  void _openEnlargedImage(BuildContext context, File imageFile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) {
          return Scaffold(
            backgroundColor: Colors.black87,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: Center(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(imageFile),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.imageUrl);
    if (widget.imageUrl.isEmpty || uri == null || !uri.isAbsolute) {
      return _buildPlaceholder(showErrorText: false);
    }
    return FutureBuilder<File?>(
      future: _imageFileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        } else if (snapshot.hasData && snapshot.data != null) {
          return GestureDetector(
            onTap: () => _openEnlargedImage(context, snapshot.data!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                snapshot.data!,
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  print("Error displaying file image: $error");
                  return _buildPlaceholder(showErrorText: true);
                },
              ),
            ),
          );
        } else {
          return _buildPlaceholder(showErrorText: true);
        }
      },
    );
  }

  Widget _buildPlaceholder({required bool showErrorText}) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(
        showErrorText ? Icons.broken_image : Icons.image_not_supported,
        color: Colors.grey.shade600,
        size: widget.width * 0.6,
      ),
    );
  }
}

/// ----------------------
/// EditMedicationScreen Widget
/// ----------------------
class EditMedicationScreen extends StatefulWidget {
  final String docId;

  const EditMedicationScreen({super.key, required this.docId});

  @override
  _EditMedicationScreenState createState() => _EditMedicationScreenState();
}

class _EditMedicationScreenState extends State<EditMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // Form state variables
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  List<TimeOfDay> _selectedTimes = [];
  String _selectedFrequency = 'يومي';
  Set<int> _selectedWeekdays = {};
  String? _currentImageUrl;
  String? _currentImgbbDeleteHash;
  File? _newImageFile;
  bool _imageRemoved = false;

  User? _user;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = "المستخدم غير مسجل الدخول.";
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      });
    } else {
      _loadMedicationData();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // --- Load Data from Firestore ---
  Future<void> _loadMedicationData() async {
    if (_user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "خطأ: المستخدم غير متوفر.";
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('medicines')
          .doc(widget.docId)
          .get();

      if (!mounted) return;

      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;
        _nameController.text = data['name'] as String? ?? '';
        _selectedStartDate = (data['startDate'] as Timestamp?)?.toDate();
        _selectedEndDate = (data['endDate'] as Timestamp?)?.toDate();
        _selectedTimes = (data['times'] as List<dynamic>? ?? [])
            .map((t) => t != null ? TimeUtils.parseTime(t.toString()) : null)
            .whereType<TimeOfDay>()
            .toList();
        _selectedFrequency = data['frequencyType'] as String? ?? 'يومي';
        _selectedWeekdays =
            (data['weeklyDays'] as List<dynamic>? ?? []).whereType<int>().toSet();
        _currentImageUrl = data['imageUrl'] as String?;
        _currentImgbbDeleteHash = data['imgbbDeleteHash'] as String?;
        _newImageFile = null;
        _imageRemoved = false;
      } else {
        _errorMessage = "لم يتم العثور على بيانات الدواء.";
      }
    } catch (e, stackTrace) {
      print("Error loading medication data: $e\n$stackTrace");
      if (mounted) _errorMessage = "حدث خطأ أثناء تحميل البيانات.";
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  // --- Date Picker ---
  Future<void> _pickDate(BuildContext context, bool isStartDate) async {
    final initialDate = (isStartDate ? _selectedStartDate : _selectedEndDate) ?? DateTime.now();
    final firstDate = DateTime(DateTime.now().year - 5);
    final lastDate = DateTime(DateTime.now().year + 20);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('ar', 'SA'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        if (isStartDate) {
          _selectedStartDate = pickedDate;
          if (_selectedEndDate != null && _selectedEndDate!.isBefore(_selectedStartDate!)) {
            _selectedEndDate = null;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("تم مسح تاريخ الانتهاء لأنه كان قبل تاريخ البدء الجديد."),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          if (_selectedStartDate != null && pickedDate.isBefore(_selectedStartDate!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("تاريخ الانتهاء لا يمكن أن يكون قبل تاريخ البدء.")),
            );
          } else {
            _selectedEndDate = pickedDate;
          }
        }
      });
    }
  }

  // --- Time Picker ---
  Future<void> _pickTime(BuildContext context) async {
    final initialTime = TimeOfDay.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.blue.shade700,
              onPrimary: Colors.white,
            ),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: child!,
          ),
        );
      },
    );
    if (pickedTime != null) {
      if (!_selectedTimes.any((t) =>
      t.hour == pickedTime.hour && t.minute == pickedTime.minute)) {
        setState(() {
          _selectedTimes.add(pickedTime);
          _selectedTimes.sort((a, b) {
            if (a.hour != b.hour) return a.hour.compareTo(b.hour);
            return a.minute.compareTo(b.minute);
          });
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("هذا الوقت تم اختياره بالفعل.")),
        );
      }
    }
  }

  void _removeTime(int index) {
    setState(() {
      _selectedTimes.removeAt(index);
    });
  }

  // --- Image Handling ---
  Future<void> _getImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (image != null) {
        setState(() {
          _newImageFile = File(image.path);
          _imageRemoved = false;
        });
      }
    } catch (e) {
      print("Error getting image from $source: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("حدث خطأ أثناء ${source == ImageSource.camera ? 'التقاط الصورة' : 'اختيار الصورة'}."),
        ),
      );
    }
  }

  void _removeImage() {
    setState(() {
      _newImageFile = null;
      _imageRemoved = true;
    });
  }

  // --- ImgBB Helpers (INSECURE: Replace with secure key handling) ---
  Future<Map<String, String>?> _uploadImageToImgBB(File imageFile) async {
    const String imgbbApiKey = 'YOUR_IMGBB_API_KEY';
    if (imgbbApiKey == 'YOUR_IMGBB_API_KEY' || imgbbApiKey.isEmpty) {
      print("ERROR: ImgBB API Key not configured securely.");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("خطأ في إعدادات رفع الصور.")));
      return null;
    }
    final url = Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbApiKey');
    try {
      var request = http.MultipartRequest('POST', url);
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      var response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final RegExp imageUrlRegExp = RegExp(r'"url":"(.*?)"');
        final RegExp deleteUrlRegExp = RegExp(r'"delete_url":"(.*?)"');
        final imageUrlMatch = imageUrlRegExp.firstMatch(responseData);
        final deleteUrlMatch = deleteUrlRegExp.firstMatch(responseData);
        if (imageUrlMatch?.group(1) != null && deleteUrlMatch?.group(1) != null) {
          final deleteUrl = deleteUrlMatch!.group(1)!;
          final deleteHash = deleteUrl.split('/').last;
          return {
            'imageUrl': imageUrlMatch!.group(1)!,
            'imgbbDeleteHash': deleteHash
          };
        } else {
          print("Failed to parse ImgBB response: $responseData");
          return null;
        }
      } else {
        print("ImgBB upload failed. Status: ${response.statusCode}, Reason: ${await response.stream.bytesToString()}");
      }
    } catch (e) {
      print("Error uploading to ImgBB: $e");
    }
    return null;
  }

  Future<void> _deleteOldImgBBImage(String deleteHash) async {
    if (deleteHash.isEmpty) return;
    const String imgbbApiKey = 'YOUR_IMGBB_API_KEY';
    if (imgbbApiKey == 'YOUR_IMGBB_API_KEY' || imgbbApiKey.isEmpty) {
      print("WARNING: ImgBB API Key not configured securely. Skipping old image deletion.");
      return;
    }
    final url = Uri.parse('https://api.imgbb.com/1/image/$deleteHash?key=$imgbbApiKey');
    try {
      final response = await http.delete(url);
      if (response.statusCode == 200) {
        print("Old ImgBB image deleted successfully. Response: ${response.body}");
      } else {
        print("Failed to delete image from ImgBB ($deleteHash). Status: ${response.statusCode}, Body: ${response.body}");
      }
    } catch (e) {
      print("Error deleting image from ImgBB ($deleteHash): $e");
    }
  }

  // --- Save Changes ---
  Future<void> _saveChanges() async {
    if (_user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("خطأ: المستخدم غير متوفر لحفظ البيانات.")),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStartDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء تحديد تاريخ البدء.")));
      return;
    }
    if (_selectedTimes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء إضافة وقت واحد على الأقل للجرعة.")));
      return;
    }
    if (_selectedFrequency == 'اسبوعي' && _selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("الرجاء تحديد يوم واحد على الأقل في الأسبوع.")));
      return;
    }

    setState(() { _isSaving = true; });

    String? finalImageUrl = _currentImageUrl;
    String? finalDeleteHash = _currentImgbbDeleteHash;
    bool deleteOldImage = false;

    if (_newImageFile != null) {
      final uploadResult = await _uploadImageToImgBB(_newImageFile!);
      if (uploadResult != null) {
        finalImageUrl = uploadResult['imageUrl'];
        finalDeleteHash = uploadResult['imgbbDeleteHash'];
        deleteOldImage = _currentImgbbDeleteHash != null && _currentImgbbDeleteHash!.isNotEmpty;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("فشل رفع الصورة الجديدة. لم يتم حفظ التغييرات.")));
        setState(() { _isSaving = false; });
        return;
      }
    } else if (_imageRemoved) {
      deleteOldImage = _currentImgbbDeleteHash != null && _currentImgbbDeleteHash!.isNotEmpty;
      finalImageUrl = null;
      finalDeleteHash = null;
    }

    if (deleteOldImage) {
      await _deleteOldImgBBImage(_currentImgbbDeleteHash!);
    }

    final List<String> timesStringList =
    _selectedTimes.map((time) => TimeUtils.formatTimeOfDay(context, time)).toList();

    final Map<String, dynamic> updatedData = {
      'name': _nameController.text.trim(),
      'startDate': Timestamp.fromDate(_selectedStartDate!),
      'endDate': _selectedEndDate != null ? Timestamp.fromDate(_selectedEndDate!) : null,
      'times': timesStringList,
      'frequencyType': _selectedFrequency,
      'weeklyDays': _selectedFrequency == 'اسبوعي' ? _selectedWeekdays.toList() : FieldValue.delete(),
      'imageUrl': finalImageUrl,
      'imgbbDeleteHash': finalDeleteHash,
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('medicines')
          .doc(widget.docId)
          .update(updatedData);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("تم حفظ التغييرات بنجاح"), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    } catch (e) {
      print("Error saving medication changes: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("فشل حفظ التغييرات: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() { _isSaving = false; });
    }
  }

  // --- Build Method ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Use a custom background and header (like in DoseSchedule)
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios_new, color: Colors.blue.shade800, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      "تعديل الدواء",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              // Form Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildForm(),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // --- Build the Form ---
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Medication Name
          Text("اسم الدواء", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: "مثال: بنادول أدفانس",
              border: const OutlineInputBorder(),
              prefixIcon: Icon(Icons.medication_liquid, color: Colors.blue.shade800),
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return "الرجاء إدخال اسم الدواء";
              return null;
            },
          ),
          const SizedBox(height: 24),
          // Start & End Dates
          Text("فترة الاستخدام", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildDateButton(context, "تاريخ البدء", true)),
              const SizedBox(width: 12),
              Expanded(child: _buildDateButton(context, "الانتهاء (اختياري)", false)),
            ],
          ),
          if (_selectedEndDate != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => setState(() => _selectedEndDate = null),
                child: Text("مسح تاريخ الانتهاء", style: TextStyle(color: Colors.red, fontSize: 12)),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size(0, 30)),
              ),
            ),
          const SizedBox(height: 16),
          const Divider(height: 24),
          // Times
          _buildTimePickerSection(context),
          const SizedBox(height: 16),
          const Divider(height: 24),
          // Frequency
          _buildFrequencySection(context),
          const SizedBox(height: 16),
          // Weekly Days (if weekly)
          if (_selectedFrequency == 'اسبوعي') ...[
            _buildWeekdaySelector(context),
            const SizedBox(height: 16),
          ],
          const Divider(height: 24),
          // Image
          _buildImageSection(context),
          const SizedBox(height: 30),
          // Save Button
          ElevatedButton.icon(
            icon: _isSaving
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : const Icon(Icons.save_alt_outlined),
            label: Text(_isSaving ? "جارٍ الحفظ..." : "حفظ التغييرات"),
            onPressed: _isSaving ? null : _saveChanges,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // --- UI Builder Helpers ---
  Widget _buildDateButton(BuildContext context, String label, bool isStartDate) {
    final DateTime? dateToShow = isStartDate ? _selectedStartDate : _selectedEndDate;
    final String buttonText = dateToShow == null
        ? label
        : intl.DateFormat('yyyy/MM/dd', 'ar_SA').format(dateToShow);
    return OutlinedButton.icon(
      icon: Icon(
        isStartDate ? Icons.calendar_today_outlined : Icons.event_available_outlined,
        size: 20,
        color: dateToShow == null ? Colors.grey.shade600 : Colors.blue.shade800,
      ),
      label: Text(buttonText,
          style: TextStyle(
            color: dateToShow == null ? Colors.grey.shade600 : Colors.blue.shade800,
          )),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        side: BorderSide(color: dateToShow == null && isStartDate ? Colors.red : Colors.grey.shade400, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () => _pickDate(context, isStartDate),
    );
  }

  Widget _buildTimePickerSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("أوقات الجرعات:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
            IconButton(
              icon: Icon(Icons.add_alarm, color: Colors.blue.shade700),
              tooltip: "إضافة وقت",
              onPressed: () => _pickTime(context),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_selectedTimes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Text("الرجاء إضافة وقت واحد على الأقل",
                style: TextStyle(fontSize: 12, color: Colors.red)),
          )
        else
          Wrap(
            spacing: 8.0,
            runSpacing: 6.0,
            children: List<Widget>.generate(_selectedTimes.length, (index) {
              return Chip(
                label: Text(TimeUtils.formatTimeOfDay(context, _selectedTimes[index])),
                onDeleted: () => _removeTime(index),
                deleteIcon: Icon(Icons.cancel_outlined, size: 18, color: Colors.blue.shade700.withValues(alpha: 0.7)),
                backgroundColor: Colors.blue.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                side: BorderSide(color: Colors.blue.shade700.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              );
            }),
          ),
      ],
    );
  }

  Widget _buildFrequencySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("التكرار:",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: const Text('يومي'),
                value: 'يومي',
                groupValue: _selectedFrequency,
                onChanged: (value) {
                  if (value != null) setState(() => _selectedFrequency = value);
                },
                activeColor: Colors.blue.shade700,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: const Text('اسبوعي'),
                value: 'اسبوعي',
                groupValue: _selectedFrequency,
                onChanged: (value) {
                  if (value != null) setState(() => _selectedFrequency = value);
                },
                activeColor: Colors.blue.shade700,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeekdaySelector(BuildContext context) {
    const Map<int, String> weekdaysArabic = {
      1: 'الإثنين',
      2: 'الثلاثاء',
      3: 'الاربعاء',
      4: 'الخميس',
      5: 'الجمعة',
      6: 'السبت',
      7: 'الأحد',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("أيام الأسبوع:",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: List<Widget>.generate(7, (index) {
            final day = index + 1;
            final isSelected = _selectedWeekdays.contains(day);
            return FilterChip(
              label: Text(weekdaysArabic[day]!),
              selected: isSelected,
              onSelected: (bool selected) {
                setState(() {
                  if (selected)
                    _selectedWeekdays.add(day);
                  else
                    _selectedWeekdays.remove(day);
                });
              },
              selectedColor: Colors.blue.shade300,
              checkmarkColor: Colors.white,
              labelStyle: TextStyle(
                  fontSize: 14,
                  color: isSelected ? Colors.white : Colors.black87),
              backgroundColor: Colors.grey.shade200,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300)),
            );
          }),
        ),
        if (_selectedFrequency == 'اسبوعي' && _selectedWeekdays.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6.0, left: 8.0),
            child: Text("الرجاء تحديد يوم واحد على الأقل",
                style: TextStyle(fontSize: 12, color: Colors.red)),
          )
      ],
    );
  }

  Widget _buildImageSection(BuildContext context) {
    Widget imageDisplay;
    if (_newImageFile != null) {
      imageDisplay = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          _newImageFile!,
          height: 150,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else if (!_imageRemoved && _currentImageUrl != null && _currentImageUrl!.isNotEmpty) {
      try {
        imageDisplay = EnlargeableImage(
          key: ValueKey(_currentImageUrl!),
          imageUrl: _currentImageUrl!,
          width: double.infinity,
          height: 150,
        );
      } catch (e) {
        print("EnlargeableImage not available, falling back to Image.network.");
        imageDisplay = ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            _currentImageUrl!,
            height: 150,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, st) => _buildImagePlaceholder(context),
            loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : Center(child: CircularProgressIndicator()),
          ),
        );
      }
    } else {
      imageDisplay = _buildImagePlaceholder(context);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("صورة الدواء (اختياري):",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
        const SizedBox(height: 10),
        imageDisplay,
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: Icon(Icons.photo_library_outlined, color: Colors.blue.shade700),
              label: Text("اختر من المعرض", style: TextStyle(color: Colors.blue.shade700)),
              onPressed: () => _getImage(ImageSource.gallery),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
            ),
            TextButton.icon(
              icon: Icon(Icons.camera_alt_outlined, color: Colors.blue.shade700),
              label: Text("التقط صورة", style: TextStyle(color: Colors.blue.shade700)),
              onPressed: () => _getImage(ImageSource.camera),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
            ),
          ],
        ),
        if (((_currentImageUrl != null && _currentImageUrl!.isNotEmpty && !_imageRemoved) || _newImageFile != null))
          Center(
            child: TextButton.icon(
              icon: Icon(Icons.delete_outline, color: Colors.red, size: 20),
              label: Text("إزالة الصورة", style: TextStyle(color: Colors.red)),
              onPressed: _removeImage,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
            ),
          ),
      ],
    );
  }

  Widget _buildImagePlaceholder(BuildContext context) {
    return Container(
      height: 150,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade400),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade600, size: 50),
          const SizedBox(height: 8),
          Text("لا توجد صورة", style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}
