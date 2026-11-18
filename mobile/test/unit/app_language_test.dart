import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:bottle_crm/config/api_config.dart';
import 'package:bottle_crm/providers/language_provider.dart';
import 'package:bottle_crm/services/api_service.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';

import '../support/org_zone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => applyLanguage(baseLanguage));

  // A stand-in second language, so the order is checked whatever this build
  // ships: `fr` here has nothing to do with the bundled catalogs.
  const twoLanguages = ['en', 'fr'];

  group('supportedLanguage', () {
    test('falls back from a regional tag to its base language', () {
      expect(supportedLanguage('en-GB'), 'en');
      expect(supportedLanguage('EN_us'), 'en');
      expect(supportedLanguage('en'), 'en');
      expect(supportedLanguage('fr-CA', supported: twoLanguages), 'fr');
    });

    test('defaults to the bundled catalogs', () {
      expect(supportedLanguages, contains(baseLanguage));
      expect(supportedLanguage('xx'), isNull);
      expect(supportedLanguage('xx', supported: ['en', 'xx']), 'xx');
    });

    test('refuses what is not supported', () {
      expect(supportedLanguage('de'), isNull);
      expect(supportedLanguage(''), isNull);
      expect(supportedLanguage(null), isNull);
      expect(supportedLanguage(42), isNull);
    });
  });

  group('resolveLanguage', () {
    test('prefers the user, then the phone, then the org, then English', () {
      const en = [Locale('en', 'US')];
      const fr = [Locale('fr', 'FR')];
      String resolve({
        String? user,
        List<Locale> device = const [],
        String? org,
      }) => resolveLanguage(
        user: user,
        device: device,
        org: org,
        supported: twoLanguages,
      );

      expect(resolve(user: 'fr', device: en, org: 'en'), 'fr');
      expect(resolve(device: fr, org: 'en'), 'fr');
      expect(
        resolve(device: const [Locale('de'), Locale('fr')], org: 'en'),
        'fr',
      );
      expect(resolve(device: const [Locale('de')], org: 'fr'), 'fr');
      expect(resolve(device: en, org: 'fr'), 'en');
      expect(resolve(), 'en');
    });

    test('falls through a stored language that is no longer supported', () {
      expect(resolveLanguage(user: 'xx', org: 'xx'), 'en');
    });
  });

  group('claims', () {
    test('reads the user choice and the org default from the token', () {
      final token = orgToken('UTC', language: 'fr', orgLanguage: 'en');
      expect(userLanguageOf(token), 'fr');
      expect(orgLanguageOf(token), 'en');
    });

    test('a blank or missing choice is no choice', () {
      expect(userLanguageOf(orgToken('UTC', language: '')), isNull);
      expect(userLanguageOf(orgToken('UTC')), isNull);
      expect(orgLanguageOf(orgToken(null)), isNull);
      expect(userLanguageOf(null), isNull);
    });
  });

  group('dates', () {
    final day = DateTime(2026, 11, 10);

    test('English keeps the pattern the app always used', () {
      applyLanguage('en');
      expect(localDateFormat('d MMM yyyy', 'yMMMd').format(day), '10 Nov 2026');
      expect(Intl.defaultLocale, 'en');
    });

    test('another language uses its own order and month names', () {
      applyLanguage('de');
      expect(Intl.defaultLocale, 'de');
      expect(
        localDateFormat('MMM d, yyyy', 'yMMMMd').format(day),
        '10. November 2026',
      );
    });
  });

  group('Accept-Language', () {
    tearDown(() => ApiService().setClientForTesting(http.Client()));

    test('every request names the current language', () async {
      final seen = <String?>[];
      ApiService().setClientForTesting(
        MockClient((request) async {
          seen.add(request.headers['Accept-Language']);
          return http.Response('{}', 200);
        }),
      );

      await ApiService().get(ApiConfig.orgLocales);
      applyLanguage('de');
      await ApiService().get(ApiConfig.orgLocales);

      expect(seen, ['en', 'de']);
    });
  });

  group('choosing a language', () {
    late FakeAuthApi auth;
    late ProviderContainer container;

    setUp(() async {
      auth = await useOrgZone('UTC');
      container = ProviderContainer();
    });

    tearDown(() async {
      container.dispose();
      await auth.uninstall();
    });

    /// `PATCH /profile/` answered with [status], and the token refresh with
    /// [FakeAuthApi.nextRefresh].
    void answerProfile(int status, {List<Object?>? sent}) {
      ApiService().setClientForTesting(
        MockClient((request) async {
          if (request.url.path.endsWith('/profile/') &&
              request.method == 'PATCH') {
            sent?.add(jsonDecode(request.body));
            return status == 200
                ? http.Response('{}', 200)
                : http.Response(
                    jsonEncode({
                      'language': ['"xx" is not a valid choice.'],
                    }),
                    status,
                  );
          }
          if (request.url.path.endsWith('/auth/refresh-token/')) {
            return http.Response(
              jsonEncode({'access': auth.nextRefresh, 'refresh': 'rotated'}),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );
    }

    test('saves the choice, refreshes the token and follows it', () async {
      final sent = <Object?>[];
      answerProfile(200, sent: sent);
      auth.nextRefresh = orgToken('UTC', language: 'en');
      applyLanguage('de');

      final error = await container
          .read(languageProvider.notifier)
          .choose('en');

      expect(error, isNull);
      expect(sent, [
        {'language': 'en'},
      ]);
      expect(container.read(languageProvider), 'en');
      expect(container.read(languageProvider.notifier).chosen, 'en');
      expect(currentLanguage, 'en');
    });

    test('automatic sends a blank choice', () async {
      final sent = <Object?>[];
      answerProfile(200, sent: sent);
      auth.nextRefresh = orgToken('UTC');

      await container.read(languageProvider.notifier).choose(null);

      expect(sent, [
        {'language': ''},
      ]);
      expect(container.read(languageProvider.notifier).chosen, isNull);
    });

    test('a refused choice changes nothing and says why', () async {
      answerProfile(400);
      final before = container.read(languageProvider);

      final error = await container
          .read(languageProvider.notifier)
          .choose('xx');

      expect(error, isNotNull);
      expect(container.read(languageProvider), before);
    });
  });

  group('message catalogs', () {
    Map<String, dynamic> read(String name) =>
        jsonDecode(File('lib/l10n/$name').readAsStringSync())
            as Map<String, dynamic>;
    Iterable<String> keys(Map<String, dynamic> arb) =>
        arb.keys.where((k) => !k.startsWith('@'));
    // A placeholder is `{name}` or `{name, plural, ...}`. An ICU branch body
    // (`other{Select}`, `=1{...}`) follows a selector word, so it is skipped.
    Set<String> placeholders(Object? message) => {
      for (final m in RegExp(r'(?<![\w=])\{(\w+)[,}]').allMatches('$message'))
        m[1]!,
    };

    final source = read('app_en.arb');
    final catalogs = Directory('lib/l10n')
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .where((n) => n.endsWith('.arb'))
        .toList();

    test('every bundled language has a catalog', () {
      expect(catalogs.toSet(), {
        for (final code in supportedLanguages) 'app_$code.arb',
      });
    });

    for (final name in catalogs) {
      test('$name has every key with the same placeholders', () {
        final target = read(name);
        expect(keys(target).toSet(), keys(source).toSet());
        for (final key in keys(source)) {
          expect(
            placeholders(target[key]),
            placeholders(source[key]),
            reason: key,
          );
        }
      });

      test('$name has no empty message and no em dash', () {
        final target = read(name);
        for (final key in keys(target)) {
          // A blank in English (a separator such as " ") is deliberate.
          if ('${source[key]}'.trim().isNotEmpty) {
            expect('${target[key]}'.trim(), isNotEmpty, reason: key);
          }
          expect('${target[key]}', isNot(contains('\u2014')), reason: key);
        }
      });
    }
  });

  group('Russian', () {
    test('is bundled and matched from a regional tag', () {
      expect(supportedLanguages, contains('ru'));
      expect(supportedLanguage('ru-RU'), 'ru');
      expect(supportedLanguage('RU_ru'), 'ru');
    });

    test('is resolved from the user, the phone or the org', () {
      const en = [Locale('en', 'US')];
      expect(resolveLanguage(user: 'ru', device: en, org: 'en'), 'ru');
      expect(resolveLanguage(device: const [Locale('ru', 'RU')]), 'ru');
      expect(resolveLanguage(device: const [Locale('de')], org: 'ru'), 'ru');
    });

    test('uses its own order and month names', () {
      applyLanguage('ru');
      expect(Intl.defaultLocale, 'ru');
      expect(
        localDateFormat('MMM d, yyyy', 'yMMMMd').format(DateTime(2026, 11, 10)),
        '10 ноября 2026\u202fг.',
      );
    });
  });
}
