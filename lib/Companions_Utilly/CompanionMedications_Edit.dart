import 'package:flutter/material.dart';
import '../Pages/EditMedication_Page.dart';
import '../services/AlarmNotificationHelper.dart';

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 18.0;

class CompanionMedicationsEditPage extends StatefulWidget {
  final String companionId;
  final String medicationId;
  final String companionName;

  const CompanionMedicationsEditPage({
    Key? key,
    required this.companionId,
    required this.medicationId,
    required this.companionName,
  }) : super(key: key);

  @override
  _CompanionMedicationsEditPageState createState() => _CompanionMedicationsEditPageState();
}

class _CompanionMedicationsEditPageState extends State<CompanionMedicationsEditPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isRescheduling = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 500)
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _rescheduleNotifications() async {
    setState(() => _isRescheduling = true);
    
    try {
      await AlarmNotificationHelper.cancelAllNotifications();
      await AlarmNotificationHelper.scheduleAlarmNotification(
        id: AlarmNotificationHelper.generateNotificationId(widget.medicationId, DateTime.now()),
        title: "💊 تذكير بجرعة دواء",
        body: "تم تحديث بيانات الدواء. تأكد من الجرعات الجديدة.",
        scheduledTime: DateTime.now().add(const Duration(seconds: 5)), // Example time
        medicationId: widget.medicationId,
      );
      
      if (mounted) {
        _showSuccessSnackBar("تم تحديث بيانات الدواء وإعادة جدولة الإشعارات بنجاح");
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar("حدث خطأ أثناء إعادة جدولة الإشعارات: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isRescheduling = false);
      }
    }
  }
  
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(10),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'تم',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }
  
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: kErrorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(10),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'حسناً',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: null,
      body: Stack(
        children: [
          // Background decoration with consistent gradient
          Container(
            height: MediaQuery.of(context).size.height * 0.12,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2E86C1), Color(0xFF2E86C1).withOpacity(0.8)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          
          // Main content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  // Consistent header styling
                  Container(
                    padding: EdgeInsets.fromLTRB(8, 0, 8, 0), // Removed bottom padding
                    child: Row(
                      children: [
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => Navigator.pop(context),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        
                        Expanded(
                          child: Text(
                            "تعديل دواء لـ ${widget.companionName}",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                              color: Colors.white,
                              shadows: [Shadow(color: Colors.black26, blurRadius: 2)],
                            ),
                          ),
                        ),
                        
                        SizedBox(width: 40),
                      ],
                    ),
                  ),
                  
                  // EditMedicationScreen
                  Expanded(
                    child: EditMedicationScreen(
                      docId: widget.medicationId,
                      companionId: widget.companionId,
                      onSave: _rescheduleNotifications,
                      buttonText: "تعديل الدواء", // This now correctly uses the parameter we added
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Loading overlay
          if (_isRescheduling)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          color: kPrimaryColor,
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          "جاري إعادة جدولة الإشعارات...",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "سيتم تطبيق التغييرات قريباً",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
