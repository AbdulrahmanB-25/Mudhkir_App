// lib/EditMedication_Utility/edit_medication_utils.dart
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
      final f = DateFormat('h:mm a', 'ar'); // changed locale here
      return TimeOfDay.fromDateTime(f.parseStrict(timeStr));
    } catch (_) {}
    return null;
  }

  static String formatTimeOfDay(TimeOfDay t) {
    final dt = DateTime(0, 0, 0, t.hour, t.minute);
    return DateFormat.jm('ar').format(dt);
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
  static Future<String> uploadToImgBB(File file, String apiKey) async {
    final b64 = base64Encode(await file.readAsBytes());
    final uri = Uri.parse('https://api.imgbb.com/1/upload?key=$apiKey');
    final resp = await http.post(uri, body: {'image': b64});
    if (resp.statusCode != 200) {
      throw Exception('ImgBB upload failed: ${resp.statusCode}');
    }
    final data = json.decode(resp.body)['data'];
    return data['url'] as String;
  }
}

