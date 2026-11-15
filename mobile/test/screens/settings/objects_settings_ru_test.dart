import 'package:bottle_crm/data/models/custom_object.dart';
import 'package:bottle_crm/l10n/l10n.dart';
import 'package:bottle_crm/providers/auth_provider.dart';
import 'package:bottle_crm/providers/custom_objects_provider.dart';
import 'package:bottle_crm/screens/settings/object_field_sheet.dart';
import 'package:bottle_crm/screens/settings/object_settings_screen.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeObjects extends CustomObjectsNotifier {
  @override
  Future<CustomObjectsAnswer?> build() async => const CustomObjectsAnswer(
    hasCustomObjects: true,
    objects: [_property],
    linkTargets: [
      LinkTarget(key: 'contact', label: 'Contact', labelPlural: 'Contacts'),
    ],
  );
}

const _property = ObjectSummary(
  key: 'property',
  label: 'Property',
  labelPlural: 'Properties',
);

void main() {
  setUp(() => applyLanguage('ru'));
  tearDown(() => applyLanguage('en'));

  testWidgets('an object reads in Russian, its tenant labels as typed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isOrgAdminProvider.overrideWithValue(true),
          customObjectsProvider.overrideWith(_FakeObjects.new),
          objectSettingsProvider('property').overrideWith(
            (ref) async => const ObjectSettingsData(
              summary: _property,
              fields: [
                ObjectField(
                  key: 'owner',
                  label: 'Owner',
                  fieldType: 'link',
                  target: 'contact',
                  many: false,
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: ObjectSettingsScreen(objectKey: 'property'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ПОЛЯ'), findsOneWidget);
    expect(find.text('Добавить поле'), findsOneWidget);
    expect(find.text('Изменить объект'), findsOneWidget);
    expect(find.text('Связь · Contacts, одна'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
  });

  test('field types and team counts follow the language', () {
    expect(objectFieldTypeLabels['checkbox'], 'Флажок');
    expect(appL10n.settingsTeamMemberTokens(5), '5 API-токенов');
    expect(appL10n.settingsTagsMoved(2, 'VIP'), '2 записи перенесены в «VIP»');
    applyLanguage('en');
    expect(objectFieldTypeLabels['checkbox'], 'Checkbox');
    expect(
      appL10n.settingsTeamOrphanTokens(1),
      '1 API token still work for someone who has been deactivated.',
    );
    expect(appL10n.settingsTagsDuplicateUsage(1, 'VIP'), 'VIP is on 1 record');
  });
}
