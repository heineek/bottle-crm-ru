import 'package:bottle_crm/data/models/invoice.dart';
import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/providers/invoices_provider.dart';
import 'package:bottle_crm/screens/invoices/invoices_list_screen.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInvoices extends InvoicesNotifier {
  @override
  Future<InvoicesListData> build() async => InvoicesListData(
    totals: const InvoiceTotals(
      count: 2,
      money: {'EUR': InvoiceMoneyTotals(outstanding: 12500, draft: 400)},
    ),
    invoices: [
      Invoice.fromJson({
        'id': '1',
        'invoice_number': 'INV-0001',
        'invoice_title': 'Retainer',
        'status': 'Draft',
        'account': 'acc-1',
        'account_name': 'Initech',
        'total_amount': '1234.50',
        'amount_due': '1234.50',
        'currency': 'EUR',
      }),
      Invoice.fromJson({
        'id': '2',
        'invoice_number': 'INV-0002',
        'invoice_title': 'Retainer',
        'status': 'Paid',
        'client_name': '',
        'total_amount': '400.00',
        'currency': 'EUR',
      }),
    ],
  );
}

void main() {
  setUp(() => applyLanguage('ru'));
  tearDown(() => applyLanguage('en'));

  testWidgets('the invoices list reads in Russian at 390px', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [invoicesProvider.overrideWith(_FakeInvoices.new)],
        child: const MaterialApp(
          locale: Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: InvoicesListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Счета'), findsOneWidget);
    expect(find.text('Все'), findsOneWidget);
    expect(find.text('2 счёта'), findsOneWidget);
    expect(find.text('Без компании'), findsOneWidget);
    expect(find.text('Отправить'), findsOneWidget);
    expect(find.text('1\u00a0234,50\u00a0€'), findsOneWidget);
    expect(find.textContaining('к оплате'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
