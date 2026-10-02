import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/notifications/notification_actions.dart';
import '../core/notifications/notification_payload.dart';
import '../core/utils/log.dart';
import '../data/repositories/settings_repository.dart';
import '../l10n/app_localizations.dart';
import '../services/background_tasks.dart';
import 'dependencies.dart';
import 'router.dart';
import 'theme.dart';

class MudhkirApp extends StatefulWidget {
  const MudhkirApp({required this.deps, super.key});

  final AppDependencies deps;

  @override
  State<MudhkirApp> createState() => _MudhkirAppState();
}

class _MudhkirAppState extends State<MudhkirApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(
    settings: widget.deps.settings,
    auth: widget.deps.auth,
  );

  AppDependencies get deps => widget.deps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startServices());
  }

  Future<void> _startServices() async {
    try {
      final l10n = lookupAppLocalizations(deps.settings.locale);
      await deps.reminders.initialize(
        l10n: l10n,
        onResponse: _onNotificationResponse,
        onBackgroundResponse: onBackgroundNotificationResponse,
      );
      deps.reminderCoordinator.start();
      await deps.sync.start();
      await BackgroundTasks.register();
      await deps.reminderCoordinator.refresh();

      final launch = await deps.reminders.launchResponse();
      if (launch != null) _onNotificationResponse(launch);
      await _checkCompanions();
    } catch (e, s) {
      log('Startup', 'Service start failed', e, s);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(() async {
      await deps.sync.syncNow();
      await deps.reminderCoordinator.refresh();
      await _checkCompanions();
    }());
  }

  Future<void> _checkCompanions() async {
    if (!deps.auth.isSignedIn) return;
    await deps.companionMonitor.check(
      caregiverId: deps.auth.ownerId,
      l10n: lookupAppLocalizations(deps.settings.locale),
    );
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = NotificationPayload.decode(response.payload);
    final action = response.actionId;
    switch (payload) {
      case DosePayload() when action != null && action.isNotEmpty:
        unawaited(
          handleDoseAction(
            action: action,
            payload: payload,
            db: deps.db,
            reminders: deps.reminders,
          ),
        );
      case DosePayload():
        _router.push(
          Routes.medication(payload.medicationId, doseAt: payload.scheduledAt),
        );
      case CompanionPayload():
        _router.push(Routes.companion(payload.patientId));
      case null:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    deps.reminderCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: deps.providers,
      child: Selector<SettingsRepository, Locale>(
        selector: (_, settings) => settings.locale,
        builder: (context, locale, _) => MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          locale: locale,
          supportedLocales: SettingsRepository.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router,
        ),
      ),
    );
  }
}
