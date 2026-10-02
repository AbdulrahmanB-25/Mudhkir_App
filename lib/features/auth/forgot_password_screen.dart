import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/auth_repository.dart';
import '../../l10n/app_localizations.dart';
import '../shared/common_widgets.dart';
import 'auth_action.dart';
import 'auth_widgets.dart';

/// Two steps: send a 6-digit code by email, then enter it with a new
/// password. No web page or deep link needed.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({this.initialEmail, super.key});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _action = AuthAction();
  bool _codeSent = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthRepository>();
    if (!_codeSent) {
      final ok = await _action.run(() => auth.sendPasswordReset(_email.text));
      if (ok && mounted) {
        setState(() => _codeSent = true);
        showMessage(context, l10n.resetCodeSent);
      }
      return;
    }
    final ok = await _action.run(
      () => auth.confirmPasswordReset(
        email: _email.text,
        code: _code.text,
        newPassword: _password.text,
      ),
    );
    if (ok && mounted) {
      showMessage(context, l10n.passwordChanged);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _action,
      builder: (context, _) => AuthScaffold(
        title: l10n.forgotPasswordTitle,
        subtitle: _codeSent ? l10n.enterResetCode : l10n.forgotPasswordSubtitle,
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthErrorText(_action.error),
                TextFormField(
                  controller: _email,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => Validators.email(v, l10n),
                  decoration: InputDecoration(
                    labelText: l10n.emailLabel,
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 10,
                    validator: (v) => Validators.required(v, l10n),
                    decoration: InputDecoration(
                      labelText: l10n.resetCodeLabel,
                      prefixIcon: const Icon(Icons.pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 6),
                  PasswordField(
                    controller: _password,
                    label: l10n.newPasswordLabel,
                    validator: (v) => Validators.password(v, l10n),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                const SizedBox(height: 20),
                BusyButton(
                  label: _codeSent ? l10n.changePassword : l10n.sendResetCode,
                  busy: _action.busy,
                  onPressed: _submit,
                ),
                if (_codeSent)
                  TextButton(
                    onPressed: () => setState(() => _codeSent = false),
                    child: Text(l10n.resendCode),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
