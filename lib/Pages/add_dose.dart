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
  final String imgbbApiKey = '2b30d3479663bc30a70c916363b07c4a'; // Replace with your actual key

  final PageController _pageController = PageController();
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
      initialDate: _startDate ?? DateTime.now(), // Use current selection or now
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(), // Use selection or start date or now
      firstDate: _startDate ?? DateTime.now(), // Cannot be before start date
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _selectTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimes[index] ?? TimeOfDay.now(), // Use current selection or now
    );
    if (picked != null) setState(() => _selectedTimes[index] = picked);
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile =
      await ImagePicker().pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        setState(() => _capturedImage = File(pickedFile.path));
        // Start upload immediately after picking
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
        if (mounted) { // Check if the widget is still in the tree
          setState(() {
            _uploadedImageUrl = jsonResponse['data']['url'];
          });
        }
        print("Image uploaded to ImgBB: $_uploadedImageUrl");
      } else {
        print("ImgBB upload failed: ${response.body}");
        // Optionally show an error to the user here
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
    // Ensure context is valid before showing dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: onOk == null, // Allow dismissal only if no specific action
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text("حسناً"), // Changed to Arabic "OK"
              onPressed: () {
                Navigator.of(context).pop();
                if (onOk != null) {
                  onOk();
                }
              },
            )
          ],
        );
      },
    );
  }

  void _submitForm() async {
    // Ensure the last form page is valid
    if (!_formKeyPage3.currentState!.validate()) {
      return; // Stop if validation fails
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showBlockingAlert("خطأ", "المستخدم غير مسجل الدخول.");
      return; // Stop if no user
    }

    // Check if an image was captured but is still uploading
    if (_capturedImage != null && _uploadedImageUrl == null) {
      _showBlockingAlert(
          "انتظار", "يتم تحميل الصورة حالياً. الرجاء الانتظار لحظات ثم المحاولة مرة أخرى.");
      return; // Stop and inform user
    }

    // Prepare data for Firestore
    final newMedicine = <String, dynamic>{ // Explicit type
      'userId': user.uid,
      'name': _nameController.text.trim(), // Trim whitespace
      'dosage': '${_dosageController.text.trim()} $_dosageUnit', // Trim whitespace
      'frequency': '$_frequencyNumber $_frequencyType',
      'times': _selectedTimes
          .map((t) => t?.format(context)) // Format TimeOfDay
          .where((t) => t != null) // Filter out potential nulls if any step failed
          .toList(),
      'startDate': _startDate != null
          ? Timestamp.fromDate(_startDate!) // Store as Timestamp
          : null,
      'endDate': _endDate != null
          ? Timestamp.fromDate(_endDate!) // Store as Timestamp
          : null,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (_uploadedImageUrl != null) {
      newMedicine['imageUrl'] = _uploadedImageUrl;
      print("✅ Image URL ready for Firestore: $_uploadedImageUrl");
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .add(newMedicine);

      _showBlockingAlert("نجاح", "تمت إضافة الدواء بنجاح!", onOk: () {
        // Ensure navigation happens only if the widget is still mounted
        if (mounted) {
          Navigator.pop(context, true); // Pop with result true indicates success
        }
      });
    } catch (e) {
      print("❌ Firestore error: $e");
      _showBlockingAlert("خطأ", "حدث خطأ أثناء إضافة الدواء إلى قاعدة البيانات.");
    }
  }


  // Page 1: Medication Name and Image
  Widget _buildMedicationNamePage() {
    final screenWidth = MediaQuery.of(context).size.width;
    // Use EdgeInsets based on screen width for consistent padding
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0; // Consistent vertical padding

    return Form(
      key: _formKeyPage1,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding, vertical: verticalPadding),
        child: Stack(
          children: [
            // Fixed back button at top-left
            Positioned(
              top: 15, // Adjust position slightly if needed
              left: -10, // Adjust position slightly if needed
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue.shade800, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            // Center the form content
            Center(
              child: SingleChildScrollView( // Allows scrolling on smaller screens
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, // Center vertically in the column
                  crossAxisAlignment: CrossAxisAlignment.center, // Center horizontally
                  children: [
                    const SizedBox(height: 50), // Space below back button area
                    Text(
                      "إضافة دواء جديد",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: screenWidth * 0.07, // Keep text size dynamic
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 25.0), // Reduced space
                    _buildImagePicker(screenWidth),
                    const SizedBox(height: 25.0), // Reduced space
                    FutureBuilder<List<String>>(
                      future: _medicineNamesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        } else if (snapshot.hasError) {
                          return Text('خطأ في تحميل أسماء الأدوية: ${snapshot.error}');
                        } else {
                          final medicineNames = snapshot.data ?? [];
                          return Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              final query = textEditingValue.text.toLowerCase();
                              if (query.length < 2) {
                                return const Iterable<String>.empty();
                              }
                              return medicineNames.where((String name) =>
                                  name.toLowerCase().contains(query));
                            },
                            onSelected: (String selection) {
                              _nameController.text = selection;
                              FocusScope.of(context).unfocus(); // Hide keyboard
                            },
                            fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                              // Sync external controller with internal one
                              if (_nameController.text != controller.text) {
                                controller.text = _nameController.text;
                                // Place cursor at the end
                                controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                              }
                              controller.addListener(() {
                                _nameController.text = controller.text;
                              });

                              return TextFormField(
                                controller: controller,
                                focusNode: focusNode,
                                onEditingComplete: onEditingComplete, // Important for accessibility
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  labelText: 'اسم الدواء',
                                  alignLabelWithHint: true,
                                  icon: Icon(Icons.medication_outlined, color: Colors.blue.shade800), // Changed icon slightly
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: Colors.blue.shade800, width: 2.0),
                                      borderRadius: BorderRadius.circular(12)
                                  ),
                                ),
                                validator: (value) => (value == null || value.trim().isEmpty)
                                    ? 'الرجاء إدخال اسم الدواء'
                                    : null,
                              );
                            },
                            optionsViewBuilder: (context, onSelected, options) {
                              return Align(
                                alignment: Alignment.topLeft,
                                child: Material(
                                  elevation: 4.0,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(maxHeight: 200, maxWidth: screenWidth - (horizontalPadding * 2)), // Limit dropdown size
                                    child: ListView.builder(
                                      padding: EdgeInsets.zero,
                                      shrinkWrap: true,
                                      itemCount: options.length,
                                      itemBuilder: (BuildContext context, int index) {
                                        final String option = options.elementAt(index);
                                        return InkWell(
                                          onTap: () => onSelected(option),
                                          child: Padding(
                                            padding: const EdgeInsets.all(16.0),
                                            child: Text(option),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 30.0), // Reduced space before button
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
                          minimumSize: Size(double.infinity, 55), // Make button slightly taller
                          backgroundColor: Colors.blue.shade800,
                          foregroundColor: Colors.white, // Set text color
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15), // Slightly adjusted radius
                          ),
                          padding: const EdgeInsets.symmetric( // Use fixed padding
                            horizontal: 20,
                            vertical: 15, // Adjusted vertical padding
                          ),
                          textStyle: const TextStyle( // Ensure text style consistency if needed
                            fontSize: 18, // Keep text size reasonable
                            fontWeight: FontWeight.bold,
                          )
                      ),
                      child: const Text('التالي'),
                    ),
                    const SizedBox(height: 20), // Add some padding at the bottom if scrolling occurs
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }


  // Page 2: Dosage and Times
  Widget _buildDosageAndTimesPage() {
    final screenWidth = MediaQuery.of(context).size.width;
    // Use consistent padding
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0;

    return Form(
      key: _formKeyPage2,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding, vertical: verticalPadding),
        child: Stack(
          children: [
            // Fixed back button
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
                  crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children horizontally
                  children: [
                    const SizedBox(height: 50), // Space below back button area
                    Text(
                      "الجرعة والأوقات",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: screenWidth * 0.07, // Keep text size dynamic
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 25.0), // Reduced space

                    // Dosage and unit fields
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center, // Align items vertically
                      children: [
                        Icon(Icons.science_outlined, color: Colors.blue.shade800), // Icon before field
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3, // Give more space to text field
                          child: TextFormField(
                            controller: _dosageController,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true), // Allow decimals
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')), // Allow numbers and one decimal point
                            ],
                            decoration: InputDecoration(
                              labelText: 'الجرعة',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue.shade800, width: 2.0),
                                  borderRadius: BorderRadius.circular(12)
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
                        Expanded( // Use Expanded for dropdown button container for better alignment
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _dosageUnit,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0), // Adjust padding
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue.shade800, width: 2.0),
                                  borderRadius: BorderRadius.circular(12)
                              ),
                            ),
                            onChanged: (value) => setState(() => _dosageUnit = value!),
                            items: _dosageUnits.map((unit) => DropdownMenuItem(value: unit, child: Text(unit))).toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20.0), // Consistent spacing

                    // Frequency options
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start, // Align based on the top of the elements
                      children: [
                        Icon(Icons.repeat, color: Colors.blue.shade800), // Icon for frequency number
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _frequencyNumber,
                            decoration: InputDecoration(
                              labelText: 'عدد المرات',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue.shade800, width: 2.0),
                                  borderRadius: BorderRadius.circular(12)
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
                            items: _frequencyNumbers.map((num) => DropdownMenuItem(value: num, child: Text(num.toString()))).toList(),
                            validator: (value) => value == null ? 'اختر العدد' : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.calendar_today_outlined, color: Colors.blue.shade800), // Icon for frequency type
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _frequencyType,
                            decoration: InputDecoration(
                              labelText: 'النوع',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue.shade800, width: 2.0),
                                  borderRadius: BorderRadius.circular(12)
                              ),
                            ),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _frequencyType = value);
                              }
                            },
                            items: _frequencyTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                            validator: (value) => value == null ? 'اختر النوع' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 25.0), // Space before time list

                    // Time picker list
                    Text(
                      "أوقات تناول الجرعة:", // Add a label for clarity
                      style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    ListView.builder( // Use ListView.builder for dynamic list
                      shrinkWrap: true, // Important within SingleChildScrollView
                      physics: const NeverScrollableScrollPhysics(), // Disable ListView's own scrolling
                      itemCount: _frequencyNumber,
                      itemBuilder: (context, index) {
                        return Card( // Wrap each time picker in a Card for better visuals
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          elevation: 1.0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            leading: Icon(Icons.access_time_filled, color: Colors.blue.shade700),
                            title: Text(
                              _selectedTimes[index] == null
                                  ? 'اضغط لاختيار الوقت ${index + 1}'
                                  : _selectedTimes[index]!.format(context),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: _selectedTimes[index] == null ? FontWeight.normal : FontWeight.bold,
                                color: _selectedTimes[index] == null ? Colors.grey.shade600 : Colors.black87,
                              ),
                            ),
                            trailing: const Icon(Icons.edit_calendar_outlined),
                            onTap: () => _selectTime(index),
                            // Add validation feedback here if needed, though direct validation on ListTile is tricky.
                            // Usually validation is checked before proceeding.
                          ),
                        );
                      },
                    ),
                    // Add a helper text if times are not selected.
                    if (_selectedTimes.any((t) => t == null))
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'الرجاء تحديد جميع الأوقات المطلوبة.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                        ),
                      ),

                    const SizedBox(height: 30.0), // Space before button
                    ElevatedButton(
                      onPressed: () {
                        bool allTimesSelected = !_selectedTimes.any((t) => t == null);
                        if (_formKeyPage2.currentState!.validate() && allTimesSelected) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else if (!allTimesSelected) {
                          // Optionally show a snackbar or alert if times are missing
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('الرجاء تحديد جميع أوقات الجرعات'))
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
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          )
                      ),
                      child: const Text('التالي'),
                    ),
                    const SizedBox(height: 20), // Bottom padding
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // Page 3: Start and End Dates
  Widget _buildStartDateEndDatePage() {
    final screenWidth = MediaQuery.of(context).size.width;
    // Use consistent padding
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0;

    return Form(
      key: _formKeyPage3,
      // No specific validation needed here unless start/end dates are mandatory
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding, vertical: verticalPadding),
        child: Stack(
          children: [
            // Fixed back button
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
                    const SizedBox(height: 50), // Space below back button area
                    Text(
                      "تاريخ البدء والانتهاء",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: screenWidth * 0.07, // Keep text size dynamic
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 35.0), // Increased space

                    // Start Date Picker
                    Card( // Wrap in Card
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
                    // Add validation message display area for start date
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
                            : Container(); // Return empty container if no error
                      },
                    ),


                    const SizedBox(height: 15.0), // Space between dates

                    // End Date Picker
                    Card( // Wrap in Card
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
                    // Optional: Add validation for end date if needed (e.g., must be after start date)
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


                    const SizedBox(height: 40.0), // Increased space before final button
                    ElevatedButton(
                      onPressed: _submitForm, // Calls the submit logic
                      style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 55),
                          backgroundColor: Colors.green.shade700, // Changed color for final action
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          )
                      ),
                      child: const Text('إضافة الدواء إلى خزانتي'),
                    ),
                    const SizedBox(height: 20), // Bottom padding
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }


  Widget _buildImagePicker(double screenWidth) {
    return Center( // Center the image picker area
      child: GestureDetector(
        onTap: _pickImage,
        child: Container(
          height: screenWidth * 0.45, // Slightly larger height
          width: screenWidth * 0.7,   // Make it wide but not full width
          decoration: BoxDecoration(
            color: Colors.grey.shade200, // Lighter background
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(15), // More rounded corners
            image: _capturedImage != null
                ? DecorationImage(
              image: FileImage(_capturedImage!),
              fit: BoxFit.cover, // Cover the area
            )
                : null,
          ),
          child: _capturedImage == null
              ? Center(
              child: Column( // Center icon and text vertically
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined, size: screenWidth * 0.12, color: Colors.blue.shade800),
                  const SizedBox(height: 8),
                  Text(
                    'اضغط لالتقاط صورة للدواء',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.blue.shade800, fontSize: screenWidth * 0.04), // Slightly smaller text
                  ),
                ],
              )
          )
          // Show upload progress or status if desired
              : _uploadedImageUrl == null ? Center(child: CircularProgressIndicator(color: Colors.white,)) : Container(), // Show progress indicator while uploading

        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // Unfocus on tap outside
      child: Scaffold(
        body: Stack(
          children: [
            // Background Gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.white, Colors.grey.shade50], // Subtle gradient
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            // PageView
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(), // Prevent manual swiping
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
    _pageController.dispose(); // Dispose PageController
    super.dispose();
  }
}