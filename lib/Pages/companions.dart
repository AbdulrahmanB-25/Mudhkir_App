import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'CompanionDetailPage.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

const Color kPrimaryColor = Color(0xFF2E86C1);
const Color kSecondaryColor = Color(0xFF5DADE2);
const double kBorderRadius = 16.0;

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
      const SnackBar(content: Text("تم حذف المرافق"), backgroundColor: Colors.red),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("المرافقين"),
          backgroundColor: kPrimaryColor,
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : companionDataList.isEmpty
                ? Center(
                    child: Text(
                      "لا يوجد مرافقين حالياً",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryColor.withOpacity(0.7),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
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
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("تأكيد الحذف"),
                              content: const Text("هل تريد بالتأكيد حذف هذا المرافق؟"),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text("إلغاء"),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddCompanionDialog,
          backgroundColor: kPrimaryColor,
          child: const Icon(Icons.person_add),
          tooltip: "إضافة مرافق",
        ),
      ),
    );
  }

  Widget _buildCompanionCard(Map<String, dynamic> companion) {
    final name = companion['name'] ?? '';
    final initials = name.isNotEmpty
        ? name.trim().split(' ').map((e) => e[0]).take(2).join()
        : '?';
    final relationship = companion['relationship'] ?? '';
    final lastSeen = companion['lastSeen'] as DateTime?;
    final isOnline = lastSeen != null &&
        DateTime.now().difference(lastSeen).inMinutes <= 5;
    final doseCount = companion['upcomingDoseCount'] ?? 0;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kBorderRadius),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kBorderRadius),
        onTap: () => _navigateToDetail(companion),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    backgroundColor: kSecondaryColor,
                    radius: 26,
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
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
                    Text(
                      companion['email'] ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (relationship.isNotEmpty)
                      Text(
                        "صلة القرابة: $relationship",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    if (doseCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          "$doseCount جرعة قادمة",
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddCompanionDialog() {
    String name = '';
    String email = '';
    String relationship = '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("إضافة مرافق"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              textDirection: ui.TextDirection.rtl,
              decoration: const InputDecoration(labelText: "الاسم"),
              onChanged: (value) => name = value,
            ),
            TextField(
              textDirection: ui.TextDirection.rtl,
              decoration: const InputDecoration(labelText: "البريد الإلكتروني"),
              onChanged: (value) => email = value,
            ),
            TextField(
              textDirection: ui.TextDirection.rtl,
              decoration: const InputDecoration(labelText: "صلة القرابة"),
              onChanged: (value) => relationship = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text("إلغاء"),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            onPressed: () async {
              if (name.isNotEmpty && email.isNotEmpty) {
                await companionsRef.add({
                  'name': name,
                  'email': email,
                  'relationship': relationship,
                  'lastSeen': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
                _loadCompanions();
              }
            },
            child: const Text("إضافة"),
          ),
        ],
      ),
    );
  }
}
