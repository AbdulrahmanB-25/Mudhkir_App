import 'package:flutter/material.dart';

class dose_schedule extends StatelessWidget {
  const dose_schedule({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "جدول الأدوية",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade800,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade100, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: EdgeInsets.all(20),
          children: [
            // Example Dose Card
            Card(
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: ListTile(
                leading: Icon(Icons.medical_services,
                    color: Colors.blue.shade800, size: 40),
                title: Text(
                  "بانادول 500 ملجم",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800),
                ),
                subtitle: Text("8:00 مساءً"),
                trailing: Icon(Icons.alarm, color: Colors.blue.shade800),
              ),
            ),
            SizedBox(height: 15),

            Card(
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: ListTile(
                leading: Icon(Icons.medical_services,
                    color: Colors.blue.shade800, size: 40),
                title: Text(
                  "فيتامين سي",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800),
                ),
                subtitle: Text("10:00 صباحاً"),
                trailing: Icon(Icons.alarm, color: Colors.blue.shade800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
