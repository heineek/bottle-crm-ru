import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../services/app_language.dart';
import '../services/auth_service.dart';
import 'auth_provider.dart';

/// The language the app renders in. Recomputed whenever the auth state
/// changes (sign-in, org switch, sign-out), since the token carries both the
/// user's choice and the org default. See `services/app_language.dart`.
class LanguageNotifier extends Notifier<String> {
  @override
  String build() {
    ref.watch(authProvider);
    return _resolve();
  }

  String _resolve() {
    final token = AuthService().accessToken;
    final language = resolveLanguage(
      user: userLanguageOf(token),
      device: PlatformDispatcher.instance.locales,
      org: orgLanguageOf(token),
    );
    applyLanguage(language);
    return language;
  }

  /// Re-read the token, after a refresh that may have changed its claims.
  void reload() => state = _resolve();

  /// The user's own choice, or null when they chose none.
  String? get chosen =>
      supportedLanguage(userLanguageOf(AuthService().accessToken));

  /// Save [language] (null: let the phone, then the org, decide) as the
  /// user's choice, shared with the web. The token is refreshed so its
  /// `language` claim, which every client reads, says the same. Returns the
  /// API's message on failure.
  Future<String?> choose(String? language) async {
    final response = await ApiService().patch(ApiConfig.profileUpdate, {
      'language': language ?? '',
    });
    if (!response.success) return response.message ?? '';
    await AuthService().refreshAccessToken();
    reload();
    return null;
  }
}

final languageProvider = NotifierProvider<LanguageNotifier, String>(
  LanguageNotifier.new,
);
