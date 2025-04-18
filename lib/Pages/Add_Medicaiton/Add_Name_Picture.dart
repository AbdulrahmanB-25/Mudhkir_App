import 'dart:io';
import 'package:flutter/material.dart';

// Constants for theming
// Hospital Blue Color Theme
const Color kPrimaryColor = Color(0xFF2E86C1); // Medium hospital blue
const Color kSecondaryColor = Color(0xFF5DADE2); // Light hospital blue
const Color kErrorColor = Color(0xFFFF6B6B); // Error red
const Color kBackgroundColor = Color(0xFFF5F8FA); // Very light blue-gray background
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

// --- Medicine Autocomplete Widget ---
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
  final int _initialDisplayCount = 3; // Number of items to show initially

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
          // Get all matches, not limited to 3
          _filteredSuggestions = widget.suggestions
              .where((s) => s.toLowerCase().contains(text))
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

  // Highlights matching text in blue
  Widget _highlightMatchingText(String text, String query) {
    if (query.isEmpty) return Text(text);

    List<TextSpan> spans = [];
    int start = 0;
    final textLower = text.toLowerCase();
    final queryLower = query.toLowerCase();

    // Find all occurrences of the query in the text
    int indexOfMatch = textLower.indexOf(queryLower);
    while (indexOfMatch != -1) {
      // Add text before the match
      if (indexOfMatch > start) {
        spans.add(TextSpan(
          text: text.substring(start, indexOfMatch),
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ));
      }

      // Add the highlighted match
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + query.length),
        style: const TextStyle(
          color: kPrimaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ));

      // Move to the next potential match
      start = indexOfMatch + query.length;
      indexOfMatch = textLower.indexOf(queryLower, start);
    }

    // Add any remaining text
    if (start < text.length) {
      spans.add(TextSpan(
        text: text.substring(start),
        style: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate the number of results to display in the UI
    final bool hasMoreResults = _filteredSuggestions.length > _initialDisplayCount;
    final int displayHeight = _filteredSuggestions.isEmpty
        ? 0
        : (_filteredSuggestions.length.clamp(1, _initialDisplayCount) * 60.0).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            labelText: 'اسم الدواء',
            labelStyle: TextStyle(
              color: kPrimaryColor.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
            hintText: 'ابحث عن اسم الدواء...',
            hintStyle: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Icon(Icons.search, color: kPrimaryColor),
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
              icon: Icon(Icons.clear, color: kErrorColor),
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
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kBorderRadius),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kBorderRadius),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kBorderRadius),
              borderSide: BorderSide(color: kPrimaryColor, width: 2.0),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kBorderRadius),
              borderSide: BorderSide(color: kErrorColor, width: 1.5),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kBorderRadius),
              borderSide: BorderSide(color: kErrorColor, width: 2.0),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            errorStyle: TextStyle(
              color: kErrorColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          validator: (value) =>
          (value == null || value.trim().isEmpty) ? 'الرجاء إدخال اسم الدواء' : null,
        ),
        if (_filteredSuggestions.isNotEmpty)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(kBorderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            height: displayHeight + (hasMoreResults ? 30 : 0), // Add extra space for the "more results" indicator
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    thickness: 6.0,
                    radius: const Radius.circular(10),
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: _filteredSuggestions.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: Colors.grey.shade200,
                        indent: 16,
                        endIndent: 16,
                      ),
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Icon(
                                    Icons.medication_outlined,
                                    color: kPrimaryColor.withOpacity(0.7),
                                    size: 20
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _highlightMatchingText(suggestion, widget.controller.text),
                                ),
                                Icon(Icons.arrow_forward_ios, color: Colors.grey.shade500, size: 14),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // "More results" indicator if there are more than 3 results
                if (hasMoreResults)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          "مرر لأسفل لمزيد من النتائج (${_filteredSuggestions.length - _initialDisplayCount})",
                          style: TextStyle(
                            fontSize: 12,
                            color: kSecondaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
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
  final String? uploadedImageUrl;
  final VoidCallback onPickImage;
  final VoidCallback onNext;
  final VoidCallback onBack;

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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt, color: kPrimaryColor),
              const SizedBox(width: 10),
              Text(
                "صورة الدواء",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),

          const Divider(height: 24),

          Center(
            child: GestureDetector(
              onTap: onPickImage,
              child: Container(
                height: screenWidth * 0.45,
                width: screenWidth * 0.7,
                decoration: BoxDecoration(
                  color: kCardColor,
                  border: Border.all(
                    color: capturedImage != null ? kPrimaryColor : Colors.grey.shade300,
                    width: capturedImage != null ? 2.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  image: capturedImage != null
                      ? DecorationImage(
                    image: FileImage(capturedImage!),
                    fit: BoxFit.cover,
                  )
                      : null,
                ),
                child: capturedImage == null
                    ? Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pulsing animation effect for camera icon
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0.8, end: 1.0),
                      duration: const Duration(seconds: 2),
                      curve: Curves.easeInOut,
                      builder: (context, value, child) {
                        return Transform.scale(
                          scale: value,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kPrimaryColor.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.camera_alt_outlined,
                              color: kPrimaryColor,
                              size: screenWidth * 0.1,
                            ),
                          ),
                        );
                      },
                      child: Container(),
                    ),
                    Positioned(
                      bottom: screenWidth * 0.08,
                      child: Text(
                        'اضغط لالتقاط صورة للدواء',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: screenWidth * 0.04,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                )
                    : (uploadedImageUrl == null
                    ? Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                    ),
                    child: const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                  ),
                )
                    : Stack(
                  children: [
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                )),
              ),
            ),
          ),

          // Optional hint text
          if (capturedImage == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: kSecondaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(kBorderRadius / 2),
                    border: Border.all(color: kSecondaryColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, color: kSecondaryColor, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        "أضف صورة لمساعدتك في التعرف على الدواء",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth * 0.06;
    const verticalPadding = 20.0;

    return Form(
      key: formKey,
      child: Container(
        decoration: const BoxDecoration(
          color: kBackgroundColor,
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Back button with consistent design
              Positioned(
                top: 15,
                left: 10,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(30),
                  child: InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back, color: kPrimaryColor, size: 28),
                    ),
                  ),
                ),
              ),

              // Main content
              Padding(
                padding: EdgeInsets.only(
                  left: horizontalPadding,
                  right: horizontalPadding,
                  top: verticalPadding + 35, // Add space for back button
                  bottom: verticalPadding,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Page title with gradient effect - matching AddDosagePage
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [kPrimaryColor, Color(0xFF4E7BFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: Text(
                          "إضافة دواء جديد",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: screenWidth * 0.07,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Subtitle - matching style with AddDosagePage
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          "أدخل اسم الدواء والتقط صورة له",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.normal,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),

                      const SizedBox(height: 25.0),

                      // Image section in card
                      _buildImagePicker(context, screenWidth),

                      const SizedBox(height: 25.0),

                      // Medicine name search with consistent card style
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kCardColor,
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.medication, color: kPrimaryColor),
                                const SizedBox(width: 10),
                                Text(
                                  "اسم الدواء",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ],
                            ),

                            const Divider(height: 24),

                            // Medicine name autocomplete
                            FutureBuilder<List<String>>(
                              future: medicineNamesFuture,
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return Center(
                                    child: Column(
                                      children: [
                                        const SizedBox(height: 20),
                                        const CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: kPrimaryColor,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "جاري تحميل قائمة الأدوية...",
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                      ],
                                    ),
                                  );
                                } else if (snapshot.hasError) {
                                  return Container(
                                    padding: const EdgeInsets.all(16.0),
                                    decoration: BoxDecoration(
                                      color: kErrorColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(kBorderRadius),
                                      border: Border.all(color: kErrorColor.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(Icons.error_outline, color: kErrorColor, size: 36),
                                        const SizedBox(height: 8),
                                        Text(
                                          'خطأ في تحميل أسماء الأدوية: ${snapshot.error}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: kErrorColor),
                                        ),
                                        const SizedBox(height: 8),
                                        ElevatedButton(
                                          onPressed: () {
                                            // Reload medicine names
                                            // (Would need to implement if desired)
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kErrorColor,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(kBorderRadius/2),
                                            ),
                                          ),
                                          child: const Text('إعادة المحاولة'),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  final medicineNames = snapshot.data ?? [];
                                  return MedicineAutocomplete(
                                    suggestions: medicineNames,
                                    controller: nameController,
                                    focusNode: FocusNode(),
                                    onSelected: (selection) {
                                      nameController.text = selection;
                                      FocusScope.of(context).unfocus();
                                    },
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 30.0),

                      // Next button with consistent styling across all pages
                      ElevatedButton(
                        onPressed: () {
                          if (formKey.currentState!.validate()) {
                            onNext();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 55),
                          backgroundColor: kPrimaryColor,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shadowColor: kPrimaryColor.withOpacity(0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'التالي',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_forward, size: 16),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}