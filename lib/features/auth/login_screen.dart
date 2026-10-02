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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _action = AuthAction();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthRepository>();
    final settings = context.read<SettingsRepository>();
    final ok = await _action.run(
      () => auth.signIn(email: _email.text, password: _password.text),
    );
    if (!ok || !mounted) return;
    await settings.completeOnboarding();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _action,
      builder: (context, _) => AuthScaffold(
        title: l10n.signInTitle,
        subtitle: l10n.signInSubtitle,
        children: [
          Form(
            key: _formKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AuthErrorText(_action.error),
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
                    validator: (v) => Validators.required(v, l10n),
                    onSubmitted: (_) => _submit(),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      onPressed: () => context.push(
                        '${Routes.forgotPassword}?email=${Uri.encodeQueryComponent(_email.text)}',
                      ),
                      child: Text(l10n.forgotPassword),
                    ),
                  ),
                  const SizedBox(height: 8),
                  BusyButton(
                    label: l10n.signIn,
                    busy: _action.busy,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.pushReplacement(Routes.signup),
                    child: Text(l10n.noAccountSignUp),
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
