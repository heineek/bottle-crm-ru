import 'package:bottle_crm/core/theme/theme.dart';
import 'package:bottle_crm/data/models/ticket.dart';
import 'package:bottle_crm/data/models/time_entry.dart';
import 'package:bottle_crm/l10n/l10n.dart';
import 'package:bottle_crm/providers/lookup_provider.dart';
import 'package:bottle_crm/providers/tickets_provider.dart';
import 'package:bottle_crm/screens/tickets/ticket_detail_screen.dart';
import 'package:bottle_crm/services/api_service.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

/// The ticket detail reads its own strings from the Russian messages, and the
/// English ones stay as they were.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void usePhone(WidgetTester tester, {double textScale = 1.0}) {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  setUp(() => ApiService().setClientForTesting(_EmptyClient()));
  tearDown(() {
    ApiService().setClientForTesting(http.Client());
    applyLanguage('en');
  });

  Widget app(String lang) => ProviderScope(
    overrides: [
      ticketsProvider.overrideWith(_FakeTicketsNotifier.new),
      usersProvider.overrideWithValue(const []),
      tagsProvider.overrideWithValue(const []),
      accountOptionsProvider.overrideWithValue(const []),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      locale: Locale(lang),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: GoRouter(
        initialLocation: '/here',
        routes: [
          GoRoute(
            path: '/here',
            builder: (_, _) => const TicketDetailScreen(ticketId: 'c1'),
          ),
        ],
      ),
    ),
  );

  for (final scale in [1.0, 1.5]) {
    testWidgets('renders in Russian at 390px, text x$scale', (tester) async {
      applyLanguage('ru');
      usePhone(tester, textScale: scale);
      await tester.pumpWidget(app('ru'));
      await tester.pumpAndSettle();

      expect(find.text('Обзор'), findsOneWidget);
      expect(find.text('Сведения об обращении'), findsOneWidget);
      expect(find.text('Компания не привязана'), findsOneWidget);
      expect(find.text('Ticket Information'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Ещё'));
      await tester.pumpAndSettle();
      expect(find.text('Закрыть обращение'), findsOneWidget);
      expect(find.text('Изменить приоритет'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the activity tab describes events in Russian', (tester) async {
    applyLanguage('ru');
    usePhone(tester);
    await tester.pumpWidget(app('ru'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Активность'));
    await tester.pumpAndSettle();
    expect(find.text('Обращение создано'), findsOneWidget);
    expect(find.text('Учтено 30 мин'), findsOneWidget);
  });

  testWidgets('English is unchanged', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(app('en'));
    await tester.pumpAndSettle();

    expect(find.text('Ticket Information'), findsOneWidget);
    expect(find.text('Sep 1, 2026'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Created the ticket'), findsOneWidget);
    expect(find.text('Logged 30m'), findsOneWidget);
  });
}

class _EmptyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value('{}'.codeUnits),
        200,
        request: request,
      );
}

class _FakeTicketsNotifier extends TicketsNotifier {
  @override
  Future<TicketsListData> build() async =>
      TicketsListData(tickets: const [], totalCount: 0, hasMore: false);

  @override
  Future<TicketDetailResult?> getTicketDetail(String id) async =>
      TicketDetailResult(
        ticketObj: Ticket.fromJson({
          'id': id,
          'name': 'Printer on fire',
          'status': 'New',
          'priority': 'Normal',
          'created_at': '2026-09-01T09:00:00Z',
        }),
        activities: const [
          {'action': 'CREATE', 'user_email': 'a@example.com'},
          {
            'action': 'TIME_LOGGED',
            'metadata': {'minutes': 30},
          },
        ],
        commentPermission: true,
        internalCommentIds: const {},
      );

  @override
  Future<TicketWatchers?> getWatchers(String id) async => const TicketWatchers(
    watchers: [],
    count: 0,
    isCurrentUserWatching: false,
  );

  @override
  Future<TicketTreeNode?> fetchTree(String id) async => null;

  @override
  Future<List<TimeEntry>> fetchTimeEntries(String id) async => const [];

  @override
  Future<TimeSummary?> fetchTimeSummary(String id) async => null;
}
