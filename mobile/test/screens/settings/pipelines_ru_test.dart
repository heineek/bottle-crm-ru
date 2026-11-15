import 'package:bottle_crm/data/models/deal_pipeline.dart';
import 'package:bottle_crm/providers/auth_provider.dart';
import 'package:bottle_crm/screens/settings/deal_pipeline_detail_screen.dart';
import 'package:bottle_crm/screens/settings/modules_screen.dart';
import 'package:bottle_crm/screens/settings/options_editor.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => applyLanguage('ru'));
  tearDown(() => applyLanguage('en'));

  test('a stage summary counts days with Russian plurals', () {
    const stage = DealPipelineStage(
      id: 's1',
      code: 'qualify',
      label: 'Qualify',
      expectedDays: 2,
    );
    expect(dealStageSummary(stage), contains('через 2 дня'));
    expect(dealStageSummary(stage), contains('«Застряла» через 3.'));
  });

  testWidgets('a member reads the modules notice in Russian', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isOrgAdminProvider.overrideWithValue(false)],
        child: const MaterialApp(home: ModulesScreen()),
      ),
    );
    expect(find.text('Модули'), findsOneWidget);
    expect(
      find.text(
        'Включать и выключать модули может только администратор организации.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the options editor reads in Russian', (tester) async {
    final option = OptionDraft(value: '', label: '');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OptionsEditor(
            options: [option],
            onAdd: () {},
            onRemove: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Варианты'), findsOneWidget);
    expect(find.text('Вариант 1'), findsOneWidget);
    expect(find.text('Добавить вариант'), findsOneWidget);
    option.controller.dispose();
  });
}
