import 'package:bottle_crm/data/models/automation.dart';
import 'package:bottle_crm/providers/auth_provider.dart';
import 'package:bottle_crm/providers/automation_provider.dart';
import 'package:bottle_crm/screens/settings/automation/automation_runs_screen.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '3f2b8c1e-7a4d-4e2b-9c1a-5d6e7f8a9b0c';

Future<void> _open(
  WidgetTester tester, {
  bool admin = true,
  List<AutomationRun> runs = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isOrgAdminProvider.overrideWithValue(admin),
        automationRuleProvider.overrideWith(
          (ref, id) async => AutomationRule(
            id: id,
            objectKey: 'lead',
            trigger: TriggerDraft(),
          ),
        ),
        automationRunsProvider.overrideWith(
          (ref, key) async =>
              RunPage(runs: runs, count: runs.length, offset: key.offset),
        ),
      ],
      child: const MaterialApp(home: AutomationRunsScreen(ruleId: _id)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => applyLanguage('ru'));
  tearDown(() => applyLanguage('en'));

  testWidgets('a member sees the admin-only notice in Russian', (tester) async {
    await _open(tester, admin: false);
    expect(find.text('Запуски'), findsOneWidget);
    expect(
      find.text(
        'Правила автоматизации видит только администратор организации.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no runs reads in Russian', (tester) async {
    await _open(tester);
    expect(find.text('Запусков пока нет'), findsOneWidget);
  });

  testWidgets('a failed run shows its Russian pill and pager', (tester) async {
    await _open(
      tester,
      runs: [
        AutomationRun(
          id: 'run-1',
          createdAt: DateTime.utc(2026, 1, 15, 10, 42),
          recordId: '',
          recordName: '',
          objectKey: 'lead',
          status: 'failed',
          triggeredByRuleName: 'Owner rotation',
        ),
      ],
    );
    expect(find.text('Сбой'), findsOneWidget);
    expect(find.text('Запись'), findsOneWidget);
    expect(find.text('Запущено правилом «Owner rotation»'), findsOneWidget);
    expect(find.text('Новее'), findsOneWidget);
    expect(find.text('Старше'), findsOneWidget);
  });
}
