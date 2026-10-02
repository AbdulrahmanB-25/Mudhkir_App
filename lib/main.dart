import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/dependencies.dart';
import 'core/time/time_zone.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initTimeZones();
  await initializeDateFormatting();
  final deps = await AppDependencies.create();
  runApp(MudhkirApp(deps: deps));
}
