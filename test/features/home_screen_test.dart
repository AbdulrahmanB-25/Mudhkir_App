import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mudhkir_app/core/notifications/reminder_service.dart';
import 'package:mudhkir_app/data/local/app_database.dart';
import 'package:mudhkir_app/data/repositories/auth_repository.dart';
import 'package:mudhkir_app/data/repositories/dose_log_repository.dart';
import 'package:mudhkir_app/data/repositories/medication_repository.dart';
import 'package:mudhkir_app/data/repositories/profile_repository.dart';
import 'package:mudhkir_app/data/services/image_store.dart';
import 'package:mudhkir_app/domain/models/local_date.dart';
import 'package:mudhkir_app/domain/models/medication.dart';
import 'package:mudhkir_app/features/home/home_screen.dart';
import 'package:mudhkir_app/l10n/app_localizations.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  testWidgets('home shows the empty state, then a medication added offline', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    // Closing drift inside the fake-async test zone never completes, so the
    // in-memory database is closed after the test instead.
    addTearDown(db.close);
    final meds = MedicationRepository(
      db,
      ImageStore(baseDirectory: () async => Directory.systemTemp),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthRepository>(
            create: (_) => AuthRepository(null),
          ),
          Provider.value(value: meds),
          Provider.value(value: DoseLogRepository(db)),
          Provider.value(value: ProfileRepository(db)),
          Provider.value(value: ReminderService()),
        ],
        child: const MaterialApp(
          locale: Locale('ar'),
          supportedLocales: [Locale('ar'), Locale('en')],
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeScreen(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('لا توجد أدوية بعد'), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).first)
          .textDirection,
      TextDirection.rtl,
    );

    final now = DateTime.now().toUtc();
    await meds.save(
      Medication(
        id: 'm1',
        ownerId: AuthRepository.guestId,
        name: 'Panadol',
        dosageAmount: '500',
        dosageUnit: DosageUnit.mg,
        frequency: Frequency.daily,
        times: const [DoseTime(minutes: 23 * 60 + 59)],
        startDate: LocalDate.fromDateTime(now),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _settle(tester);

    expect(find.text('Panadol'), findsWidgets);
    expect(find.text('الجرعة القادمة'), findsOneWidget);

    // Unmount so the view model cancels its ticker and drift streams.
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });
}

/// Lets drift's stream queries deliver (they complete via microtasks and
/// zero-length timers) without waiting for the 1-minute ticker.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
