import 'package:bottle_crm/data/models/account.dart';
import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/providers/accounts_provider.dart';
import 'package:bottle_crm/providers/contacts_provider.dart';
import 'package:bottle_crm/screens/accounts/accounts_list_screen.dart';
import 'package:bottle_crm/screens/contacts/contacts_list_screen.dart';
import 'package:bottle_crm/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The accounts and contacts lists in Russian at 390px: the count strip goes
/// through plural rules ("2 из 3 компаний"), never a number plus a fixed word.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The saved views button asks for its list; nothing here needs an answer.
    ApiService().setClientForTesting(
      MockClient((_) async => http.Response('{"results": []}', 200)),
    );
  });

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    required List<Override> overrides,
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the accounts list reads in Russian', (tester) async {
    await pump(
      tester,
      const AccountsListScreen(),
      overrides: [accountsProvider.overrideWith(_TwoOfThreeAccounts.new)],
    );
    expect(find.text('Компании'), findsOneWidget);
    expect(find.text('Открытые'), findsOneWidget);
    expect(find.text('Закрытые'), findsOneWidget);
    expect(find.text('2 из 3 компаний'), findsOneWidget);
    expect(find.text('Northwind'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty accounts list says so in Russian', (tester) async {
    await pump(
      tester,
      const AccountsListScreen(),
      overrides: [accountsProvider.overrideWith(_NoAccounts.new)],
      textScale: 1.5,
    );
    expect(find.text('Компаний пока нет'), findsOneWidget);
    expect(find.text('0 компаний'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty contacts list offers the import in Russian', (
    tester,
  ) async {
    await pump(
      tester,
      const ContactsListScreen(),
      overrides: [contactsProvider.overrideWith(_NoContacts.new)],
    );
    expect(find.text('Контакты'), findsOneWidget);
    expect(find.text('Контактов пока нет'), findsOneWidget);
    expect(find.text('Импортировать контакты'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TwoOfThreeAccounts extends AccountsNotifier {
  @override
  Future<AccountsListData> build() async => AccountsListData(
    accounts: [
      Account.fromJson(const {'id': 'a1', 'name': 'Northwind'}),
      Account.fromJson(const {'id': 'a2', 'name': 'Contoso'}),
    ],
    totalCount: 3,
  );
}

class _NoAccounts extends AccountsNotifier {
  @override
  Future<AccountsListData> build() async => const AccountsListData();
}

class _NoContacts extends ContactsNotifier {
  @override
  Future<ContactsListData> build() async => const ContactsListData();
}
