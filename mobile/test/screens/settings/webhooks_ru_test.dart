import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/screens/settings/webhook_form_sheet.dart';
import 'package:bottle_crm/screens/settings/webhooks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The webhook sheet and the member notice in Russian.
void main() {
  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: home),
      ),
    );
    await tester.pump();
  }

  testWidgets('the new webhook sheet reads in Russian', (tester) async {
    await pump(tester, const WebhookFormSheet(catalogue: []));

    expect(find.text('Новый вебхук'), findsOneWidget);
    expect(find.text('URL-адрес'), findsOneWidget);
    expect(find.text('СОБЫТИЯ'), findsOneWidget);
    expect(find.text('Добавить вебхук'), findsOneWidget);

    await tester.tap(find.text('Добавить вебхук'));
    await tester.pump();
    expect(find.text('URL должен начинаться с https://.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a member is told in Russian why the list is closed', (
    tester,
  ) async {
    await pump(tester, const WebhooksMemberNotice());

    expect(find.text('Только для администраторов'), findsOneWidget);
    expect(find.text('Administrators only'), findsNothing);
  });
}
