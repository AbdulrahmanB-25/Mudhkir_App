/// Build-time configuration.
///
/// The app talks to the "mudhkir" Supabase project by default, so any run
/// button works. To use another project, pass your own values with
/// `flutter run --dart-define-from-file=env.json` (see env.example.json).
/// To run fully offline, pass `--dart-define=SUPABASE_URL=` (empty).
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://emvpjqtaylchpmaugipy.supabase.co',
  );

  /// The project's publishable key. It is meant to ship inside the app:
  /// row-level security in the database decides what each user can see.
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_R7Z65GFDIMzSfpgSC7dPmg_CbewTTjE',
  );

  static bool get isCloudConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseKey.isNotEmpty &&
      !supabaseUrl.contains('YOUR-PROJECT-REF');

  /// Contact address shown in Settings (hidden when empty).
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL');
}
