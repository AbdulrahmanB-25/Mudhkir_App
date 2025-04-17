import 'dart:io';
import 'package:flutter/material.dart';

// --- Medicine Autocomplete Widget ---
// (Moved here as it's only used on this page)
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
  final ScrollController _scrollController = ScrollController();

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
      if (mounted) {
        setState(() {
          _filteredSuggestions = [];
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _filteredSuggestions = widget.suggestions
              .where((s) => s.toLowerCase().contains(text))
              .take(3) // Limit to 3 suggestions
              .toList();
        });
      }
    }
  }

  void _handleFocusChange() {
    if (!widget.focusNode.hasFocus) {
      if (mounted) {
        setState(() {
          _filteredSuggestions = [];
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_filter);
    widget.focusNode.removeListener(_handleFocusChange);
    _scrollController.dispose();
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
                if (mounted) {
                  setState(() {
                    _filteredSuggestions = [];
                  });
                }
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
            // Adjust height based on suggestion count, max 3 items
            height: (_filteredSuggestions.length * 60.0).clamp(60.0, 180.0),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _scrollController,
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
                      if (mounted) {
                        setState(() {
                          _filteredSuggestions = [];
                        });
                      }
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


// --- AddNamePicturePage Widget ---
class AddNamePicturePage extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final Future<List<String>> medicineNamesFuture;
  final File? capturedImage;
  final String? uploadedImageUrl; // To show progress indicator
  final VoidCallback onPickImage;
  final VoidCallback onNext;
  final VoidCallback onBack; // Callback for back button

  const AddNamePicturePage({
    Key? key,
    required this.formKey,
    required this.nameController,
    required this.medicineNamesFuture,
    required this.capturedImage,
    required this.uploadedImageUrl,
    required this.onPickImage,
    required this.onNext,
    required this.onBack,
  }) : super(key: key);


  // --- Image Picker Section UI ---
  Widget _buildImagePicker(BuildContext context, double screenWidth) {
    return Center(
      child: GestureDetector(
        onTap: onPickImage, // Use the callback
        child: Container(
          height: screenWidth * 0.45,
          width: screenWidth * 0.7,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            border: Border.all(color: Colors.blue.shade600, width: 1.5),
            borderRadius: BorderRadius.circular(15),
            image: capturedImage != null
                ? DecorationImage(
              image: FileImage(capturedImage!),
              fit: BoxFit.cover,
            )
                : null,
          ),
          child: capturedImage == null
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
          // Show progress only if image is captured but not yet uploaded
              : (uploadedImageUrl == null
              ? Center(child: CircularProgressIndicator(color: Colors.white))
              : Container()), // Show nothing if uploaded
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0;

    return Form(
      key: formKey, // Use the passed key
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
        child: Stack(
          children: [
            Positioned(
              top: 15,
              left: -10,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.blue.shade800, size: 28),
                onPressed: onBack, // Use the callback
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
                    _buildImagePicker(context, screenWidth), // Pass context
                    const SizedBox(height: 25.0),
                    FutureBuilder<List<String>>(
                      future: medicineNamesFuture, // Use the passed future
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
                            controller: nameController, // Use the passed controller
                            focusNode: FocusNode(), // Can create a local one here
                            onSelected: (selection) {
                              nameController.text = selection; // Update controller
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
                        // Validate using the passed key before calling the callback
                        if (formKey.currentState!.validate()) {
                          onNext(); // Use the callback
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
}