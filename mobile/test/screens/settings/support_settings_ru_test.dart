import 'package:bottle_crm/data/models/routing_rule.dart';
import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/providers/auth_provider.dart';
import 'package:bottle_crm/providers/settings_provider.dart';
import 'package:bottle_crm/screens/settings/reopen_screen.dart';
import 'package:bottle_crm/screens/settings/routing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TwoDeadRules extends RoutingRulesNotifier {
  @override
  Future<RoutingRulesState> build() async => RoutingRulesState(
    count: 2,
    active: 2,
    rules: [
      for (final id in ['r1', 'r2'])
        RoutingRule.fromJson({
          'id': id,
          'name': 'Rule $id',
          'priority_order': 10,
          'is_active': true,
          'strategy': 'direct',
          'stop_processing': false,
          'conditions': const [],
          'target_assignees': const [],
        }),
    ],
  );
}

Widget _ru(Widget home, {required bool isAdmin, List overrides = const []}) =>
    ProviderScope(
      overrides: [isOrgAdminProvider.overrideWithValue(isAdmin), ...overrides],
      child: MaterialApp(
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
  testWidgets('the reopen policy tells a member in Russian', (tester) async {
    await tester.pumpWidget(_ru(const ReopenScreen(), isAdmin: false));
    await tester.pumpAndSettle();

    expect(find.text('Повторное открытие'), findsOneWidget);
    expect(find.text('Только для администраторов'), findsOneWidget);
    expect(find.text('Administrators only'), findsNothing);
  });

  testWidgets('routing pluralises the dead-rule warning in Russian', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ru(
        const RoutingScreen(),
        isAdmin: true,
        overrides: [routingRulesProvider.overrideWith(_TwoDeadRules.new)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Маршрутизация обращений'), findsOneWidget);
    expect(
      find.textContaining('2 работающих правила: назначать некого.'),
      findsOneWidget,
    );
    expect(find.text('Выключить'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
