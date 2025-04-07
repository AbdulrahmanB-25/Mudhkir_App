import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class add_dose extends StatefulWidget {
  const add_dose({super.key});

  @override
  State<add_dose> createState() => _add_doseState();
}



//TODO : MAKE IT PAGES FOR EVERY CATAGORIE



class _add_doseState extends State<add_dose> {
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
      final String jsonString = await rootBundle.loadString(
        'assets/Mediciens/trade_names.json',
      );
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
            (index) => _selectedTimes.length > index ? _selectedTimes[index] : null,
      );
    });
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
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
        };

        try {
          CollectionReference medicines =
          FirebaseFirestore.instance.collection('medicines');
          await medicines.add(newMedicine);

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
            SingleChildScrollView(
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
                  Form(
                    key: _formKey,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          FutureBuilder<List<String>>(
                            future: _medicineNamesFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return CircularProgressIndicator();
                              } else if (snapshot.hasError) {
                                return Text('Error: ${snapshot.error}');
                              } else {
                                final medicineNames = snapshot.data!;
                                return Autocomplete<String>(
                                  optionsBuilder: (
                                      TextEditingValue textEditingValue,
                                      ) {
                                    if (textEditingValue.text.length < 2) {
                                      return const Iterable<String>.empty();
                                    }
                                    return medicineNames.where(
                                          (String medicine) {
                                        return medicine
                                            .toLowerCase()
                                            .startsWith(
                                          textEditingValue.text.toLowerCase(),
                                        );
                                      },
                                    ).toList();
                                  },
                                  onSelected: (String selection) {
                                    _nameController.text = selection;
                                  },
                                  fieldViewBuilder: (
                                      context,
                                      controller,
                                      focusNode,
                                      onEditingComplete,
                                      ) {
                                    _nameFocusNode = focusNode;
                                    return TextFormField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      decoration: InputDecoration(
                                        labelText: 'اسم الدواء',
                                        icon: Icon(
                                          Icons.medication,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                      validator: (value) =>
                                      (value == null || value.isEmpty)
                                          ? 'ادخل اسم الدواء'
                                          : null,
                                    );
                                  },
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _dosageController,
                                  decoration: InputDecoration(
                                    labelText: 'الجرعة',
                                    icon: Icon(
                                      Icons.science,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (value) =>
                                  (value == null || value.isEmpty)
                                      ? 'ادخل الجرعة'
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              DropdownButton<String>(
                                value: _dosageUnit,
                                onChanged: (value) =>
                                    setState(() => _dosageUnit = value!),
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
                                    icon: Icon(
                                      Icons.repeat,
                                      color: Colors.blue.shade800,
                                    ),
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
                                    icon: Icon(
                                      Icons.calendar_today,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                  onChanged: (value) =>
                                      setState(() => _frequencyType = value!),
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
                              Text(
                                'أوقات الجرعة',
                                style: TextStyle(color: Colors.blue.shade800),
                              ),
                              ...List.generate(_frequencyNumber, (index) {
                                return Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.access_time,
                                        color: Colors.blue.shade800,
                                      ),
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
                          ListTile(
                            leading: Icon(
                              Icons.calendar_today,
                              color: Colors.blue.shade800,
                            ),
                            title: Text(
                              _startDate == null
                                  ? 'اختر تاريخ البدء'
                                  : "${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}",
                            ),
                            onTap: _selectStartDate,
                          ),
                          const SizedBox(height: 20),
                          ListTile(
                            leading: Icon(
                              Icons.calendar_today,
                              color: Colors.blue.shade800,
                            ),
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 30,
                                vertical: 15,
                              ),
                            ),
                            child: const Text(
                              'اضف الدواء لخزانتي',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
