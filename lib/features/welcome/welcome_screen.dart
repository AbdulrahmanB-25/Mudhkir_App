import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/router.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../l10n/app_localizations.dart';

/// First launch: explains the app and lets the user start right away
/// (offline, no account) or sign in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cloud = context.select<AuthRepository, bool>((a) => a.cloudAvailable);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 132,
                  height: 132,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.welcomeTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.welcomeSubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            _Feature(
              icon: Icons.alarm_on_rounded,
              title: l10n.featureRemindersTitle,
              text: l10n.featureRemindersText,
            ),
            _Feature(
              icon: Icons.wifi_off_rounded,
              title: l10n.featureOfflineTitle,
              text: l10n.featureOfflineText,
            ),
            _Feature(
              icon: Icons.family_restroom_rounded,
              title: l10n.featureCompanionsTitle,
              text: l10n.featureCompanionsText,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () =>
                  context.read<SettingsRepository>().completeOnboarding(),
              child: Text(l10n.startWithoutAccount),
            ),
            if (cloud) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.push(Routes.login),
                child: Text(l10n.signIn),
              ),
              TextButton(
                onPressed: () => context.push(Routes.signup),
                child: Text(l10n.createAccount),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
