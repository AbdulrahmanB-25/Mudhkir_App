/// Build-time configuration, passed with
/// `flutter run --dart-define-from-file=env.json`.
///
/// When the Supabase values are missing the app runs fully offline: no
/// sign-in, sync or companions, but every other feature works.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The project's publishable key (older projects call it the "anon" key).
  /// It is safe to ship in the app; row-level security protects the data.
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isCloudConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseKey.isNotEmpty &&
      !supabaseUrl.contains('YOUR-PROJECT-REF');

  /// Contact address shown in Settings (hidden when empty).
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
}
