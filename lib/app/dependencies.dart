import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/notifications/reminder_service.dart';
import '../core/utils/log.dart';
import '../data/local/app_database.dart';
import '../data/remote/remote_store.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/companion_repository.dart';
import '../data/repositories/dose_log_repository.dart';
import '../data/repositories/medication_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/services/image_store.dart';
import '../data/services/medicine_catalog.dart';
import '../data/sync/sync_service.dart';
import '../domain/services/dose_calculator.dart';
import '../services/companion_monitor.dart';
import '../services/reminder_coordinator.dart';

/// Builds every long-lived object once and hands them to the widget tree.
class AppDependencies {
  AppDependencies._({
    required this.db,
    required this.settings,
    required this.auth,
    required this.images,
    required this.medications,
    required this.logs,
    required this.profiles,
    required this.companions,
    required this.sync,
    required this.reminders,
    required this.reminderCoordinator,
    required this.companionMonitor,
    required this.catalog,
  });

  final AppDatabase db;
  final SettingsRepository settings;
  final AuthRepository auth;
  final ImageStore images;
  final MedicationRepository medications;
  final DoseLogRepository logs;
  final ProfileRepository profiles;
  final CompanionRepository companions;
  final SyncService sync;
  final ReminderService reminders;
  final ReminderCoordinator reminderCoordinator;
  final CompanionMonitor companionMonitor;
  final MedicineCatalog catalog;

  static Future<AppDependencies> create() async {
    final db = AppDatabase();
    final settings = SettingsRepository(db);
    await settings.load();

    SupabaseClient? client;
    if (Env.isCloudConfigured) {
      try {
        await Supabase.initialize(
          url: Env.supabaseUrl,
          publishableKey: Env.supabaseKey,
        );
        client = Supabase.instance.client;
      } catch (e) {
        // Still usable offline as a guest.
        log('Startup', 'Supabase could not be initialised', e);
      }
    }
    final remote = client == null ? null : SupabaseRemoteStore(client);
    final auth = AuthRepository(client);
    final images = ImageStore();
    final medications = MedicationRepository(db, images);
    final logs = DoseLogRepository(db);
    final reminders = ReminderService();
    final companions = CompanionRepository(db, remote);

    return AppDependencies._(
      db: db,
      settings: settings,
      auth: auth,
      images: images,
      medications: medications,
      logs: logs,
      profiles: ProfileRepository(db),
      companions: companions,
      sync: SyncService(
        db: db,
        auth: auth,
        images: images,
        remote: remote,
        connectivity: Connectivity().onConnectivityChanged,
      ),
      reminders: reminders,
      reminderCoordinator: ReminderCoordinator(
        auth: auth,
        settings: settings,
        medications: medications,
        logs: logs,
        reminders: reminders,
      ),
      companionMonitor: CompanionMonitor(
        companions: companions,
        medications: medications,
        logs: logs,
        reminders: reminders,
      ),
      catalog: MedicineCatalog(),
    );
  }

  List<SingleChildWidget> get providers => [
    ChangeNotifierProvider.value(value: settings),
    ChangeNotifierProvider.value(value: auth),
    ChangeNotifierProvider.value(value: sync),
    Provider.value(value: db),
    Provider.value(value: images),
    Provider.value(value: medications),
    Provider.value(value: logs),
    Provider.value(value: profiles),
    Provider.value(value: companions),
    Provider.value(value: reminders),
    Provider.value(value: reminderCoordinator),
    Provider.value(value: companionMonitor),
    Provider.value(value: catalog),
    Provider.value(value: const DoseCalculator()),
  ];
}

extension DependenciesContext on BuildContext {
  T dep<T>() => read<T>();
}
