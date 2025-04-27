import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'Companion_Details_Page.dart';
import '../Companions_Utilly/CompanionMedications_Addation.dart';
import 'dart:ui' as ui;

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kErrorColor = Color(0xFFFF6B6B);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const Color kCardColor = Colors.white;
const double kBorderRadius = 16.0;
const double kSpacing = 16.0;

class Companions extends StatefulWidget {
  const Companions({super.key});

  @override
  State<Companions> createState() => _CompanionsState();
}

class _CompanionsState extends State<Companions> with SingleTickerProviderStateMixin {
  final user = FirebaseAuth.instance.currentUser;
  late CollectionReference companionsRef;
  List<Map<String, dynamic>> companionDataList = [];
  bool isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    
    if (user != null) {
      companionsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('companions');
      _loadCompanions();
    }
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanions() async {
    setState(() => isLoading = true);
    final snapshot = await companionsRef.get();
    List<Map<String, dynamic>> tempList = [];

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final email = data['email'];
      final name = data['name'];
      final relationship = data['relationship'] ?? '';
      final lastSeen = data['lastSeen'] as Timestamp?;
      int upcomingDoseCount = await _getUpcomingDoseCount(email);

      tempList.add({
        'docId': doc.id,
        'name': name,
        'email': email,
        'relationship': relationship,
        'lastSeen': lastSeen?.toDate(),
        'upcomingDoseCount': upcomingDoseCount,
      });
    }

    setState(() {
      companionDataList = tempList;
      isLoading = false;
    });
  }

  Future<int> _getUpcomingDoseCount(String email) async {
    int count = 0;

    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return 0;

    final companionId = query.docs.first.id;

    final medsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(companionId)
        .collection('medicines')
        .get();

    final today = DateTime.now();

    for (var doc in medsSnapshot.docs) {
      final data = doc.data();
      final missedDoses = (data['missedDoses'] as List?) ?? [];

      for (var dose in missedDoses) {
        final ts = dose['scheduled'] as Timestamp?;
        final status = dose['status'];

        if (ts != null &&
            status == 'pending' &&
            ts.toDate().isAfter(today.subtract(const Duration(days: 1)))) {
          count++;
        }
      }
    }

    return count;
  }

  Future<void> _deleteCompanion(String id) async {
    try {
      await companionsRef.doc(id).delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("تم حذف المرافق بنجاح"),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(10),
        ),
      );

      _loadCompanions();
    } catch (e) {
      print("Error deleting companion: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("حدث خطأ أثناء حذف المرافق: ${e.toString()}"),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(10),
        ),
      );
    }
  }

  void _navigateToDetail(Map<String, dynamic> companion) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompanionDetailPage(
          email: companion['email'],
          name: companion['name'],
        ),
      ),
    ).then((_) => _loadCompanions());
  }

  void _navigateToAddMedication(String companionId, String companionName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompanionMedicationsPage(
          companionId: companionId,
          companionName: companionName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text(
            "المرافقين",
            style: TextStyle(fontWeight: FontWeight.bold, shadows: [Shadow(color: Colors.white, blurRadius: 15)]),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: kPrimaryColor),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8), kBackgroundColor.withOpacity(0.9), kBackgroundColor],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.3, 0.7, 1.0],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeInAnimation,
              child: isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          "جاري تحميل المرافقين...",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  )
                : companionDataList.isEmpty
                    ? _buildEmptyState()
                    : _buildCompanionsList(),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddCompanionDialog,
          backgroundColor: kPrimaryColor,
          child: const Icon(Icons.person_add),
          tooltip: "إضافة مرافق",
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 80,
                color: kPrimaryColor,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              "لا يوجد مرافقين حالياً",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(kBorderRadius),
              ),
              child: Text(
                "أضف مرافقين لمساعدتك في متابعة أدويتك",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text("إضافة مرافق جديد"),
              onPressed: _showAddCompanionDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                elevation: 5,
                shadowColor: kPrimaryColor.withOpacity(0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanionsList() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 25),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 16),
            child: Text(
              "المرافقين المسجلين",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: companionDataList.length,
              itemBuilder: (context, index) {
                final companion = companionDataList[index];
                return Dismissible(
                  key: Key(companion['docId']),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.delete_rounded, color: Colors.white),
                  ),
                  confirmDismiss: (direction) async {
                    return await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("تأكيد الحذف"),
                        titleTextStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                          fontSize: 20,
                        ),
                        content: const Text("هل تريد بالتأكيد حذف هذا المرافق؟"),
                        contentTextStyle: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text("إلغاء"),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey.shade700,
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text("نعم، حذف"),
                            onPressed: () => Navigator.pop(context, true),
                          ),
                        ],
                      ),
                    );
                  },
                  onDismissed: (_) => _deleteCompanion(companion['docId']),
                  child: _buildCompanionCard(companion),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanionCard(Map<String, dynamic> companion) {
    final name = companion['name'] ?? '';
    final email = companion['email'] ?? '';
    final docId = companion['docId'] ?? '';
    final initials = name.isNotEmpty
        ? name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
        : '?';
    final relationship = companion['relationship'] ?? '';
    final lastSeen = companion['lastSeen'] as DateTime?;
    final isOnline = lastSeen != null &&
        DateTime.now().difference(lastSeen).inMinutes <= 5;
    final doseCount = companion['upcomingDoseCount'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withOpacity(0.1),
            blurRadius: 8, 
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: kSecondaryColor.withOpacity(0.2), width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kBorderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kBorderRadius),
          onTap: () => _navigateToDetail(companion),
          onLongPress: () => _navigateToAddMedication(docId, name),
          splashColor: kPrimaryColor.withOpacity(0.1),
          highlightColor: kPrimaryColor.withOpacity(0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildCompanionAvatar(initials, isOnline),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.email_outlined,
                            size: 14,
                            color: kSecondaryColor,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (relationship.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.people_alt_outlined,
                              size: 14,
                              color: kSecondaryColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              relationship,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (doseCount > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: kSecondaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kSecondaryColor.withOpacity(0.3), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: kPrimaryColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "$doseCount جرعة قادمة",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: kPrimaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _buildActionButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompanionAvatar(String initials, bool isOnline) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [kPrimaryColor, kSecondaryColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: CircleAvatar(
            backgroundColor: Colors.transparent,
            radius: 26,
            child: Text(
              initials.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.red.shade400,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton() {
    return Container(
      decoration: BoxDecoration(
        color: kSecondaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.chevron_left,
        color: kPrimaryColor,
      ),
    );
  }

  void _showAddCompanionDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final relationshipController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kPrimaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add, color: kPrimaryColor),
            ),
            const SizedBox(width: 12),
            const Text("إضافة مرافق"),
          ],
        ),
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          color: kPrimaryColor,
          fontSize: 20,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                TextFormField(
                  controller: nameController,
                  textDirection: ui.TextDirection.rtl,
                  decoration: InputDecoration(
                    labelText: "الاسم",
                    prefixIcon: const Icon(Icons.person, color: kSecondaryColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kPrimaryColor, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "الرجاء إدخال الاسم";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: ui.TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: "البريد الإلكتروني",
                    prefixIcon: const Icon(Icons.email, color: kSecondaryColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kPrimaryColor, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "الرجاء إدخال البريد الإلكتروني";
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return "الرجاء إدخال بريد إلكتروني صالح";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: relationshipController,
                  textDirection: ui.TextDirection.rtl,
                  decoration: InputDecoration(
                    labelText: "صلة القرابة (اختياري)",
                    hintText: "مثال: زوجة، ابن، أخ",
                    prefixIcon: const Icon(Icons.people_alt_outlined, color: kSecondaryColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kPrimaryColor, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                ),
              ],
            ),
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actions: [
          TextButton(
            child: const Text("إلغاء"),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text("إضافة"),
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                await companionsRef.add({
                  'name': nameController.text.trim(),
                  'email': emailController.text.trim(),
                  'relationship': relationshipController.text.trim(),
                  'lastSeen': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
                _loadCompanions();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("تمت إضافة المرافق بنجاح"),
                    backgroundColor: Colors.green.shade700,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    margin: const EdgeInsets.all(10),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
