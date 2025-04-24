import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'CompanionDetailPage.dart';
import 'dart:ui' as ui;

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const Color kBackgroundColor = Color(0xFFF5F8FA);
const double kBorderRadius = 16.0;
const double kSpacing = 16.0;

class Companions extends StatefulWidget {
  const Companions({super.key});

  @override
  State<Companions> createState() => _CompanionsState();
}

class _CompanionsState extends State<Companions> {
  final user = FirebaseAuth.instance.currentUser;
  late CollectionReference companionsRef;
  List<Map<String, dynamic>> companionDataList = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    if (user != null) {
      companionsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('companions');
      _loadCompanions();
    }
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
    await companionsRef.doc(id).delete();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("تم حذف المرافق"),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(10),
      ),
    );
    _loadCompanions();
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
    ).then((_) => _loadCompanions()); // Refresh data when returning
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        appBar: AppBar(
          title: const Text(
            "المرافقين",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: kPrimaryColor,
          elevation: 2,
          centerTitle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(kBorderRadius),
            ),
          ),
        ),
        body: isLoading
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: kPrimaryColor),
              const SizedBox(height: 16),
              Text(
                "جاري تحميل المرافقين...",
                style: TextStyle(
                  color: kPrimaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        )
            : companionDataList.isEmpty
            ? _buildEmptyState()
            : _buildCompanionsList(),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kSecondaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 60,
                color: kSecondaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "لا يوجد مرافقين حالياً",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kPrimaryColor.withOpacity(0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              "أضف مرافقين لمساعدتك في متابعة أدويتك",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text("إضافة مرافق"),
              onPressed: _showAddCompanionDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                elevation: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanionsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
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
    );
  }

  Widget _buildCompanionCard(Map<String, dynamic> companion) {
    final name = companion['name'] ?? '';
    final initials = name.isNotEmpty
        ? name.trim().split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join()
        : '?';
    final relationship = companion['relationship'] ?? '';
    final lastSeen = companion['lastSeen'] as DateTime?;
    final isOnline = lastSeen != null &&
        DateTime.now().difference(lastSeen).inMinutes <= 5;
    final doseCount = companion['upcomingDoseCount'] ?? 0;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kBorderRadius),
        side: BorderSide(
          color: kSecondaryColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kBorderRadius),
        onTap: () => _navigateToDetail(companion),
        splashColor: kPrimaryColor.withOpacity(0.05),
        highlightColor: kPrimaryColor.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kPrimaryColor.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundColor: kPrimaryColor,
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
              ),
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
                            companion['email'] ?? '',
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
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "$doseCount جرعة قادمة",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade900,
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
              const Icon(
                Icons.chevron_left,
                color: kPrimaryColor,
              ),
            ],
          ),
        ),
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
        title: const Text("إضافة مرافق"),
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
                TextFormField(
                  controller: nameController,
                  textDirection: ui.TextDirection.rtl,
                  decoration: InputDecoration(
                    labelText: "الاسم",
                    prefixIcon: const Icon(Icons.person, color: kSecondaryColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kPrimaryColor),
                    ),
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
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kPrimaryColor),
                    ),
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
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kPrimaryColor),
                    ),
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
            ),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text("إضافة"),
          ),
        ],
      ),
    );
  }
}