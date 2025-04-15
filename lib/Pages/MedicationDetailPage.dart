import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class MedicationDetailPage extends StatefulWidget {
  final String docId;
  const MedicationDetailPage({Key? key, required this.docId}) : super(key: key);

  @override
  _MedicationDetailPageState createState() => _MedicationDetailPageState();
}

class _MedicationDetailPageState extends State<MedicationDetailPage> {
  DocumentSnapshot? medicationDoc;
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadMedication();
  }

  Future<void> _loadMedication() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        var doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('medicines')
            .doc(widget.docId)
            .get();
            
        if (!mounted) return;
        
        if (doc.exists) {
          setState(() {
            medicationDoc = doc;
            isLoading = false;
          });
        } else {
          setState(() {
            isLoading = false;
            errorMessage = "لم يتم العثور على بيانات هذا الدواء";
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          isLoading = false;
          errorMessage = "حدث خطأ أثناء تحميل البيانات: $e";
        });
      }
    } else {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = "المستخدم غير مسجل الدخول";
      });
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "غير محدد";
    final date = timestamp.toDate();
    return DateFormat('yyyy/MM/dd', 'ar_SA').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "تفاصيل الدواء",
          style: TextStyle(
            color: Colors.blue.shade800,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.white.withOpacity(0.7),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.blue.shade800),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade50,
              Colors.white.withOpacity(0.8),
              Colors.blue.shade100,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: isLoading
              ? Center(child: CircularProgressIndicator(color: Colors.blue.shade700))
              : errorMessage.isNotEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 70, color: Colors.red.shade400),
                          const SizedBox(height: 16),
                          Text(
                            errorMessage,
                            style: TextStyle(fontSize: 18, color: Colors.red.shade700),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            child: const Text("العودة", style: TextStyle(fontSize: 16)),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildMedicationCard(),
                          const SizedBox(height: 20),
                          _buildScheduleCard(),
                          const SizedBox(height: 20),
                          _buildActionButtons(),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _buildMedicationCard() {
    final data = medicationDoc!.data() as Map<String, dynamic>;
    final imageUrl = data['imageUrl'] as String?;
    
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 160,
                      width: double.infinity,
                      color: Colors.grey.shade200,
                      child: Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 50),
                    ),
                  ),
                ),
              ),
            Text(
              data['name'] ?? "دواء غير مسمى",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            InfoRow(
              icon: Icons.medical_information,
              label: "الجرعة:",
              value: data['dosage'] ?? "غير محددة",
            ),
            const Divider(height: 24),
            InfoRow(
              icon: Icons.date_range,
              label: "تاريخ البدء:",
              value: _formatDate(data['startDate']),
            ),
            const SizedBox(height: 12),
            InfoRow(
              icon: Icons.event_busy,
              label: "تاريخ الانتهاء:",
              value: data['endDate'] != null ? _formatDate(data['endDate']) : "غير محدد",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard() {
    final data = medicationDoc!.data() as Map<String, dynamic>;
    final frequency = data['frequency'] ?? "غير محدد";
    final List<dynamic> times = data['times'] ?? [];
    
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "جدول الجرعات",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
            const SizedBox(height: 12),
            InfoRow(
              icon: Icons.repeat,
              label: "التكرار:",
              value: frequency,
            ),
            const Divider(height: 24),
            const Text(
              "أوقات الجرعات:",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (times.isEmpty)
              Text(
                "لا توجد أوقات محددة",
                style: TextStyle(color: Colors.grey.shade600),
              ),
            if (times.isNotEmpty)
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: times.length,
                itemBuilder: (context, index) {
                  String timeDisplay;
                  if (times[index] is Map) {
                    final day = times[index]['day'];
                    final time = times[index]['time'];
                    timeDisplay = "$day: $time";
                  } else {
                    timeDisplay = times[index].toString();
                  }
                  return ListTile(
                    leading: Icon(Icons.access_time, color: Colors.blue.shade600),
                    title: Text(timeDisplay),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/dose_schedule', 
                ).then((_) => _loadMedication());
              },
              icon: const Icon(Icons.calendar_month),
              label: const Text("عرض الجدول الكامل"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/medication_detail',
                  arguments: {'docId': widget.docId},
                ).then((_) => _loadMedication());
              },
              icon: const Icon(Icons.mark_chat_read),
              label: const Text("تأكيد أخذ الجرعة"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow({
    Key? key,
    required this.icon,
    required this.label,
    required this.value,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue.shade600, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }
}
