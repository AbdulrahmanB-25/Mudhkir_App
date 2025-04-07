import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;

class AddDose extends StatefulWidget {
  const AddDose({super.key});

  @override
  State<AddDose> createState() => _AddDoseState();
}

class _AddDoseState extends State<AddDose> {
  final PageController _pageController = PageController();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  String _dosageUnit = 'ملغم';
  List<TimeOfDay?> _selectedTimes = [];
  String _frequencyType = 'يومي';
  int _frequencyNumber = 1;
  DateTime? _startDate = DateTime.now();
  DateTime? _endDate;
  late Future<List<String>> _medicineNamesFuture;
  FocusNode _nameFocusNode = FocusNode();

  // Variable for the captured image.
  File? _capturedImage;

  final List<String> _dosageUnits = ['ملغم', 'غرام', 'مل', 'وحدة'];
  final List<String> _frequencyTypes = ['يومي', 'اسبوعي'];
  final List<int> _frequencyNumbers = [1, 2, 3, 4, 5, 6];

  @override
  void initState() {
    super.initState();
    _medicineNamesFuture = _loadMedicineNames();
    _updateTimeFields();
  }

  Future<List<String>> _loadMedicineNames() async {
    try {
      final String jsonString =
      await rootBundle.loadString('assets/Mediciens/trade_names.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      return List<String>.from(jsonList);
    } catch (e) {
      print('Error loading medicine names: $e');
      return [];
    }
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _selectTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedTimes[index] = picked;
      });
    }
  }

  void _updateTimeFields() {
    setState(() {
      _selectedTimes = List.generate(
        _frequencyNumber,
            (index) =>
        _selectedTimes.length > index ? _selectedTimes[index] : null,
      );
    });
  }

  // Function to capture image from the camera using image_picker.
Future<void> _pickImage() async {
  try {
final pickedFile = await ImagePicker().pickImage(source: ImageSource.camera);
if (pickedFile != null) {
      setState(() {
        _capturedImage = File(pickedFile.path);
      });
    }
  } catch (e) {
    print("Image picker error: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("حدث خطأ أثناء التقاط الصورة")),
    );
  }
}

  // Function to upload the image to Firebase Storage and return its download URL.
  Future<String?> _uploadImage(String userId) async {
    // Check if image exists
    if (_capturedImage == null) {
      print('No image captured to upload.');
      return null;
    }

    try {
      // Create unique filename
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Create storage reference
      final storageRef = firebase_storage.FirebaseStorage.instance
          .ref()
          .child('users')
          .child(userId)
          .child('medicines')
          .child(fileName);

      // Upload file
      final metadata = firebase_storage.SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'userId': userId}
      );

      final uploadTask = await storageRef.putFile(_capturedImage!, metadata);

      // Get download URL
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      print('Image uploaded successfully. URL: $downloadUrl');
      return downloadUrl;

    } catch (e) {
      print('Error uploading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء رفع الصورة'))
      );
      return null;
    }
  }


  void _submitForm() async {
                if (_formKey.currentState!.validate()) {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    // Upload the image if available.
                    String? imageUrl = await _uploadImage(user.uid);

                    final newMedicine = {
                      'userId': user.uid,
                      'name': _nameController.text,
                      'dosage': '${_dosageController.text} $_dosageUnit',
                      'frequency': '$_frequencyNumber $_frequencyType',
                      'times': _selectedTimes.map((time) => time?.format(context)).toList(),
                      'startDate': _startDate != null
                          ? "${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}"
                          : null,
                      'endDate': _endDate != null
                          ? "${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}"
                          : null,
                      'createdAt': FieldValue.serverTimestamp(),
                      if (imageUrl != null) 'imageUrl': imageUrl,
                    };

                    try {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('medicines')
                          .add(newMedicine);

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تمت إضافة الدواء بنجاح!')),
                      );

                      Navigator.pop(context, true);
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('حدث خطأ أثناء إضافة الدواء!'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              }

  // Widget for capturing and displaying the image.
  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.blue.shade800),
          borderRadius: BorderRadius.circular(8),
        ),
        child: _capturedImage != null
            ? Image.file(_capturedImage!, fit: BoxFit.contain)
            : Center(
          child: Text(
            'اضغط لالتقاط صورة',
            style: TextStyle(color: Colors.blue.shade800, fontSize: 16),
          ),
        ),
      ),
    );
  }

  Widget _buildMedicationNamePage() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue.shade800),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Text(
              "إضافة دواء جديد",
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
            const SizedBox(height: 30),
            // Use image_picker to capture the image.
            _buildImagePicker(),
            const SizedBox(height: 20),
            FutureBuilder<List<String>>(
              future: _medicineNamesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                } else {
                  final medicineNames = snapshot.data ?? [];
                  return Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.length < 2) {
                        return const Iterable<String>.empty();
                      }
                      return medicineNames.where((String medicine) {
                        return medicine
                            .toLowerCase()
                            .startsWith(textEditingValue.text.toLowerCase());
                      });
                    },
                    onSelected: (String selection) {
                      _nameController.text = selection;
                    },
                    fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                      _nameFocusNode = focusNode;
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'اسم الدواء',
                          icon: Icon(Icons.medication, color: Colors.blue.shade800),
                        ),
                        validator: (value) =>
                        (value == null || value.isEmpty) ? 'ادخل اسم الدواء' : null,
                      );
                    },
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState != null && _formKey.currentState!.validate()) {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              child: const Text('التالي', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDosageAndTimesPage() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue.shade800),
                onPressed: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
              ),
            ),
            Text(
              "الجرعة والأوقات",
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dosageController,
                    decoration: InputDecoration(
                      labelText: 'الجرعة',
                      icon: Icon(Icons.science, color: Colors.blue.shade800),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'ادخل الجرعة'
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _dosageUnit,
                  onChanged: (value) => setState(() => _dosageUnit = value!),
                  items: _dosageUnits.map((unit) {
                    return DropdownMenuItem(
                      value: unit,
                      child: Text(unit),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _frequencyNumber,
                    decoration: InputDecoration(
                      labelText: 'عدد المرات',
                      icon: Icon(Icons.repeat, color: Colors.blue.shade800),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _frequencyNumber = value!;
                        _updateTimeFields();
                      });
                    },
                    items: _frequencyNumbers.map((num) {
                      return DropdownMenuItem(
                        value: num,
                        child: Text(num.toString()),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _frequencyType,
                    decoration: InputDecoration(
                      labelText: 'النوع',
                      icon: Icon(Icons.calendar_today, color: Colors.blue.shade800),
                    ),
                    onChanged: (value) => setState(() => _frequencyType = value!),
                    items: _frequencyTypes.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أوقات الجرعة', style: TextStyle(color: Colors.blue.shade800)),
                ...List.generate(_frequencyNumber, (index) {
                  return Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.access_time, color: Colors.blue.shade800),
                        onPressed: () => _selectTime(index),
                      ),
                      GestureDetector(
                        onTap: () => _selectTime(index),
                        child: Text(
                          _selectedTimes[index] == null
                              ? 'اختر الوقت'
                              : _selectedTimes[index]!.format(context),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              child: const Text('التالي', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartDateEndDatePage() {
    return Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue.shade800),
                onPressed: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
              ),
            ),
            Text(
              "تاريخ البدء والانتهاء",
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800),
            ),
            const SizedBox(height: 30),
            ListTile(
              leading: Icon(Icons.calendar_today, color: Colors.blue.shade800),
              title: Text(
                _startDate == null
                    ? 'اختر تاريخ البدء'
                    : "${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}",
              ),
              onTap: _selectStartDate,
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.calendar_today, color: Colors.blue.shade800),
              title: Text(
                _endDate == null
                    ? 'اختر تاريخ الانتهاء'
                    : "${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}",
              ),
              onTap: _selectEndDate,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              child: const Text('اضف الدواء لخزانتي', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _nameFocusNode.unfocus();
      },
      child: Scaffold(
        body: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade100, Colors.white],
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
    _nameFocusNode.dispose();
    super.dispose();
  }
}
