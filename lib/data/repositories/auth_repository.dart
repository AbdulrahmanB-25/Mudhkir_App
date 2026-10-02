import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why an account action failed, so screens can show a translated message.
enum AuthFailureReason {
  invalidCredentials,
  emailNotConfirmed,
  emailInUse,
  weakPassword,
  invalidCode,
  rateLimited,
  network,
  cloudUnavailable,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.reason, [this.details]);

  final AuthFailureReason reason;
  final String? details;

  @override
  String toString() => 'AuthFailure($reason, $details)';
}

/// The signed-in Supabase user, or a local guest when signed out or when
/// the app is built without Supabase settings.
class AuthRepository extends ChangeNotifier {
  AuthRepository(this._client) {
    final client = _client;
    if (client != null) {
      _user = client.auth.currentUser;
      _subscription = client.auth.onAuthStateChange.listen((state) {
        final user = state.session?.user;
        if (user?.id != _user?.id || user?.email != _user?.email) {
          _user = user;
          notifyListeners();
        }
      });
    }
  }

  /// Owner id used for data created while not signed in.
  static const guestId = 'local';

  final SupabaseClient? _client;
  StreamSubscription<AuthState>? _subscription;
  User? _user;

  bool get cloudAvailable => _client != null;
  bool get isSignedIn => _user != null;
  String get ownerId => _user?.id ?? guestId;
  String? get email => _user?.email;
  String? get pendingEmail => _user?.newEmail;

  /// Name entered at sign-up (also kept in the profile).
  String? get displayName => _user?.userMetadata?['name'] as String?;

  SupabaseClient get _cloud {
    final client = _client;
    if (client == null) {
      throw const AuthFailure(AuthFailureReason.cloudUnavailable);
    }
    return client;
  }

  Future<void> signIn({required String email, required String password}) =>
      _guard(
        () => _cloud.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        ),
      );

  /// Returns true when Supabase requires the email to be confirmed before
  /// the first sign-in.
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _guard(
      () => _cloud.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'name': name.trim()},
      ),
    );
    return response.session == null;
  }

  /// Sends an email with a 6-digit code (see RUNNING.md: the "Reset
  /// password" template must include `{{ .Token }}`).
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _cloud.auth.resetPasswordForEmail(email.trim()));

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) => _guard(() async {
    await _cloud.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.recovery,
    );
    await _cloud.auth.updateUser(UserAttributes(password: newPassword));
  });

  /// Checks the current password first, as the old app did.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _guard(() async {
    final email = this.email;
    if (email == null) throw const AuthFailure(AuthFailureReason.unknown);
    await _cloud.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );
    await _cloud.auth.updateUser(UserAttributes(password: newPassword));
  });

  /// Supabase emails a confirmation link to the new address; the email only
  /// changes after it is confirmed.
  Future<void> changeEmail(String newEmail) => _guard(
    () => _cloud.auth.updateUser(UserAttributes(email: newEmail.trim())),
  );

  Future<void> signOut() => _guard(() => _cloud.auth.signOut());

  /// Deletes the account and all its cloud data (required by the App Store
  /// for apps that offer sign-up).
  Future<void> deleteAccount() => _guard(() async {
    await _cloud.rpc<void>('delete_my_account');
    await _cloud.auth.signOut();
  });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthFailure {
      rethrow;
    } on AuthRetryableFetchException catch (e) {
      throw AuthFailure(AuthFailureReason.network, e.message);
    } on AuthWeakPasswordException catch (e) {
      throw AuthFailure(AuthFailureReason.weakPassword, e.message);
    } on AuthException catch (e) {
      throw AuthFailure(_reasonFor(e), e.message);
    } on Exception catch (e) {
      final text = e.toString();
      if (text.contains('SocketException') ||
          text.contains('ClientException') ||
          text.contains('Failed host lookup')) {
        throw AuthFailure(AuthFailureReason.network, text);
      }
      throw AuthFailure(AuthFailureReason.unknown, text);
    }
  }

  static AuthFailureReason _reasonFor(AuthException e) {
    switch (e.code) {
      case 'invalid_credentials':
        return AuthFailureReason.invalidCredentials;
      case 'email_not_confirmed':
        return AuthFailureReason.emailNotConfirmed;
      case 'user_already_exists':
      case 'email_exists':
        return AuthFailureReason.emailInUse;
      case 'weak_password':
        return AuthFailureReason.weakPassword;
      case 'otp_expired':
      case 'otp_disabled':
        return AuthFailureReason.invalidCode;
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return AuthFailureReason.rateLimited;
    }
    if (e.statusCode == '429') return AuthFailureReason.rateLimited;
    return AuthFailureReason.unknown;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
