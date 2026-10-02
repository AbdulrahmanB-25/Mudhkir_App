import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../utils/log.dart';

/// Loads the time-zone database and sets [tz.local] to the device's zone.
///
/// The old app hard-coded Asia/Riyadh; reminders now follow the phone.
Future<void> initTimeZones() async {
  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } catch (e) {
    log('TimeZone', 'Could not read device time zone, using UTC', e);
    tz.setLocalLocation(tz.UTC);
  }
}
