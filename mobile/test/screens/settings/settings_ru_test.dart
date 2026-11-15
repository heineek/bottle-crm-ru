import 'package:bottle_crm/data/models/custom_object.dart';
import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/providers/auth_provider.dart';
import 'package:bottle_crm/providers/custom_objects_provider.dart';
import 'package:bottle_crm/screens/settings/settings_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoObjects extends CustomObjectsNotifier {
  @override
  Future<CustomObjectsAnswer?> build() async => null;
}

void main() {
  testWidgets('the settings hub renders in Russian at 390px', (tester) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customObjectsProvider.overrideWith(_NoObjects.new),
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
          home: SettingsHubScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Настройки организации'), findsOneWidget);
    expect(find.text('Дополнительные поля'), findsOneWidget);
    expect(find.text('Organization settings'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
