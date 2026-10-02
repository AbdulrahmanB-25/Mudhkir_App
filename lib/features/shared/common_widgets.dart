import 'package:flutter/material.dart';

import '../../data/repositories/auth_repository.dart';
import '../../l10n/app_localizations.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ),
  );
}

extension AuthFailureMessage on AuthFailureReason {
  String message(AppLocalizations l10n) => switch (this) {
    AuthFailureReason.invalidCredentials => l10n.errorInvalidCredentials,
    AuthFailureReason.emailNotConfirmed => l10n.errorEmailNotConfirmed,
    AuthFailureReason.emailInUse => l10n.errorEmailInUse,
    AuthFailureReason.weakPassword => l10n.errorWeakPassword,
    AuthFailureReason.invalidCode => l10n.errorInvalidCode,
    AuthFailureReason.rateLimited => l10n.errorRateLimited,
    AuthFailureReason.network => l10n.errorNetwork,
    AuthFailureReason.cloudUnavailable => l10n.errorCloudUnavailable,
    AuthFailureReason.unknown => l10n.errorUnknown,
  };
}

/// Shared form validators.
abstract final class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) return l10n.validationRequired;
    if (!_email.hasMatch(value.trim())) return l10n.validationEmail;
    return null;
  }

  static String? password(String? value, AppLocalizations l10n) {
    if (value == null || value.isEmpty) return l10n.validationRequired;
    if (value.length < 8) return l10n.validationPasswordLength;
    return null;
  }

  static String? required(String? value, AppLocalizations l10n) =>
      (value == null || value.trim().isEmpty) ? l10n.validationRequired : null;
}

/// A [StreamBuilder] that creates its stream once (and again only when
/// [streamKey] changes). Creating a database stream inside `build` would
/// re-run the query on every rebuild.
class WatchBuilder<T> extends StatefulWidget {
  const WatchBuilder({
    required this.create,
    required this.builder,
    this.streamKey,
    super.key,
  });

  final Stream<T> Function() create;
  final AsyncWidgetBuilder<T> builder;
  final Object? streamKey;

  @override
  State<WatchBuilder<T>> createState() => _WatchBuilderState<T>();
}

class _WatchBuilderState<T> extends State<WatchBuilder<T>> {
  late Stream<T> _stream = widget.create();

  @override
  void didUpdateWidget(WatchBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamKey != widget.streamKey) _stream = widget.create();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<T>(stream: _stream, builder: widget.builder);
}
