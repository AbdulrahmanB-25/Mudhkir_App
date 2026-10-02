import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';
import 'auth_action.dart';
import 'auth_widgets.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _action = AuthAction();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthRepository>();
    final settings = context.read<SettingsRepository>();
    var needsConfirmation = false;
    final ok = await _action.run(() async {
      needsConfirmation = await auth.signUp(
        name: _name.text,
        email: _email.text,
        password: _password.text,
      );
    });
    if (!ok || !mounted) return;
    if (needsConfirmation) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_outlined, size: 40),
          title: Text(l10n.confirmEmailTitle),
          content: Text(l10n.confirmEmailMessage(_email.text.trim())),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.actionOk),
            ),
          ],
        ),
      );
      if (mounted) context.pushReplacement(Routes.login);
      return;
    }
    await settings.completeOnboarding();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _action,
      builder: (context, _) => AuthScaffold(
        title: l10n.signUpTitle,
        subtitle: l10n.signUpSubtitle,
        children: [
          Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthErrorText(_action.error),
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    validator: (v) => Validators.required(v, l10n),
                    decoration: InputDecoration(
                      labelText: l10n.nameLabel,
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => Validators.email(v, l10n),
                    decoration: InputDecoration(
                      labelText: l10n.emailLabel,
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  PasswordField(
                    controller: _password,
                    label: l10n.passwordLabel,
                    textInputAction: TextInputAction.next,
                    validator: (v) => Validators.password(v, l10n),
                  ),
                  const SizedBox(height: 14),
                  PasswordField(
                    controller: _confirm,
                    label: l10n.confirmPasswordLabel,
                    validator: (v) => v != _password.text
                        ? l10n.validationPasswordsDiffer
                        : null,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  BusyButton(
                    label: l10n.createAccount,
                    busy: _action.busy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.signUpGuestDataNote,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.pushReplacement(Routes.login),
                    child: Text(l10n.haveAccountSignIn),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
