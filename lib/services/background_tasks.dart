import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../core/config/env.dart';
import '../core/notifications/notification_actions.dart';
import '../core/notifications/reminder_service.dart';
import '../core/time/time_zone.dart';
import '../core/utils/log.dart';
import '../data/local/app_database.dart';
import '../data/remote/remote_store.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/companion_repository.dart';
import '../data/repositories/dose_log_repository.dart';
import '../data/repositories/medication_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/image_store.dart';
import '../data/sync/sync_service.dart';
import '../l10n/app_localizations.dart';
import 'companion_monitor.dart';
import 'reminder_coordinator.dart';

/// Periodic work while the app is closed (Android WorkManager / iOS
/// background app refresh):
///  * keep the 7-day reminder window topped up,
///  * sync with Supabase when signed in,
///  * alert caregivers about missed doses.
///
/// iOS decides when (and whether) background refresh runs, so on iPhone the
/// same checks also run whenever the app is opened.
abstract final class BackgroundTasks {
  /// Must match AppDelegate.swift and Info.plist on iOS.
  static const periodicTask = 'com.example.mudhkirApp.companionCheck';

  static Future<void> register() async {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      periodicTask,
      periodicTask,
      frequency: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}

@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await initTimeZones();
    final db = AppDatabase();
    try {
      await runPeriodicChecks(db);
      return true;
    } catch (e, s) {
      log('Background', 'Periodic check failed', e, s);
      return false;
    } finally {
      await db.close();
    }
  });
}

Future<void> runPeriodicChecks(AppDatabase db) async {
  final l10n = lookupAppLocalizations(await SettingsRepository.readLocale(db));
  final images = ImageStore();
  final medications = MedicationRepository(db, images);
  final logs = DoseLogRepository(db);
  final reminders = ReminderService();
  await reminders.initialize(
    l10n: l10n,
    onBackgroundResponse: onBackgroundNotificationResponse,
  );

  SupabaseClient? client;
  if (Env.isCloudConfigured) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseKey,
      );
      client = Supabase.instance.client;
    } catch (e) {
      log('Background', 'Supabase unavailable', e);
    }
  }
  final auth = AuthRepository(client);
  final remote = client == null ? null : SupabaseRemoteStore(client);

  if (auth.isSignedIn) {
    await SyncService(
      db: db,
      auth: auth,
      images: images,
      remote: remote,
    ).syncNow();
  }

  await rescheduleReminders(
    ownerId: auth.ownerId,
    medications: medications,
    logs: logs,
    reminders: reminders,
    l10n: l10n,
  );

  if (auth.isSignedIn) {
    await CompanionMonitor(
      companions: CompanionRepository(db, remote),
      medications: medications,
      logs: logs,
      reminders: reminders,
    ).check(caregiverId: auth.ownerId, l10n: l10n);
  }
}
