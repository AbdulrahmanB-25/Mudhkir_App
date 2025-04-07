import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Companions extends StatefulWidget {
  const Companions({super.key});

  @override
  _CompanionsState createState() => _CompanionsState();
}

class _CompanionsState extends State<Companions> {
  final List<Map<String, String>> companions = [];

  @override
  void initState() {
    super.initState();
    _loadCompanionsFromFirestore();
  }

  Future<void> _loadCompanionsFromFirestore() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('companions')
          .get();

      setState(() {
        companions.clear();
        companions.addAll(snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'name': data['name'] ?? '',
            'relation': data['relation'] ?? '',
            'email': data['email'] ?? '',
          };
        }));
      });
    } catch (e) {
      print('🚫 Error loading companions: $e');
    }
  }

  void _showAddCompanionDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController relationController = TextEditingController();
    TextEditingController emailController = TextEditingController();
    String errorText = "";

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("إضافة مرافق جديد", textAlign: TextAlign.right),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(labelText: "اسم المرافق"),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: relationController,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(labelText: "العلاقة"),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      textAlign: TextAlign.right,
                      decoration: const InputDecoration(labelText: "البريد الإلكتروني للمرافق"),
                    ),
                    if (errorText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          errorText,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.right,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final relation = relationController.text.trim();
                    final email = emailController.text.trim().toLowerCase();

                    if (name.isEmpty || relation.isEmpty || email.isEmpty) {
                      setState(() {
                        errorText = "يرجى تعبئة جميع الحقول";
                      });
                      return;
                    }

                    try {
                      // Check if that email exists (optional validation)
                      final query = await FirebaseFirestore.instance
                          .collection('users')
                          .where('email', isEqualTo: email)
                          .limit(1)
                          .get();

                      if (query.docs.isEmpty) {
                        setState(() {
                          errorText = "❌ هذا البريد غير مسجل في التطبيق";
                        });
                        return;
                      }

                      // Get your UID (current user)
                      final currentUser = FirebaseAuth.instance.currentUser;
                      if (currentUser == null || currentUser.email == null) {
                        setState(() {
                          errorText = "لم يتم تسجيل الدخول";
                        });
                        return;
                      }

                      // ✅ Save companion under YOUR account
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(currentUser.uid)
                          .collection('companions')
                          .add({
                        'name': name,
                        'relation': relation,
                        'email': email,
                        'addedAt': FieldValue.serverTimestamp(),
                      });

                      print("✅ Companion saved under your account");

                      setState(() {
                        companions.add({
                          'name': name,
                          'relation': relation,
                          'email': email,
                        });
                        errorText = '';
                      });

                      Navigator.pop(context);
                    } catch (e) {
                      print("🔥 Error saving companion: $e");
                      setState(() {
                        errorText = "حدث خطأ أثناء الإضافة";
                      });
                    }
                  },
                  child: const Text("إضافة"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteCompanion(int index) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final emailToDelete = companions[index]['email'];

    final query = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('companions')
        .where('email', isEqualTo: emailToDelete)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      await query.docs.first.reference.delete();
      print("🗑️ Companion deleted");
    }

    setState(() {
      companions.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// 🌈 Background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          /// 📜 Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Column(
              children: [
                /// 🔙 Back
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(Icons.arrow_back, color: Colors.blue.shade800),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

                /// 📘 Title
                Align(
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "المرافقون",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      Text(
                        "المرافقين المرتبطين بحسابك",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                /// ➕ Add Button
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: _showAddCompanionDialog,
                    icon: const Icon(Icons.person_add),
                    label: const Text('إضافة مرافق جديد'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                /// 🧑 Companions List
                Expanded(
                  child: companions.isEmpty
                      ? Center(
                    child: Text(
                      "لا يوجد مرافقون مضافون بعد.",
                      style: TextStyle(color: Colors.blue.shade700),
                    ),
                  )
                      : ListView.builder(
                    itemCount: companions.length,
                    itemBuilder: (context, index) {
                      final companion = companions[index];
                      return Dismissible(
                        key: Key(companion['email'] ?? companion['name']!),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          padding: const EdgeInsets.only(right: 20),
                          alignment: Alignment.centerRight,
                          color: Colors.red.shade600,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _deleteCompanion(index),
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            leading: const Icon(Icons.person, color: Colors.blue),
                            title: Text(
                              companion['name']!,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            subtitle: Text(
                              "العلاقة: ${companion['relation']}\nالبريد: ${companion['email']}",
                              textAlign: TextAlign.right,
                              style: TextStyle(color: Colors.blue.shade600),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
