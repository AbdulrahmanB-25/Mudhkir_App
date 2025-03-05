import 'package:flutter/material.dart';

class Companions extends StatefulWidget {
  const Companions({super.key});


  //TODO: REMOVE HARDCODED MAKE DYNAMIC
  @override
  _CompanionsState createState() => _CompanionsState();
}

class _CompanionsState extends State<Companions> {
  final List<Map<String, String>> companions = [
    {'name': 'أحمد', 'relation': 'ابن'},
    {'name': 'فاطمة', 'relation': 'زوجة'},
    {'name': 'سعيد', 'relation': 'أخ'},
  ];

  void _showAddCompanionDialog() {
    TextEditingController nameController = TextEditingController();
    TextEditingController relationController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("إضافة مرافق جديد", textAlign: TextAlign.right),
          content: Column(
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
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty &&
                    relationController.text.isNotEmpty) {
                  setState(() {
                    companions.add({
                      'name': nameController.text,
                      'relation': relationController.text,
                    });
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text("إضافة"),
            ),
          ],
        );
      },
    );
  }

  void _deleteCompanion(int index) {
    setState(() {
      companions.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// 🌈 Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade100, Colors.white],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          /// 📜 Main Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Column(
              children: [
                /// 🔙 Back Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(Icons.arrow_back, color: Colors.blue.shade800),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ),

                /// 👋 Page Title
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
                        "إدارة المرافقين المسجلين",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                /// ➕ Add Companion Button
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

                /// 📋 Companions List with Swipe to Delete
                Expanded(
                  child: ListView.builder(
                    itemCount: companions.length,
                    itemBuilder: (context, index) {
                      return Dismissible(
                        key: Key(companions[index]['name']!),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          padding: const EdgeInsets.only(right: 20),
                          alignment: Alignment.centerRight,
                          color: Colors.red.shade600,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          _deleteCompanion(index);
                        },
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: ListTile(
                            leading:
                                Icon(Icons.person, color: Colors.blue.shade800),
                            title: Text(
                              companions[index]['name']!,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                              textAlign: TextAlign.right,
                            ),
                            subtitle: Text(
                              "العلاقة: ${companions[index]['relation']}",
                              style: TextStyle(color: Colors.blue.shade600),
                              textAlign: TextAlign.right,
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
