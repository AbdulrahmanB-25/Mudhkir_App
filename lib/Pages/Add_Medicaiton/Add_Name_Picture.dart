import 'dart:io';
import 'package:flutter/material.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

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
  final int _initialDisplayCount = 3;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_filter);
    widget.focusNode.addListener(_handleFocusChange);
    _filter();
  }

  void _filter() {
    final text = widget.controller.text.toLowerCase().trim();
    if (mounted) {
      setState(() {
        if (text.isEmpty) {
          _filteredSuggestions = [];
        } else {
          _filteredSuggestions = widget.suggestions
              .where((s) => s.toLowerCase().contains(text))
              .toList();
        }
      });
    }
  }

  void _handleFocusChange() {
    if (!widget.focusNode.hasFocus && mounted) {
      setState(() {
        _filteredSuggestions = [];
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_filter);
    widget.focusNode.removeListener(_handleFocusChange);
    _scrollController.dispose();
    super.dispose();
  }

  Widget _highlightMatchingText(String text, String query) {
    if (query.isEmpty || !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(
        text,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    List<TextSpan> spans = [];
    int start = 0;
    final textLower = text.toLowerCase();
    final queryLower = query.toLowerCase();
    int indexOfMatch;

    while ((indexOfMatch = textLower.indexOf(queryLower, start)) != -1) {
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
      spans.add(TextSpan(
        text: text.substring(indexOfMatch, indexOfMatch + query.length),
        style: const TextStyle(
          color: kPrimaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ));
      start = indexOfMatch + query.length;
    }

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
    final bool hasMoreResults = _filteredSuggestions.length > _initialDisplayCount;
    final int displayItemCount = _filteredSuggestions.isEmpty ? 0 : _filteredSuggestions.length.clamp(1, _initialDisplayCount);
    final double calculatedHeight = displayItemCount * 60.0;
    final double totalHeight = calculatedHeight + (hasMoreResults && displayItemCount > 0 ? 30.0 : 0.0);


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
              tooltip: 'Clear search',
              onPressed: () {
                widget.controller.clear();
                widget.focusNode.requestFocus();
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
          onChanged: (text) {},
        ),
        if (widget.focusNode.hasFocus && _filteredSuggestions.isNotEmpty)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
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
            height: totalHeight >= 0 ? totalHeight : 0,
            child: totalHeight > 0 ? Stack(
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
                      padding: EdgeInsets.only(bottom: (hasMoreResults ? 30 : 0)),
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
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              widget.onSelected(suggestion);
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
                          ),
                        );
                      },
                    ),
                  ),
                ),

                if (hasMoreResults)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 30,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.8),
                              Colors.white.withOpacity(1.0),
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(kBorderRadius),
                            bottomRight: Radius.circular(kBorderRadius),
                          ),
                          border: Border(
                            top: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            "مرر لأسفل لمزيد من النتائج (${_filteredSuggestions.length - _initialDisplayCount}+)",
                            style: TextStyle(
                              fontSize: 12,
                              color: kSecondaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ) : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

class AddNamePicturePage extends StatefulWidget {
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

  @override
  _AddNamePicturePageState createState() => _AddNamePicturePageState();
}

class _AddNamePicturePageState extends State<AddNamePicturePage> {
  late FocusNode _medicineFocusNode;

  @override
  void initState() {
    super.initState();
    _medicineFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _medicineFocusNode.dispose();
    super.dispose();
  }

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
              onTap: widget.onPickImage,
              child: Container(
                height: screenWidth * 0.45,
                width: screenWidth * 0.7,
                decoration: BoxDecoration(
                  color: kCardColor,
                  border: Border.all(
                    color: widget.capturedImage != null || widget.uploadedImageUrl != null
                        ? kPrimaryColor
                        : Colors.grey.shade300,
                    width: widget.capturedImage != null || widget.uploadedImageUrl != null ? 2.0 : 1.0,
                  ),
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  image: widget.capturedImage != null
                      ? DecorationImage(
                    image: FileImage(widget.capturedImage!),
                    fit: BoxFit.cover,
                  )
                      : (widget.uploadedImageUrl != null
                      ? DecorationImage(
                    image: NetworkImage(widget.uploadedImageUrl!),
                    fit: BoxFit.cover,
                  )
                      : null),
                ),
                child: widget.capturedImage == null && widget.uploadedImageUrl == null
                    ? Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
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
                    Positioned(
                      bottom: screenWidth * 0.08,
                      child: Text(
                        'اضغط لالتقاط صورة للدواء',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: screenWidth * 0.035,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                )
                    : (widget.uploadedImageUrl == null
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

          if (widget.capturedImage == null)
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
      key: widget.formKey,
      child: Container(
        decoration: const BoxDecoration(
          color: kBackgroundColor,
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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

                  _buildImagePicker(context, screenWidth),

                  const SizedBox(height: 25.0),

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

                        FutureBuilder<List<String>>(
                          future: widget.medicineNamesFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: kPrimaryColor,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        "جاري تحميل قائمة الأدوية...",
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
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
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline, color: kErrorColor, size: 36),
                                    const SizedBox(height: 8),
                                    Text(
                                      'خطأ في تحميل أسماء الأدوية.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: const Color(0xFFD32F2F), // Dark red color instead of shade900
                                          fontWeight: FontWeight.w500
                                      ),
                                    ),
                                    Text(
                                      '${snapshot.error}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: const Color(0xFFE57373), // Lighter red color instead of shade700
                                          fontSize: 11
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              );
                            } else {
                              final medicineNames = snapshot.data ?? [];
                              return MedicineAutocomplete(
                                suggestions: medicineNames,
                                controller: widget.nameController,
                                focusNode: _medicineFocusNode,
                                onSelected: (selection) {
                                  widget.nameController.text = selection;
                                  _medicineFocusNode.unfocus();
                                },
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30.0),

                  ElevatedButton(
                    onPressed: () {
                      if (widget.formKey.currentState!.validate()) {
                        _medicineFocusNode.unfocus();
                        widget.onNext();
                      } else {
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
                          child: const Icon(Icons.arrow_forward, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
