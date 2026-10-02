import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/companions/companion_detail_screen.dart';
import '../features/companions/companions_screen.dart';
import '../features/home/home_screen.dart';
import '../features/medication_detail/medication_detail_screen.dart';
import '../features/medication_form/medication_form_screen.dart';
import '../features/medications/medications_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/welcome/welcome_screen.dart';

/// All screens and their URLs. Notification taps navigate with these paths.
abstract final class Routes {
  static const welcome = '/welcome';
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const home = '/home';
  static const schedule = '/schedule';
  static const companions = '/companions';
  static const settings = '/settings';
  static const profile = '/profile';
  static const medications = '/medications';

  static String newMedication({String? ownerId}) =>
      ownerId == null ? '/medications/new' : '/medications/new?owner=$ownerId';

  static String medication(String id, {DateTime? doseAt}) => doseAt == null
      ? '/medications/$id'
      : '/medications/$id?at=${doseAt.toUtc().millisecondsSinceEpoch}';

  static String editMedication(String id) => '/medications/$id/edit';

  static String companion(String patientId) => '/companions/$patientId';
}

GoRouter buildRouter({
  required SettingsRepository settings,
  required AuthRepository auth,
}) {
  const openRoutes = {
    Routes.welcome,
    Routes.login,
    Routes.signup,
    Routes.forgotPassword,
  };

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: Listenable.merge([settings, auth]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      if (!settings.onboarded && !openRoutes.contains(location)) {
        return Routes.welcome;
      }
      if (settings.onboarded && location == Routes.welcome) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => ForgotPasswordScreen(
          initialEmail: state.uri.queryParameters['email'],
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.schedule,
                builder: (context, state) => const ScheduleScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.companions,
                builder: (context, state) => const CompanionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.medications,
        builder: (context, state) => const MedicationsScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => MedicationFormScreen(
              ownerId: state.uri.queryParameters['owner'],
            ),
          ),
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final at = int.tryParse(state.uri.queryParameters['at'] ?? '');
              return MedicationDetailScreen(
                medicationId: state.pathParameters['id']!,
                doseAt: at == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
              );
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) => MedicationFormScreen(
                  medicationId: state.pathParameters['id'],
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/companions/:patientId',
        builder: (context, state) => CompanionDetailScreen(
          patientId: state.pathParameters['patientId']!,
        ),
      ),
    ],
  );
}
