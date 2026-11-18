import 'dart:convert';

import 'package:bottle_crm/core/theme/theme.dart';
import 'package:bottle_crm/data/models/auth_response.dart';
import 'package:bottle_crm/data/models/models.dart';
import 'package:bottle_crm/providers/auth_provider.dart';
import 'package:bottle_crm/providers/deal_pipelines_provider.dart';
import 'package:bottle_crm/providers/deals_provider.dart';
import 'package:bottle_crm/screens/deals/deal_form_screen.dart';
import 'package:bottle_crm/services/api_service.dart';
import 'package:bottle_crm/widgets/common/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A duplicate deal name is refused as a field error on `name`, worded in the
/// caller's language. The form used to find it by the English words "already
/// exists", so a refusal worded otherwise never reached the Name input.
const _english = 'Opportunity already exists with this name';
const _reworded = 'Another deal has this name';

Map<String, dynamic> _refusal(String message) => {
  'error': true,
  'errors': {
    'name': [message],
  },
};

final _sales = DealPipeline.fromJson({
  'id': 'p1',
  'name': 'Sales',
  'is_default': true,
  'stages': [
    {'id': 's1', 'code': 'PROSPECTING', 'label': 'Prospecting', 'kind': 'open'},
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the deals notifier reads the name refusal by field', () {
    tearDown(() => ApiService().setClientForTesting(http.Client()));

    final deal = Deal(
      id: '',
      title: 'Renewal',
      value: 100,
      stage: 'PROSPECTING',
      probability: 10,
      companyName: '',
      assignedTo: '',
      priority: Priority.medium,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

    ProviderContainer answering(Object body) {
      ApiService().setClientForTesting(
        MockClient((request) async {
          if (request.method == 'GET') return http.Response('{}', 200);
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            400,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container;
    }

    for (final message in [_english, _reworded]) {
      test('create and update carry "$message" as the name error', () async {
        final notifier = answering(
          _refusal(message),
        ).read(dealsProvider.notifier);

        final created = await notifier.createDeal(deal);
        expect(created.success, isFalse);
        expect(created.nameError, message);

        final updated = await notifier.updateDeal('d1', deal);
        expect(updated.nameError, message);
      });
    }

    test('a refusal on another field is no name error', () async {
      final notifier = answering({
        'error': true,
        'errors': {
          'amount': ['Amount must be greater than zero'],
        },
      }).read(dealsProvider.notifier);

      final result = await notifier.createDeal(deal);
      expect(result.success, isFalse);
      expect(result.nameError, isNull);
    });

    test('a plain-string refusal is no name error', () async {
      final notifier = answering({
        'error': true,
        'errors': 'Opportunity already exists with this name',
      }).read(dealsProvider.notifier);

      expect((await notifier.createDeal(deal)).nameError, isNull);
    });
  });

  group('the form shows the name refusal next to the Name input', () {
    for (final message in [_english, _reworded]) {
      testWidgets('"$message"', (tester) async {
        final deals = _RefusingDeals(message);
        final router = GoRouter(
          initialLocation: '/new',
          routes: [
            GoRoute(path: '/new', builder: (_, _) => const DealFormScreen()),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authProvider.overrideWith(() => _FakeAuth()),
              dealsProvider.overrideWith(() => deals),
              dealPipelinesProvider.overrideWith(() => _FakePipelines()),
            ],
            child: MaterialApp.router(
              theme: AppTheme.light,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final name = find.widgetWithText(FloatingLabelInput, 'Deal Name *');
        await tester.enterText(name, 'Renewal');
        await tester.tap(find.text('Create Deal'));
        await tester.pumpAndSettle();

        expect(deals.attempts, 1);
        // Inline under the input, apart from the snackbar's "Name: ..." line.
        expect(
          find.descendant(of: name, matching: find.text(message)),
          findsOneWidget,
        );
        expect(find.text('Name: $message'), findsOneWidget);
      });
    }
  });
}

class _RefusingDeals extends DealsNotifier {
  _RefusingDeals(this.message);

  final String message;
  int attempts = 0;

  @override
  Future<DealsListData> build() async => const DealsListData();

  @override
  Future<({bool success, String? error, Deal? deal, String? nameError})>
  createDeal(Deal deal, {bool withLeadSource = false}) async {
    attempts++;
    return (
      success: false,
      error: 'Name: $message',
      deal: null,
      nameError: message,
    );
  }
}

class _FakePipelines extends DealPipelinesNotifier {
  @override
  Future<List<DealPipeline>> build() async => [_sales];
}

class _FakeAuth extends AuthNotifier {
  @override
  AuthState build() {
    const org = Organization(
      id: 'org-1',
      name: 'Test Org',
      role: 'ADMIN',
      defaultCurrency: 'USD',
    );
    return AuthState(
      user: const AuthUser(id: 'user-1', email: 'user@example.com'),
      organizations: [org],
      selectedOrganization: org,
      isAuthenticated: true,
    );
  }
}
