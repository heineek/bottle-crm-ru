import 'package:bottle_crm/core/theme/theme.dart';
import 'package:bottle_crm/data/models/ticket.dart';
import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/screens/support/support_create_screen.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:bottle_crm/widgets/tickets/ticket_properties_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _ru(Widget home) => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.light,
    locale: const Locale('ru'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  ),
);

void main() {
  setUp(() => applyLanguage('ru'));
  tearDown(() => applyLanguage('en'));

  testWidgets('the support form renders in Russian', (tester) async {
    await tester.pumpWidget(_ru(const SupportCreateScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Новое обращение в поддержку'), findsOneWidget);
    expect(find.text('Тема'), findsOneWidget);
    expect(find.text('Создать обращение'), findsOneWidget);

    await tester.tap(find.text('Создать обращение'));
    await tester.pumpAndSettle();
    expect(find.text('Укажите тему.'), findsOneWidget);
    expect(find.text('Выберите категорию.'), findsOneWidget);
  });

  testWidgets('the ticket SLA card renders units and dates in Russian', (
    tester,
  ) async {
    final ticket = Ticket(
      id: 't-1',
      name: 'Printer on fire',
      status: TicketStatus.newStatus,
      priority: TicketPriority.normal,
      ticketType: TicketType.question,
      createdAt: DateTime(2026, 5, 1),
      firstResponseAt: DateTime(2026, 5, 1, 9, 30),
    );
    await tester.pumpWidget(
      _ru(
        Scaffold(body: TicketPropertiesCard(ticket: ticket, watcherCount: 2)),
      ),
    );

    expect(find.text('СВОЙСТВА'), findsOneWidget);
    expect(find.text('Первый ответ'), findsOneWidget);
    expect(find.text('Выполнен'), findsOneWidget);
    expect(find.text('Ответ 1 мая, 09:30'), findsOneWidget);
    expect(find.text('Наблюдатели'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
