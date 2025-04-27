import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

/// Houses all the low-level helpers:
///  • Time parsing/formatting
///  • Date calculations
///  • Permission checks
///  • ImgBB uploads
class EditMedicationUtils {
  // -- Time Parsing & Formatting --
  static TimeOfDay? parseTime(String timeStr) {
    try {
      // Normalize Arabic AM/PM to English for parsing
      String normalized = timeStr
          .replaceAll('صباحاً', 'AM')
          .replaceAll('مساءً', 'PM')
          .replaceAll('ص', 'AM')
          .replaceAll('م', 'PM')
          .trim();
      final f = DateFormat('h:mm a', 'en_US');
      return TimeOfDay.fromDateTime(f.parseStrict(normalized));
    } catch (_) {}
    return null;
  }

  static String formatTimeOfDay(TimeOfDay t) {
    final dt = DateTime(0, 0, 0, t.hour, t.minute);
    String formatted = DateFormat('h:mm a', 'ar').format(dt);
    formatted = formatted
        .replaceAll('AM', 'صباحاً')
        .replaceAll('PM', 'مساءً')
        .replaceAll('ص', 'صباحاً')
        .replaceAll('م', 'مساءً');
    return formatted;
  }

  // -- Date Range --
  static int calculateDays(DateTime start, DateTime end) =>
      end.difference(start).inDays + 1;

  // -- Permissions --
  static Future<void> ensureCameraPermission() async {
    final st = await Permission.camera.request();
    if (!st.isGranted) {
      if (st.isPermanentlyDenied) {
        openAppSettings();
      }
      throw Exception('Camera permission denied');
    }
  }

  // -- ImgBB Upload --
  static Future<Map<String, String>> uploadToImgBB(File file, String apiKey) async {
    final b64 = base64Encode(await file.readAsBytes());
    final uri = Uri.parse('https://api.imgbb.com/1/upload?key=$apiKey');
    final resp = await http.post(uri, body: {'image': b64});
    
    if (resp.statusCode != 200) {
      print("ImgBB Upload Failed - Status: ${resp.statusCode}, Body: ${resp.body}");
      throw Exception('ImgBB upload failed');
    }
    
    final jsonResponse = json.decode(resp.body);
    final data = jsonResponse['data'];
    final imageUrl = data['url'] as String;
    final deleteUrl = data['delete_url'] as String;
    final deleteHash = deleteUrl.substring(deleteUrl.lastIndexOf('/') + 1);
    
    return {'url': imageUrl, 'delete_hash': deleteHash};
  }
}

