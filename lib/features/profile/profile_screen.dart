import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/models/profile.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_action.dart';
import '../auth/auth_widgets.dart';
import '../shared/common_widgets.dart';

/// Name, email, password and account removal.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = context.watch<AuthRepository>();
    final profiles = context.read<ProfileRepository>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileTitle)),
      body: WatchBuilder<Profile?>(
        streamKey: auth.ownerId,
        create: () => profiles.watch(auth.ownerId),
        builder: (context, snapshot) {
          final name = snapshot.data?.name ?? auth.displayName ?? '';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(l10n.nameLabel),
                  subtitle: Text(name.isEmpty ? l10n.notSet : name),
                  trailing: const Icon(Icons.edit_rounded),
                  onTap: () => _editName(context, name),
                ),
              ),
              if (auth.isSignedIn) ...[
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.email_outlined),
                        title: Text(l10n.emailLabel),
                        subtitle: Text(
                          auth.pendingEmail == null
                              ? auth.email ?? ''
                              : l10n.emailChangePending(auth.pendingEmail!),
                        ),
                        trailing: const Icon(Icons.edit_rounded),
                        onTap: () => _changeEmail(context),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.password_rounded),
                        title: Text(l10n.changePassword),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _changePassword(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(l10n.signOut),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => _deleteAccount(context),
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: Text(l10n.deleteAccount),
                ),
              ] else if (auth.cloudAvailable) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.push(Routes.signup),
                  child: Text(l10n.createAccount),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _editName(BuildContext context, String current) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthRepository>();
    final profiles = context.read<ProfileRepository>();
    final name = await _prompt(
      context,
      title: l10n.nameLabel,
      initial: current,
    );
    if (name == null || name.trim().isEmpty) return;
    await profiles.saveName(auth.ownerId, name, email: auth.email);
  }

  Future<void> _changeEmail(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthRepository>();
    final email = await _prompt(
      context,
      title: l10n.changeEmail,
      initial: '',
      keyboardType: TextInputType.emailAddress,
      validator: (v) => Validators.email(v, l10n),
    );
    if (email == null || !context.mounted) return;
    final action = AuthAction();
    if (await action.run(() => auth.changeEmail(email))) {
      if (context.mounted) showMessage(context, l10n.emailChangeSent(email));
    } else if (context.mounted) {
      showMessage(context, action.error!.message(l10n), error: true);
    }
  }

  Future<void> _changePassword(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const _ChangePasswordDialog(),
  );

  Future<void> _signOut(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthRepository>();
    final sync = context.read<SyncService>();
    await sync.syncNow();
    final pending = await sync.pendingCount();
    if (!context.mounted) return;
    final ok = await confirm(
      context,
      title: l10n.signOut,
      message: pending > 0
          ? l10n.signOutPendingWarning(pending)
          : l10n.signOutConfirm,
      confirmLabel: l10n.signOut,
      destructive: pending > 0,
    );
    if (!ok || !context.mounted) return;
    final action = AuthAction();
    if (await action.run(auth.signOut)) {
      if (context.mounted) context.go(Routes.home);
    } else if (context.mounted) {
      showMessage(context, action.error!.message(l10n), error: true);
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthRepository>();
    final ok = await confirm(
      context,
      title: l10n.deleteAccount,
      message: l10n.deleteAccountConfirm,
      confirmLabel: l10n.actionDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final action = AuthAction();
    if (await action.run(auth.deleteAccount)) {
      if (context.mounted) {
        showMessage(context, l10n.accountDeleted);
        context.go(Routes.home);
      }
    } else if (context.mounted) {
      showMessage(context, action.error!.message(l10n), error: true);
    }
  }
}

Future<String?> _prompt(
  BuildContext context, {
  required String title,
  required String initial,
  TextInputType? keyboardType,
  FormFieldValidator<String>? validator,
}) {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
          validator: validator,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.of(context).pop(controller.text.trim());
            }
          },
          child: Text(l10n.actionSave),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _action = AuthAction();

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthRepository>();
    final ok = await _action.run(
      () => auth.changePassword(
        currentPassword: _current.text,
        newPassword: _next.text,
      ),
    );
    if (ok && mounted) {
      Navigator.of(context).pop();
      showMessage(context, l10n.passwordChanged);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _action,
      builder: (context, _) => AlertDialog(
        title: Text(l10n.changePassword),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AuthErrorText(_action.error),
              PasswordField(
                controller: _current,
                label: l10n.currentPasswordLabel,
                textInputAction: TextInputAction.next,
                validator: (v) => Validators.required(v, l10n),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _next,
                label: l10n.newPasswordLabel,
                validator: (v) => Validators.password(v, l10n),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionCancel),
          ),
          BusyButton(
            label: l10n.actionSave,
            busy: _action.busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
