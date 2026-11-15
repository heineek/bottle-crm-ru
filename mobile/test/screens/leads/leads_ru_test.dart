import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/providers/leads_provider.dart';
import 'package:bottle_crm/screens/leads/leads_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The leads list in Russian: its own strings, and a count that takes the
/// Russian plural forms rather than "lead" plus "s".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, int total) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [leadsProvider.overrideWith(() => _Loaded(total))],
        child: const MaterialApp(
          locale: Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: LeadsListScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('an empty list reads in Russian', (tester) async {
    await pump(tester, 0);

    expect(find.text('Лиды'), findsOneWidget);
    expect(find.text('0 лидов'), findsOneWidget);
    expect(find.text('Лидов пока нет'), findsOneWidget);
    expect(find.text('Добавить лид'), findsOneWidget);
    expect(find.text('Источник'), findsOneWidget);
    expect(find.text('No leads yet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the count takes the few form', (tester) async {
    await pump(tester, 3);
    expect(find.text('3 лида'), findsOneWidget);
  });

  testWidgets('the count takes the one form past twenty', (tester) async {
    await pump(tester, 21);
    expect(find.text('21 лид'), findsOneWidget);
  });
}

class _Loaded extends LeadsNotifier {
  _Loaded(this.total);

  final int total;

  @override
  Future<LeadsListData> build() async =>
      LeadsListData(totalCount: total, hasMore: false);
}
