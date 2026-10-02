import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../core/config/env.dart';
import '../../core/notifications/reminder_service.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';
import '../shared/formatters.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabSettings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SectionTitle(l10n.accountSection),
          const _AccountCard(),
          SectionTitle(l10n.remindersSection),
          const _RemindersCard(),
          SectionTitle(l10n.languageSection),
          const _LanguageCard(),
          SectionTitle(l10n.aboutSection),
          const _AboutCard(),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = context.watch<AuthRepository>();

    if (!auth.isSignedIn) {
      return Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(l10n.guestMode),
              subtitle: Text(
                auth.cloudAvailable ? l10n.guestModeHint : l10n.offlineOnlyHint,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(Routes.profile),
            ),
            if (auth.cloudAvailable) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.login_rounded),
                title: Text(l10n.signIn),
                onTap: () => context.push(Routes.login),
              ),
              ListTile(
                leading: const Icon(Icons.person_add_alt_rounded),
                title: Text(l10n.createAccount),
                onTap: () => context.push(Routes.signup),
              ),
            ],
          ],
        ),
      );
    }

    final sync = context.watch<SyncService>();
    final last = sync.lastSyncedAt;
    final (icon, status) = switch (sync.state) {
      SyncState.syncing => (Icons.sync_rounded, l10n.syncInProgress),
      SyncState.offline => (Icons.cloud_off_rounded, l10n.syncOffline),
      SyncState.error => (Icons.sync_problem_rounded, l10n.syncError),
      _ => (
        Icons.cloud_done_rounded,
        last == null
            ? l10n.syncNever
            : l10n.syncLast(context.formatDateTime(last)),
      ),
    };

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
            title: Text(auth.displayName ?? l10n.myAccount),
            subtitle: Text(auth.email ?? ''),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push(Routes.profile),
          ),
          const Divider(height: 1),
          WatchBuilder<int>(
            streamKey: auth.ownerId,
            create: sync.watchPendingCount,
            builder: (context, snapshot) {
              final pending = snapshot.data ?? 0;
              return ListTile(
                leading: Icon(icon),
                title: Text(status),
                subtitle: pending > 0 ? Text(l10n.syncPending(pending)) : null,
                trailing: sync.state == SyncState.syncing
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : TextButton(
                        onPressed: sync.syncNow,
                        child: Text(l10n.syncNow),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RemindersCard extends StatefulWidget {
  const _RemindersCard();

  @override
  State<_RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends State<_RemindersCard> {
  ReminderPermissions? _permissions;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final value = await context.read<ReminderService>().permissions();
    if (mounted) setState(() => _permissions = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reminders = context.read<ReminderService>();
    final permissions = _permissions;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(l10n.notificationsPermission),
            subtitle: Text(l10n.notificationsPermissionHint),
            value: permissions?.notifications ?? false,
            onChanged: (_) async {
              await reminders.requestPermissions();
              await _refresh();
            },
          ),
          if (permissions != null && !permissions.exactAlarms)
            ListTile(
              leading: const Icon(Icons.alarm_off_rounded),
              title: Text(l10n.exactAlarmsOffTitle),
              subtitle: Text(l10n.exactAlarmsHint),
              trailing: TextButton(
                onPressed: () async {
                  await reminders.requestExactAlarms();
                  await _refresh();
                },
                child: Text(l10n.actionAllow),
              ),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.notification_add_outlined),
            title: Text(l10n.testReminder),
            subtitle: Text(l10n.testReminderHint),
            onTap: () async {
              await reminders.scheduleTest(l10n);
              if (context.mounted) {
                showMessage(context, l10n.testReminderScheduled);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ar', label: Text('العربية')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: {settings.locale.languageCode},
          onSelectionChanged: (value) =>
              settings.setLocale(Locale(value.first)),
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(l10n.privacyTitle),
            subtitle: Text(l10n.privacyText),
          ),
          if (Env.supportEmail.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.support_agent_rounded),
              title: Text(l10n.contactUs),
              subtitle: const Text(Env.supportEmail),
              onTap: () =>
                  launchUrl(Uri(scheme: 'mailto', path: Env.supportEmail)),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(l10n.appTitle),
            subtitle: Text(l10n.appVersion('2.0.0')),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
              applicationVersion: '2.0.0',
            ),
          ),
        ],
      ),
    );
  }
}
