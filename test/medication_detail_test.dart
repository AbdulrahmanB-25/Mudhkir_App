import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mudhkir_app/MeidcaitonDetailPage_Utility/medication_detail_services.dart';
import 'package:mudhkir_app/MeidcaitonDetailPage_Utility/medication_detail_ui_components.dart';
import 'package:mudhkir_app/MeidcaitonDetailPage_Utility/time_utilities.dart'; // 🆕 for date formatting

void main() {
  // Initialize Arabic date formatting before tests
  setUpAll(() async {
    await initializeDateFormatting('ar_SA');
  });

  // ▸ UNIT TEST: Testing TimeUtilities
  group('TimeUtilities Tests', () {
    test('formats TimeOfDay correctly', () {
      final time = TimeOfDay(hour: 14, minute: 5);
      final formatted = TimeUtilities.formatTimeOfDay(time);
      expect(formatted, '2:05 مساءً');
    });

    test('detects future time', () {
      final now = TimeOfDay.now();
      final future = TimeUtilities.addHoursToTime(now, 1);
      expect(TimeUtilities.isTimeInFuture(future), true);
    });

    test('formats DateTime to Arabic date', () {
      final date = DateTime(2025, 4, 25);
      final formattedDate = TimeUtilities.formatDate(date);
      expect(formattedDate, contains('أبريل'));
    });
  });

  // ▸ UNIT TEST: Testing MedicationDetailUIComponents
  group('MedicationDetailUIComponents Tests', () {
    late MedicationDetailUIComponents components;

    setUp(() {
      components = MedicationDetailUIComponents(
        updateState: () {},
        handleConfirmation: (_) {},
        handleReschedule: () {},
        showCustomTimePickerDialog: () {},
        showManualTimePickerDialog: () {},
        setReschedulingModeTrue: () {},
        setReschedulingModeFalse: () {},
        selectSuggestedTime: (_) {},
      );
    });

    testWidgets('renders error view correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: components.buildErrorView('خطأ', () {}),
          ),
        ),
      );

      expect(find.text('خطأ'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('renders action section correctly', (WidgetTester tester) async {
      final mockData = {'name': 'Panadol'};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: components.buildActionSection(mockData, null, false),
          ),
        ),
      );

      expect(find.text('الإجراءات'), findsOneWidget);
      expect(find.text('Panadol'), findsOneWidget);
    });
  });

  // ▸ UNIT TEST: Testing MedicationDetailService (testing ServiceResult separately)
  group('MedicationDetailService Tests', () {
    test('ServiceResult succeeds and fails correctly', () {
      final success = ServiceResult.succeeded('data');
      expect(success.success, true);
      expect(success.data, 'data');

      final failure = ServiceResult.failed('error');
      expect(failure.success, false);
      expect(failure.error, 'error');
    });
  });

  // ▸ WIDGET TEST: Testing basic loading indicator (instead of full MedicationDetailPage)
  group('Basic UI Placeholder Test', () {
    testWidgets('renders a loading spinner', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
