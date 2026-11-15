import 'package:bottle_crm/core/theme/theme.dart';
import 'package:bottle_crm/data/models/auth_response.dart';
import 'package:bottle_crm/data/models/models.dart';
import 'package:bottle_crm/l10n/l10n.dart';
import 'package:bottle_crm/providers/auth_provider.dart';
import 'package:bottle_crm/providers/board_provider.dart';
import 'package:bottle_crm/providers/tasks_provider.dart';
import 'package:bottle_crm/screens/tasks/board_screen.dart';
import 'package:bottle_crm/screens/tasks/tasks_list_screen.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tasks list and the board read their own strings from the Russian
/// messages, plurals included, and fit a 390px phone in Russian.
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

  tearDown(() => applyLanguage('en'));

  Widget app(String lang, Widget home, List overrides) {
    applyLanguage(lang);
    return ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuthNotifier.new),
        ...overrides.cast(),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: Locale(lang),
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
  }

  Widget tasksApp(String lang, List<Task> tasks) =>
      app(lang, const TasksListScreen(), [
        tasksProvider.overrideWith(
          () => _FakeTasksNotifier(
            TasksListData(
              tasks: tasks,
              totalCount: tasks.length,
              hasMore: false,
            ),
          ),
        ),
      ]);

  final done = [
    for (var i = 0; i < 5; i++)
      Task(
        id: 'task-$i',
        title: 'Finished $i',
        status: TaskStatus.completed,
        priority: Priority.low,
        createdAt: DateTime(2026, 5, 1),
      ),
  ];

  testWidgets('the tasks list renders in Russian with a plural count', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(tasksApp('ru', done));
    await tester.pumpAndSettle();

    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Поиск по названию задачи'), findsOneWidget);
    expect(find.text('Выполненные'), findsOneWidget);
    expect(find.text('5 задач'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the empty tasks list fits in Russian', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(tasksApp('ru', const []));
    await tester.pumpAndSettle();

    expect(find.text('Всё сделано!'), findsOneWidget);
    expect(find.text('Добавить задачу'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English keeps its wording', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(tasksApp('en', done));
    await tester.pumpAndSettle();

    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('5 tasks'), findsOneWidget);
  });

  testWidgets('the board with no boards renders in Russian', (tester) async {
    usePhone(tester, textScale: 1.5);
    await tester.pumpWidget(
      app('ru', const BoardScreen(), [
        boardProvider.overrideWith(_EmptyBoard.new),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Досок пока нет'), findsOneWidget);
    expect(find.text('Создать доску'), findsOneWidget);
    expect(find.text('Доска'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeTasksNotifier extends TasksNotifier {
  _FakeTasksNotifier(this.initialData);

  final TasksListData initialData;

  @override
  Future<TasksListData> build() async => initialData;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> loadMore() async {}
}

class _EmptyBoard extends BoardNotifier {
  @override
  Future<BoardData> build() async => const BoardData();
}

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    const org = Organization(
      id: 'org-1',
      name: 'Test Org',
      role: 'USER',
      currencySymbol: r'$',
    );
    return AuthState(
      user: const AuthUser(id: 'user-1', email: 'member@example.com'),
      organizations: [org],
      selectedOrganization: org,
      isAuthenticated: true,
    );
  }
}
