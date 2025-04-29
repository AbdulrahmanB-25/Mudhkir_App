import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'dart:ui' as ui;
import '../Edit/EditMedication_Page.dart';
import 'dose_schedule_services.dart';
import 'time_utils.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const double kBorderRadius = 16.0;
const double kSpacing = 16.0;

class EnlargeableImage extends StatefulWidget {
  final String imageUrl;
  final double width;
  final double height;
  final String docId;

  const EnlargeableImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.docId,
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
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, animation, __) {
          return FadeTransition(
            opacity: animation,
            child: Directionality(
              textDirection: ui.TextDirection.rtl,
              child: Scaffold(
                backgroundColor: Colors.black.withOpacity(0.85),
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  iconTheme: IconThemeData(color: kSecondaryColor),
                  leading: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                body: Center(
                  child: Hero(
                    tag: 'medication_image_${widget.docId}_${widget.imageUrl.hashCode}',
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.file(imageFile),
                    ),
                  ),
                ),
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
              color: kSecondaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(kBorderRadius),
            ),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: kPrimaryColor,
                ),
              ),
            ),
          );
        } else if (snapshot.hasData && snapshot.data != null) {
          return Hero(
            tag: 'medication_image_${widget.docId}_${widget.imageUrl.hashCode}',
            child: GestureDetector(
              onTap: () => _openEnlargedImage(context, snapshot.data!),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withOpacity(0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kBorderRadius),
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
        color: kSecondaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: kSecondaryColor.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            showErrorText ? Icons.broken_image_rounded : Icons.medication_rounded,
            color: kSecondaryColor.withOpacity(0.5),
            size: widget.width * 0.4,
          ),
          if (showErrorText) const SizedBox(height: 4),
          if (showErrorText)
            Text(
              "لا توجد صورة",
              style: TextStyle(
                fontSize: 10,
                color: kSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

class DoseTile extends StatefulWidget {
  final String medicationName;
  final String nextDose;
  final String docId;
  final String imageUrl;
  final String imgbbDeleteHash;
  final VoidCallback onDataChanged;
  final DateTime selectedDay;

  const DoseTile({
    super.key,
    required this.medicationName,
    required this.nextDose,
    required this.docId,
    required this.imageUrl,
    required this.imgbbDeleteHash,
    required this.onDataChanged,
    required this.selectedDay,
  });

  @override
  _DoseTileState createState() => _DoseTileState();
}

class _DoseTileState extends State<DoseTile> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  String _doseStatus = 'pending';
  bool _isLoadingStatus = true;
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  late DoseScheduleServices _services;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _services = DoseScheduleServices(user: FirebaseAuth.instance.currentUser);
    _checkDoseStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DoseTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.docId != widget.docId ||
        oldWidget.nextDose != widget.nextDose ||
        !_isSameDay(oldWidget.selectedDay, widget.selectedDay)) {
      _checkDoseStatus();
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month && date1.day == date2.day;
  }

  Future<void> _checkDoseStatus() async {
    if (!mounted) return;
    setState(() => _isLoadingStatus = true);

    final status = await _services.checkDoseStatus(
        widget.docId,
        widget.nextDose,
        widget.selectedDay
    );

    if (mounted) {
      setState(() {
        _doseStatus = status;
        _isLoadingStatus = false;
      });
    }
  }

  Future<void> _toggleDoseStatus() async {
    setState(() => _isLoadingStatus = true);

    final success = await _services.toggleDoseStatus(
        widget.docId,
        widget.nextDose,
        widget.selectedDay,
        _doseStatus
    );

    if (mounted) {
      if (success) {
        setState(() {
          _doseStatus = _doseStatus == 'taken' ? 'pending' : 'taken';
          _isLoadingStatus = false;
        });
        widget.onDataChanged();
      } else {
        setState(() => _isLoadingStatus = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("فشل تحديث حالة الجرعة"),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            )
        );
        _checkDoseStatus();
      }
    }
  }

  Future<bool?> _showConfirmationDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmText,
    Color confirmButtonColor = Colors.red,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.right,
        ),
        content: Text(
          content,
          style: const TextStyle(color: Colors.black87),
          textAlign: TextAlign.right,
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmButtonColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<void> _handleEdit(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "تعديل الدواء",
      content: "هل تريد الانتقال إلى شاشة تعديل بيانات هذا الدواء؟",
      confirmText: "نعم، تعديل",
      confirmButtonColor: Colors.blue.shade700,
    );

    if (confirmed == true && mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EditMedicationScreen(docId: widget.docId),
        ),
      );
      widget.onDataChanged();
    }
  }

  Future<void> _handleFinishMed(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "إنهاء الدواء",
      content: "هل أنت متأكد من إنهاء جدول هذا الدواء؟ سيتم تحديد تاريخ الانتهاء إلى ${DateFormat('EEEE, d MMMM yyyy', 'ar_SA').format(widget.selectedDay)} ولن يظهر في الأيام التالية.",
      confirmText: "نعم، إنهاء",
      confirmButtonColor: Colors.orange.shade700,
    );

    if (confirmed == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: kPrimaryColor),
                const SizedBox(height: 16),
                const Text("جاري إنهاء الدواء..."),
              ],
            ),
          ),
        ),
      );

      final success = await _services.finishMedication(widget.docId, widget.selectedDay);

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("تم إنهاء الدواء بتاريخ ${DateFormat('d MMMM', 'ar_SA').format(widget.selectedDay)}"),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
          widget.onDataChanged();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("فشل إنهاء الدواء"),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              )
          );
        }
      }
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await _showConfirmationDialog(
      context: context,
      title: "تأكيد الحذف",
      content: "هل أنت متأكد من حذف هذا الدواء؟ سيتم حذف صورته أيضاً إذا كانت مرتبطة (لا يمكن التراجع عن هذا الإجراء).",
      confirmText: "نعم، حذف",
      confirmButtonColor: Colors.red.shade700,
    );

    if (confirmed == true) {
      await _deleteMedication(context);
    }
  }

  Future<void> _deleteMedication(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: kPrimaryColor),
              const SizedBox(height: 16),
              const Text("جاري حذف الدواء..."),
            ],
          ),
        ),
      ),
    );

    final success = await _services.deleteMedication(
        widget.docId,
        widget.imgbbDeleteHash
    );

    if (mounted) {
      Navigator.of(context).pop(); // Close loading dialog

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("تم حذف الدواء بنجاح"),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        widget.onDataChanged();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("فشل حذف الدواء"),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            )
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpanded) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }

    return Card(
      elevation: 2,
      shadowColor: kPrimaryColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kBorderRadius),
        side: BorderSide(
          color: _doseStatus == 'taken'
              ? Colors.green.shade300.withOpacity(0.5)
              : kSecondaryColor.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kBorderRadius),
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        splashColor: kPrimaryColor.withOpacity(0.05),
        highlightColor: kPrimaryColor.withOpacity(0.05),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: _doseStatus == 'taken'
                    ? Colors.green.shade50.withOpacity(0.3)
                    : Colors.transparent,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(kBorderRadius),
                  bottom: _isExpanded ? Radius.zero : Radius.circular(kBorderRadius),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _isLoadingStatus
                      ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimaryColor,
                    ),
                  )
                      : IconButton(
                    icon: Icon(
                      _doseStatus == 'taken'
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 28,
                      color: _doseStatus == 'taken'
                          ? Colors.green.shade600
                          : Colors.grey.shade400,
                    ),
                    onPressed: _toggleDoseStatus,
                    padding: EdgeInsets.zero,
                    tooltip: _doseStatus == 'taken' ? "تم أخذ الجرعة" : "لم تؤخذ الجرعة بعد",
                  ),
                  const SizedBox(width: 12),

                  EnlargeableImage(
                    imageUrl: widget.imageUrl,
                    width: 50,
                    height: 50,
                    docId: widget.docId,
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.medicationName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: kSecondaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.nextDose,
                              style: TextStyle(
                                fontSize: 14,
                                color: kSecondaryColor,
                              ),
                            ),
                            if (_doseStatus == 'taken')
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "تم",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5)
                        .animate(_animationController),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: kPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),

            SizeTransition(
              sizeFactor: _expandAnimation,
              child: Container(
                decoration: BoxDecoration(
                  color: kSecondaryColor.withOpacity(0.05),
                  border: Border(
                    top: BorderSide(
                      color: kSecondaryColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(kBorderRadius),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      label: "تعديل",
                      icon: Icons.edit_rounded,
                      color: kPrimaryColor,
                      onPressed: () => _handleEdit(context),
                    ),
                    _buildActionButton(
                      label: "إنهاء",
                      icon: Icons.event_busy_rounded,
                      color: Colors.orange.shade700,
                      onPressed: () => _handleFinishMed(context),
                    ),
                    _buildActionButton(
                      label: "حذف",
                      icon: Icons.delete_rounded,
                      color: Colors.red.shade700,
                      onPressed: () => _handleDelete(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 18),
      label: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class CalendarWidget extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final CalendarFormat calendarFormat;
  final Function(DateTime, DateTime) onDaySelected;
  final Function(CalendarFormat) onFormatChanged;
  final Function(DateTime) onPageChanged;
  final Function(DateTime) getEventsForDay;

  const CalendarWidget({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.calendarFormat,
    required this.onDaySelected,
    required this.onFormatChanged,
    required this.onPageChanged,
    required this.getEventsForDay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kBorderRadius),
        child: TableCalendar<Map<String, dynamic>>(
          locale: 'ar_SA',
          firstDay: DateTime.utc(DateTime.now().year - 1, 1, 1),
          lastDay: DateTime.utc(DateTime.now().year + 2, 12, 31),
          focusedDay: focusedDay,
          calendarFormat: calendarFormat,
          eventLoader: (day) => getEventsForDay(day),
          selectedDayPredicate: (day) => isSameDay(selectedDay, day),
          onDaySelected: onDaySelected,
          onFormatChanged: onFormatChanged,
          onPageChanged: onPageChanged,
          availableCalendarFormats: const {
            CalendarFormat.month: 'اسبوع',
            CalendarFormat.week: 'شهر',
          },
          headerStyle: HeaderStyle(
            titleCentered: true,
            formatButtonVisible: true,
            formatButtonDecoration: BoxDecoration(
              color: kSecondaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            formatButtonTextStyle: TextStyle(
              color: kPrimaryColor,
              fontWeight: FontWeight.bold,
            ),
            titleTextStyle: TextStyle(
              color: kPrimaryColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            leftChevronIcon: Icon(Icons.chevron_left, color: kPrimaryColor),
            rightChevronIcon: Icon(Icons.chevron_right, color: kPrimaryColor),
            headerPadding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: kSecondaryColor.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
          ),
          daysOfWeekStyle: DaysOfWeekStyle(
            weekdayStyle: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
            weekendStyle: TextStyle(
              color: Colors.red.shade300,
              fontWeight: FontWeight.bold,
            ),
            decoration: BoxDecoration(
              color: kSecondaryColor.withOpacity(0.05),
            ),
          ),
          calendarStyle: CalendarStyle(
            outsideDaysVisible: false,
            defaultDecoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
            ),
            weekendDecoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
            ),
            todayDecoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kPrimaryColor,
            ),
            selectedDecoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kSecondaryColor,
            ),
            markerDecoration: BoxDecoration(
              color: Colors.orange.shade400,
              shape: BoxShape.circle,
            ),
            markerSize: 5,
            markersMaxCount: 3,
            cellMargin: const EdgeInsets.all(6),
            todayTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            selectedTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, events) {
              if (events.isEmpty) return const SizedBox();

              return Positioned(
                bottom: 1,
                child: Container(
                  width: events.length > 2 ? 16 : 12,
                  height: 4,
                  decoration: BoxDecoration(
                    color: events.any((e) => e['isImportant'] == true)
                        ? Colors.orange.shade400
                        : kSecondaryColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            },
            defaultBuilder: (context, day, focusedDay) {
              final events = getEventsForDay(day);
              if (events.isNotEmpty) {
                return Container(
                  margin: const EdgeInsets.all(5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: kSecondaryColor.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: kPrimaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }
              return null;
            },
          ),
        ),
      ),
    );
  }
}