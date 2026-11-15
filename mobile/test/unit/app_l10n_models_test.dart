import 'package:bottle_crm/data/models/access_token.dart';
import 'package:bottle_crm/data/models/models.dart';
import 'package:bottle_crm/data/models/sales_goal.dart';
import 'package:bottle_crm/data/models/tag.dart';
import 'package:bottle_crm/l10n/l10n.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:bottle_crm/widgets/common/badge.dart';
import 'package:bottle_crm/widgets/forms/unsaved_changes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => applyLanguage(baseLanguage));

  group('model labels follow the current language', () {
    test('English is unchanged', () {
      expect(LeadStatus.closed.label, 'Closed');
      expect(TicketStatus.closed.label, 'Closed');
      expect(TaskStatus.completed.label, 'Completed');
      expect(InvoiceStatus.partiallyPaid.label, 'Partially paid');
      expect(goalStatusLabel('on_track'), 'On track');
    });

    test('Russian statuses agree with their entity', () {
      applyLanguage('ru');
      expect(LeadStatus.closed.label, 'Закрыт');
      expect(TicketStatus.closed.label, 'Закрыто');
      expect(TaskStatus.completed.label, 'Выполнена');
      expect(InvoiceStatus.sent.label, 'Отправлен');
      expect(EstimateStatus.sent.label, 'Отправлено');
      expect(TicketPriority.urgent.label, 'Срочный');
    });

    test('a label is read per call, not frozen at first use', () {
      expect(LeadStatus.assigned.label, 'Assigned');
      applyLanguage('ru');
      expect(LeadStatus.assigned.label, 'Назначен');
      applyLanguage('en');
      expect(LeadStatus.assigned.label, 'Assigned');
    });

    test('the API values do not change with the language', () {
      applyLanguage('ru');
      expect(Priority.high.value, 'High');
      expect(boardPriorityValue(Priority.high), 'high');
      expect(TicketStatus.closed.value, 'Closed');
    });

    test('Russian counts use the plural forms', () {
      applyLanguage('ru');
      final tag = Tag.fromJson({
        'id': 't1',
        'name': 'vip',
        'usage': {'leads': 2, 'opportunities': 5},
      });
      expect(tagUsageSummary(tag), contains('2 лида'));
      expect(tagUsageSummary(tag), contains('5 сделок'));
    });

    test('validation messages are translated', () {
      applyLanguage('ru');
      expect(tokenNameProblem(''), 'Укажите название токена.');
    });
  });

  testWidgets('the shared discard dialog renders Russian', (tester) async {
    applyLanguage('ru');
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                StatusBadge.fromTicketStatus(TicketStatus.pending),
                TextButton(
                  onPressed: () => confirmDiscard(context),
                  child: const Text('open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Ожидает'), findsOneWidget);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Отменить изменения?'), findsOneWidget);
    expect(find.text('Не сохранять'), findsOneWidget);
  });
}
