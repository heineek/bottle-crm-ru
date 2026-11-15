/// Which language the app renders in, and the one it asks the API for.
///
/// The same order as the API (`backend/common/locale.py`) and the web
/// (`frontend/src/lib/i18n/locale.js`), so a screen and the errors it shows
/// agree:
///
///   1. the user's own choice (the access token's `language` claim),
///   2. the phone's languages, in order,
///   3. the org's default (`org_settings.default_language` claim),
///   4. English.
///
/// Like `org_date.dart`, it reads the claims from the current token on every
/// call: login, org switch and refresh each replace the token.
library;

import 'dart:ui' show Locale;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../l10n/app_localizations.dart';

const String baseLanguage = 'en';

/// The languages this build has messages for, from `lib/l10n/`.
List<String> get supportedLanguages => [
  for (final locale in AppLocalizations.supportedLocales) locale.languageCode,
];

/// [code] as one of [supportedLanguages], or null. A regional tag falls back
/// to its base language, so `ru-RU` and `ru_RU` match `ru`.
String? supportedLanguage(Object? code) {
  if (code is! String || code.trim().isEmpty) return null;
  final normalized = code.trim().toLowerCase().replaceAll('_', '-');
  final supported = supportedLanguages;
  if (supported.contains(normalized)) return normalized;
  final base = normalized.split('-').first;
  return supported.contains(base) ? base : null;
}

String resolveLanguage({
  String? user,
  List<Locale> device = const [],
  String? org,
}) {
  final chosen = supportedLanguage(user);
  if (chosen != null) return chosen;
  for (final locale in device) {
    final found = supportedLanguage(locale.languageCode);
    if (found != null) return found;
  }
  return supportedLanguage(org) ?? baseLanguage;
}

/// The `language` claim: the user's own choice, or null when they chose none.
String? userLanguageOf(String? accessToken) {
  if (accessToken == null) return null;
  final value = JwtDecoder.tryDecode(accessToken)?['language'];
  return value is String && value.isNotEmpty ? value : null;
}

/// The org's default language from the `org_settings` claim, or null.
String? orgLanguageOf(String? accessToken) {
  if (accessToken == null) return null;
  final settings = JwtDecoder.tryDecode(accessToken)?['org_settings'];
  final value = settings is Map ? settings['default_language'] : null;
  return value is String && value.isNotEmpty ? value : null;
}

/// The language currently rendered, for code with no [BuildContext] (date
/// patterns, the API's Accept-Language). Set by `languageProvider`.
String currentLanguage = baseLanguage;

/// Make [language] the one every `DateFormat` and the API use.
void applyLanguage(String language) {
  currentLanguage = language;
  Intl.defaultLocale = language;
  // The bundled symbols load synchronously; the Future is only the API shape.
  initializeDateFormatting(language);
}

/// A date pattern for the current language: [english] exactly as the app has
/// always printed it, or the locale's own order for [skeleton] (an `intl`
/// skeleton such as `yMMMd`) in any other language, where a hand-written
/// English order would read wrong ("нояб. 10, 2026").
///
/// Build it per use, never into a `static final`: that would freeze the
/// language the class was first loaded in.
DateFormat localDateFormat(String english, String skeleton) =>
    currentLanguage == baseLanguage
    // Locale-less: `en_US` symbols are built in, while `'en'` needs
    // initializeDateFormatting, which a test that never applied a language skips.
    ? DateFormat(english)
    : DateFormat(skeleton, currentLanguage);
