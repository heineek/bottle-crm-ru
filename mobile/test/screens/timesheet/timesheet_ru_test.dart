import 'package:bottle_crm/data/models/time_entry.dart';
import 'package:bottle_crm/data/models/timesheet.dart';
import 'package:bottle_crm/l10n/app_localizations.dart';
import 'package:bottle_crm/providers/timesheet_provider.dart';
import 'package:bottle_crm/screens/timesheet/timesheet_screen.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTimesheet extends TimesheetNotifier {
  @override
  Future<TimesheetWeek> build() async => TimesheetWeek(
    start: DateTime(2026, 8, 3),
    end: DateTime(2026, 8, 9),
    profileName: '',
    days: [
      TimesheetDay(
        date: DateTime(2026, 8, 3),
        entries: [
          TimeEntry(
            id: 'e1',
            caseId: 'case-9',
            caseName: 'Printer on fire',
            profileId: 'p1',
            startedAt: DateTime(2026, 8, 3, 9),
            endedAt: DateTime(2026, 8, 3, 11, 5),
            durationMinutes: 125,
            billable: true,
            invoiceId: 'inv-2',
            invoiceNumber: 'INV-0002',
          ),
        ],
      ),
      TimesheetDay(date: DateTime(2026, 8, 4)),
    ],
  );
}

const _localizations = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

void main() {
  setUp(() => applyLanguage('ru'));
  tearDown(() => applyLanguage('en'));

  testWidgets('the timesheet reads in Russian', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [timesheetProvider.overrideWith(_FakeTimesheet.new)],
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: _localizations,
          home: const TimesheetScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Учёт времени'), findsOneWidget);
    expect(find.text('2 ч 5 мин'), findsWidgets);
    expect(find.text('учтено за неделю'), findsOneWidget);
    expect(find.text('в счёте INV-0002'), findsOneWidget);
    expect(find.text('Ничего не учтено'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
