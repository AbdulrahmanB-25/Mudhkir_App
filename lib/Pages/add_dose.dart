import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class AddDose extends StatefulWidget {
  const AddDose({super.key});

  @override
  State<AddDose> createState() => _AddDoseState();
}

class _AddDoseState extends State<AddDose> {
  final String imgbbApiKey = '2b30d3479663bc30a70c916363b07c4a';

  final PageController _pageController = PageController();
  // Use three separate form keys—one for each page.
  final GlobalKey<FormState> _formKeyPage1 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyPage2 = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyPage3 = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  String _dosageUnit = 'ملغم';
  List<TimeOfDay?> _selectedTimes = [];
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

  void _updateTimeFields() {
    setState(() {
      _selectedTimes = List.generate(
        _frequencyNumber,
            (index) => _selectedTimes.length > index ? _selectedTimes[index] : null,
      );
    });
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _selectTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _selectedTimes[index] = picked);
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile =
      await ImagePicker().pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        setState(() => _capturedImage = File(pickedFile.path));
        await _uploadImageToImgBB(_capturedImage!);
      }
    } catch (e) {
      print("Image picker error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("حدث خطأ أثناء التقاط الصورة")),
      );
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
        setState(() {
          _uploadedImageUrl = jsonResponse['data']['url'];
        });
        print("Image uploaded to ImgBB: $_uploadedImageUrl");
      } else {
        print("ImgBB upload failed: ${response.body}");
      }
    } catch (e) {
      print("Error uploading image to ImgBB: $e");
    }
  }

  void _submitForm() async {
    if (_formKeyPage3.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (_capturedImage != null && _uploadedImageUrl == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("يتم تحميل الصورة... الرجاء الانتظار")),
          );
          return;
        }

        final newMedicine = {
          'userId': user.uid,
          'name': _nameController.text,
          'dosage': '${_dosageController.text} $_dosageUnit',
          'frequency': '$_frequencyNumber $_frequencyType',
          'times': _selectedTimes.map((t) => t?.format(context)).toList(),
          'startDate': _startDate != null
              ? "${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}"
              : null,
          'endDate': _endDate != null
              ? "${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}"
              : null,
          'createdAt': FieldValue.serverTimestamp(),
        };

        if (_uploadedImageUrl != null) {
          newMedicine['imageUrl'] = _uploadedImageUrl;
          print("✅ Image URL ready: $_uploadedImageUrl");
        }

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
          print("❌ Firestore error: $e");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('حدث خطأ أثناء إضافة الدواء!'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

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
            ? Image.file(_capturedImage!, fit: BoxFit.cover)
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
      key: _formKeyPage1,
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
                  color: Colors.blue.shade800),
            ),
            const SizedBox(height: 30),
            _buildImagePicker(),
            const SizedBox(height: 20),
            FutureBuilder<List<String>>(
              future: _medicineNamesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                } else {
                  final medicineNames = snapshot.data ?? [];
                  return Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.length < 2)
                        return const Iterable<String>.empty();
                      return medicineNames.where((String name) =>
                          name.toLowerCase().contains(
                              textEditingValue.text.toLowerCase()));
                    },
                    onSelected: (String selection) {
                      _nameController.text = selection;
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onEditingComplete) {
                      // Simply attach the provided controller and focus node.
                      controller.text = _nameController.text;
                      controller.addListener(() {
                        _nameController.text = controller.text;
                        _nameController.selection = controller.selection;
                      });
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'اسم الدواء',
                          icon: Icon(Icons.medication,
                              color: Colors.blue.shade800),
                        ),
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'ادخل اسم الدواء'
                            : null,
                      );
                    },
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_formKeyPage1.currentState!.validate()) {
                  _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child:
              const Text('التالي', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDosageAndTimesPage() {
    return Form(
      key: _formKeyPage2,
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
                    curve: Curves.easeInOut),
              ),
            ),
            Text(
              "الجرعة والأوقات",
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800),
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dosageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'الجرعة',
                      icon: Icon(Icons.science, color: Colors.blue.shade800),
                    ),
                    validator: (value) =>
                    (value == null || value.isEmpty) ? 'ادخل الجرعة' : null,
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: _dosageUnit,
                  onChanged: (value) => setState(() => _dosageUnit = value!),
                  items: _dosageUnits
                      .map((unit) =>
                      DropdownMenuItem(value: unit, child: Text(unit)))
                      .toList(),
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
                          value: num, child: Text(num.toString()));
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _frequencyType,
                    decoration: InputDecoration(
                      labelText: 'النوع',
                      icon:
                      Icon(Icons.calendar_today, color: Colors.blue.shade800),
                    ),
                    onChanged: (value) => setState(() => _frequencyType = value!),
                    items: _frequencyTypes.map((type) {
                      return DropdownMenuItem(value: type, child: Text(type));
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Column(
              children: List.generate(_frequencyNumber, (index) {
                return ListTile(
                  leading:
                  Icon(Icons.access_time, color: Colors.blue.shade800),
                  title: Text(
                    _selectedTimes[index] == null
                        ? 'اختر الوقت'
                        : _selectedTimes[index]!.format(context),
                  ),
                  onTap: () => _selectTime(index),
                );
              }),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_formKeyPage2.currentState!.validate()) {
                  _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child:
              const Text('التالي', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartDateEndDatePage() {
    return Form(
      key: _formKeyPage3,
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
                    curve: Curves.easeInOut),
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
              leading:
              Icon(Icons.calendar_today, color: Colors.blue.shade800),
              title: Text(_startDate == null
                  ? 'اختر تاريخ البدء'
                  : "${_startDate!.year}-${_startDate!.month}-${_startDate!.day}"),
              onTap: _selectStartDate,
            ),
            ListTile(
              leading:
              Icon(Icons.calendar_today, color: Colors.blue.shade800),
              title: Text(_endDate == null
                  ? 'اختر تاريخ الانتهاء'
                  : "${_endDate!.year}-${_endDate!.month}-${_endDate!.day}"),
              onTap: _selectEndDate,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade800,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('اضف الدواء لخزانتي',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Instead of using a disposed FocusNode, unfocus via the FocusScope.
      onTap: () => FocusScope.of(context).unfocus(),
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
    super.dispose();
  }
}
