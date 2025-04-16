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
  bool isProcessingAction = false; // Track when action button operations are in progress
  String errorMessage = '';
  TimeOfDay? selectedDoseTime; // Store the currently selected dose time

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
            
            // Try to determine current dose time
            final data = doc.data() as Map<String, dynamic>;
            final List<dynamic> times = data['times'] ?? [];
            
            if (times.isNotEmpty) {
              // Get the current time for comparison
              final now = TimeOfDay.now();
              final nowMinutes = now.hour * 60 + now.minute;
              
              // Find the closest time (past or future)
              TimeOfDay? closestTime;
              int? minDifference;
              
              for (var timeEntry in times) {
                String timeStr;
                if (timeEntry is Map) {
                  timeStr = timeEntry['time']?.toString() ?? '';
                } else {
                  timeStr = timeEntry.toString();
                }
                
                final time = _parseTime(timeStr);
                if (time != null) {
                  final timeMinutes = time.hour * 60 + time.minute;
                  final diff = (timeMinutes - nowMinutes).abs();
                  
                  if (minDifference == null || diff < minDifference) {
                    minDifference = diff;
                    closestTime = time;
                  }
                }
              }
              
              selectedDoseTime = closestTime;
            }
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

  // Parse time string to TimeOfDay object
  TimeOfDay? _parseTime(String timeStr) {
    try {
      final DateFormat ampmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = ampmFormat.parseStrict(timeStr);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      String normalizedTime = timeStr
          .replaceAll('صباحاً', 'AM').replaceAll('مساءً', 'PM').trim();
      final DateFormat arabicAmpmFormat = DateFormat('h:mm a', 'en_US');
      DateTime parsedDt = arabicAmpmFormat.parseStrict(normalizedTime);
      return TimeOfDay.fromDateTime(parsedDt);
    } catch (_) {}
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
        if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
          return TimeOfDay(hour: hour, minute: minute);
        }
      }
    } catch (_) {}
    return null;
  }

  // Format TimeOfDay to string in Arabic format
  String _formatTimeOfDay(TimeOfDay time) {
    final int hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final String minute = time.minute.toString().padLeft(2, '0');
    final String period = time.period == DayPeriod.am ? 'صباحاً' : 'مساءً';
    return '$hour:$minute $period';
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "غير محدد";
    final date = timestamp.toDate();
    return DateFormat('yyyy/MM/dd', 'ar_SA').format(date);
  }

  // Method to mark the dose as taken
  Future<void> _confirmDoseTaken() async {
    if (isProcessingAction) return; // Prevent multiple submissions
    
    setState(() {
      isProcessingAction = true;
    });
    
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("المستخدم غير مسجل الدخول"),
          backgroundColor: Colors.red.shade700,
        ),
      );
      setState(() {
        isProcessingAction = false;
      });
      return;
    }
    
    try {
      final now = DateTime.now();
      final Timestamp takenTimestamp = Timestamp.fromDate(now);
      
      // Get the current date in normalized form
      final today = DateTime(now.year, now.month, now.day);
      
      // Reference to the document
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('medicines')
          .doc(widget.docId);
      
      // Get the existing document to update
      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        throw Exception("Document not found");
      }
      
      final data = docSnapshot.data()!;
      List<Map<String, dynamic>> missedDoses = [];
      
      // Convert existing missedDoses to proper List<Map>
      if (data.containsKey('missedDoses')) {
        final existingDoses = data['missedDoses'];
        if (existingDoses is List) {
          for (var dose in existingDoses) {
            if (dose is Map) {
              missedDoses.add(Map<String, dynamic>.from(dose));
            }
          }
        }
      }
      
      // Create a new dose entry
      final doseEntry = {
        'scheduled': takenTimestamp,  // Using current time as scheduled time
        'status': 'taken',
        'takenAt': takenTimestamp,
        'originalSchedule': selectedDoseTime != null ? _formatTimeOfDay(selectedDoseTime!) : null,
      };
      
      // Add the new entry
      missedDoses.add(doseEntry);
      
      // Update the document
      await docRef.update({
        'missedDoses': missedDoses,
        'lastTaken': takenTimestamp,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("تم تأكيد أخذ الجرعة بنجاح"),
            backgroundColor: Colors.green.shade700,
          ),
        );
        
        // Optional: Navigate back or reload
        // Navigator.pop(context, true); // Uncomment to go back
        _loadMedication(); // Reload the current page
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("حدث خطأ: $e"),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isProcessingAction = false;
        });
      }
    }
  }

  // Method to open time picker and reschedule dose
  Future<void> _reschedule() async {
    if (isProcessingAction) return; // Prevent multiple submissions
    
    // Show time picker
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: selectedDoseTime ?? TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.orange.shade700,
            ),
            buttonTheme: const ButtonThemeData(
              textTheme: ButtonTextTheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        isProcessingAction = true;
        selectedDoseTime = picked;
      });
      
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("المستخدم غير مسجل الدخول"),
            backgroundColor: Colors.red.shade700,
          ),
        );
        setState(() {
          isProcessingAction = false;
        });
        return;
      }
      
      try {
        final now = DateTime.now();
        final DateTime scheduledDateTime = DateTime(
          now.year,
          now.month,
          now.day,
          picked.hour,
          picked.minute,
        );
        
        if (scheduledDateTime.isBefore(now)) {
          // If time is in past, schedule for tomorrow
          scheduledDateTime.add(const Duration(days: 1));
        }
        
        // Reference to the document
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('medicines')
            .doc(widget.docId);
        
        // Get the document to update
        final docSnapshot = await docRef.get();
        if (!docSnapshot.exists) {
          throw Exception("Document not found");
        }
        
        final data = docSnapshot.data()!;
        List<dynamic> times = List.from(data['times'] ?? []);
        final String frequencyType = data['frequencyType'] ?? 'يومي';
        final formattedTime = _formatTimeOfDay(picked);
        
        // Update times based on frequency type
        if (frequencyType == 'يومي') {
          // For daily medications with simple time list
          if (times.isNotEmpty && times[0] is String) {
            // Find closest match to our current time and replace it
            int matchIndex = -1;
            TimeOfDay? previousSelectedTime = selectedDoseTime;
            
            if (previousSelectedTime != null) {
              for (int i = 0; i < times.length; i++) {
                final timeStr = times[i].toString();
                final time = _parseTime(timeStr);
                if (time != null && 
                    time.hour == previousSelectedTime.hour && 
                    time.minute == previousSelectedTime.minute) {
                  matchIndex = i;
                  break;
                }
              }
            }
            
            if (matchIndex >= 0) {
              times[matchIndex] = formattedTime;
            } else if (times.isNotEmpty) {
              // If no match found, update the first time
              times[0] = formattedTime;
            }
          }
        } else if (frequencyType == 'اسبوعي') {
          // For weekly medications with day-specific times
          int today = now.weekday;
          bool updated = false;
          
          for (int i = 0; i < times.length; i++) {
            if (times[i] is Map && times[i]['day'] == today) {
              times[i]['time'] = formattedTime;
              updated = true;
              break;
            }
          }
          
          if (!updated && times.isNotEmpty) {
            // If no match for today, update the first entry
            if (times[0] is Map) {
              times[0]['time'] = formattedTime;
            }
          }
        }
        
        // Update rescheduling record
        List<Map<String, dynamic>> reschedulingHistory = [];
        if (data.containsKey('reschedulingHistory') && data['reschedulingHistory'] is List) {
          for (var entry in data['reschedulingHistory']) {
            if (entry is Map) {
              reschedulingHistory.add(Map<String, dynamic>.from(entry));
            }
          }
        }
        
        reschedulingHistory.add({
          'previousTime': selectedDoseTime != null ? _formatTimeOfDay(selectedDoseTime!) : null,
          'newTime': formattedTime,
          'rescheduledAt': Timestamp.now(),
        });
        
        // Update the document
        await docRef.update({
          'times': times,
          'reschedulingHistory': reschedulingHistory,
          'lastRescheduled': Timestamp.now(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("تم إعادة جدولة الجرعة إلى $formattedTime بنجاح"),
              backgroundColor: Colors.blue.shade700,
            ),
          );
          
          // Reload the page to show updated information
          _loadMedication();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("حدث خطأ أثناء إعادة الجدولة: $e"),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            isProcessingAction = false;
          });
        }
      }
    }
  }

  // Check if the dose is significantly late (more than 3 hours)
  bool _isDoseSignificantlyLate() {
    if (selectedDoseTime == null) return false;
    
    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final doseMinutes = selectedDoseTime!.hour * 60 + selectedDoseTime!.minute;
    
    // If dose time is earlier today and more than 3 hours ago
    return doseMinutes < nowMinutes && (nowMinutes - doseMinutes) > 180;
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
    // Check if the dose is significantly late (more than 3 hours)
    final isDoseLate = _isDoseSignificantlyLate();
    
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (selectedDoseTime != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  "الجرعة الحالية: ${_formatTimeOfDay(selectedDoseTime!)}",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
            // Confirm Taken Button
            SizedBox(
              height: 60, // Make button larger for easier tapping
              child: ElevatedButton.icon(
                onPressed: isProcessingAction || (isDoseLate && false) ? null : _confirmDoseTaken,
                icon: isProcessingAction 
                    ? SizedBox(
                        width: 20, 
                        height: 20, 
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      ) 
                    : const Icon(Icons.check_circle_outline, size: 24),
                label: Text(
                  "تأكيد أخذ الجرعة", 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  disabledBackgroundColor: Colors.green.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Reschedule Button
            SizedBox(
              height: 60, // Make button larger for easier tapping
              child: ElevatedButton.icon(
                onPressed: isProcessingAction ? null : _reschedule,
                icon: isProcessingAction 
                    ? SizedBox(
                        width: 20, 
                        height: 20, 
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        )
                      ) 
                    : const Icon(Icons.update, size: 24),
                label: Text(
                  "إعادة جدولة الجرعة", 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  disabledBackgroundColor: Colors.orange.shade200,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
            
            if (isDoseLate)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  "ملاحظة: مر أكثر من 3 ساعات على موعد الجرعة",
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
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
