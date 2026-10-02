import 'package:flutter/widgets.dart';

import '../local/app_database.dart';

/// App preferences kept in the local database (readable from background
/// isolates too, unlike in-memory state).
class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const _localeKey = 'locale';
  static const _onboardedKey = 'onboarded';
  static const defaultLocale = Locale('ar');
  static const supportedLocales = [Locale('ar'), Locale('en')];

  Locale _locale = defaultLocale;
  bool _onboarded = false;

  Locale get locale => _locale;
  bool get onboarded => _onboarded;

  Future<void> load() async {
    _locale = await readLocale(_db);
    _onboarded = await _db.readValue(_onboardedKey) == 'true';
    notifyListeners();
  }

  static Future<Locale> readLocale(AppDatabase db) async {
    final code = await db.readValue(_localeKey);
    return supportedLocales.firstWhere(
      (l) => l.languageCode == code,
      orElse: () => defaultLocale,
    );
  }

  Future<void> setLocale(Locale locale) async {
    if (locale == _locale) return;
    _locale = locale;
    await _db.writeValue(_localeKey, locale.languageCode);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _onboarded = true;
    await _db.writeValue(_onboardedKey, 'true');
    notifyListeners();
  }
}
