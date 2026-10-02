import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../core/notifications/reminder_service.dart';
import '../../l10n/app_localizations.dart';

/// Warns when reminders cannot ring (notifications off, or exact alarms not
/// allowed on Android) and offers a one-tap fix.
class ReminderPermissionBanner extends StatefulWidget {
  const ReminderPermissionBanner({super.key});

  @override
  State<ReminderPermissionBanner> createState() =>
      _ReminderPermissionBannerState();
}

class _ReminderPermissionBannerState extends State<ReminderPermissionBanner>
    with WidgetsBindingObserver {
  ReminderPermissions? _permissions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final permissions = await context.read<ReminderService>().permissions();
    if (mounted) setState(() => _permissions = permissions);
  }

  Future<void> _fix() async {
    final reminders = context.read<ReminderService>();
    final permissions = _permissions;
    if (permissions == null) return;
    if (!permissions.notifications) {
      await reminders.requestPermissions();
    } else if (!permissions.exactAlarms) {
      await reminders.requestExactAlarms();
    }
    await _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissions = _permissions;
    if (permissions == null || permissions.allGranted) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: AppColors.warning.withValues(alpha: 0.15),
        child: ListTile(
          leading: const Icon(
            Icons.notifications_off_rounded,
            color: AppColors.warning,
          ),
          title: Text(
            permissions.notifications
                ? l10n.exactAlarmsOffTitle
                : l10n.notificationsOffTitle,
          ),
          subtitle: Text(l10n.permissionBannerMessage),
          trailing: TextButton(onPressed: _fix, child: Text(l10n.actionAllow)),
        ),
      ),
    );
  }
}
