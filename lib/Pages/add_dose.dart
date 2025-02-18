import 'package:flutter/material.dart';

class add_dose extends StatefulWidget {
  const add_dose({super.key});

  @override
  State<add_dose> createState() => _AddDoseState();
}

class _AddDoseState extends State<add_dose> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  Future<void> _selectExpiryDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) {
      setState(() {
        _expiryController.text = "${picked.year}-${picked.month}-${picked.day}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      /// 🌈 Background Gradient
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// 📌 Title
                  Text(
                    "إضافة دواء جديد",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 30),

                  /// 📜 Form
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
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          /// 📝 Medication Name
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'اسم الدواء',
                              icon: Icon(Icons.medication,
                                  color: Colors.blue.shade800),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'ادخل اسم الدواء';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          /// 💊 Dosage
                          TextFormField(
                            controller: _dosageController,
                            decoration: InputDecoration(
                              labelText: 'الجرعة',
                              icon: Icon(Icons.science,
                                  color: Colors.blue.shade800),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'ادخل معلومات الجرعة';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          /// 📅 Expiry Date
                          TextFormField(
                            controller: _expiryController,
                            decoration: InputDecoration(
                              labelText: 'تاريخ الانتهاء من اخذ الدواء',
                              icon: Icon(Icons.calendar_today,
                                  color: Colors.blue.shade800),
                              suffixIcon: IconButton(
                                icon: Icon(Icons.date_range,
                                    color: Colors.blue.shade800),
                                onPressed: _selectExpiryDate,
                              ),
                            ),
                            readOnly: true,
                            onTap: _selectExpiryDate,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'ادخل تاريخ الانتهاء من الدواء';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          /// 🔢 Quantity
                          TextFormField(
                            controller: _quantityController,
                            decoration: InputDecoration(
                              labelText: 'الكمية اليومية للدواء',
                              icon: Icon(Icons.format_list_numbered,
                                  color: Colors.blue.shade800),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'ادخل الكمية اليومية للدواء';
                              }
                              if (int.tryParse(value) == null) {
                                return ' ادخل عدد المرات اليومية للدواء ';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 30),

                          /// 📥 Submit Button
                          ElevatedButton(
                            onPressed: _submitForm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade800,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 30, vertical: 15),
                            ),
                            child: const Text(
                              'اضف الدواء لخزانتي',
                              style: TextStyle(fontSize: 18 , color: Colors.white),
                            ),
                          ),
                        ],
                      ),
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

  /// 📨 Submit Form
  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      final newMedicine = {
        'name': _nameController.text,
        'dosage': _dosageController.text,
        'expiry': _expiryController.text,
        'quantity': int.parse(_quantityController.text),
      };

      //TODO: ADD TO save to database
      print('New Medicine: $newMedicine');

      Navigator.pop(context, newMedicine);
    }
  }

  /// 🧹 Clean up Controllers
  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _expiryController.dispose();
    _quantityController.dispose();
    super.dispose();
  }
}
