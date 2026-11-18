import 'package:bottle_crm/data/models/sales_goal.dart';
import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/providers/auth_provider.dart';
import 'package:bottle_crm/providers/goals_provider.dart';
import 'package:bottle_crm/screens/goals/goals_screen.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Goals in Russian at 390px, and the count goals priced with plural rules.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => applyLanguage('en'));

  test('a count goal is counted with Russian plural forms', () {
    applyLanguage('ru');
    String deals(double n) =>
        formatGoalValue(n, goalType: 'DEALS_CLOSED', symbol: r'$');
    expect(deals(1), '1 сделка');
    expect(deals(3), '3 сделки');
    expect(deals(5), '5 сделок');
    expect(
      formatGoalValue(21, goalType: 'ACTIVITIES', symbol: r'$'),
      '21 активность',
    );
  });

  test('English is unchanged', () {
    applyLanguage('en');
    expect(
      formatGoalValue(1, goalType: 'DEALS_CLOSED', symbol: r'$'),
      '1 deal',
    );
    expect(
      formatGoalValue(40, goalType: 'ACTIVITIES', symbol: r'$'),
      '40 activities',
    );
  });

  testWidgets('the goals screen reads in Russian', (tester) async {
    applyLanguage('ru');
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          goalsProvider.overrideWith(_OneGoal.new),
          isOrgAdminProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          locale: Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: GoalsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Цели'), findsOneWidget);
    expect(find.text('ЦЕЛИ'), findsOneWidget);
    expect(find.text('РЕЙТИНГ'), findsOneWidget);
    expect(find.text('Идут сейчас'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _OneGoal extends GoalsNotifier {
  @override
  Future<GoalsData> build() async {
    final goals = [
      SalesGoal.fromJson(const {
        'id': 'g2',
        'name': 'New logos this month',
        'goal_type': 'DEALS_CLOSED',
        'target_value': '8',
        'period_type': 'MONTHLY',
        'period_start': '2026-08-01',
        'period_end': '2026-08-31',
        'is_active': true,
        'progress_value': 3,
        'progress_percent': 37,
        'status': 'on_track',
      }),
    ];
    return GoalsData(
      goals: goals,
      totals: goalTotals(goals, today: '2026-08-08'),
    );
  }
}
