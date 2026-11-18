import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/providers/documents_provider.dart';
import 'package:bottle_crm/screens/documents/documents_list_screen.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoDocuments extends DocumentsNotifier {
  @override
  Future<DocumentsData> build() async => const DocumentsData();
}

void main() {
  setUp(() => applyLanguage('ru'));
  tearDown(() => applyLanguage('en'));

  testWidgets('an empty documents list reads in Russian', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [documentsProvider.overrideWith(_NoDocuments.new)],
        child: const MaterialApp(
          locale: Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: DocumentsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Документы'), findsOneWidget);
    expect(find.text('Документов нет'), findsOneWidget);
    expect(find.byTooltip('Загрузить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
