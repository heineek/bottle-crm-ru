import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../config/api_config.dart';
import '../data/models/automation.dart';
import '../services/api_service.dart';
import '../services/automation_text.dart';
import 'auth_provider.dart';

final automationCatalogueProvider =
    FutureProvider.autoDispose<AutomationCatalogue>((ref) async {
      ref.watch(selectedOrgProvider.select((o) => o?.id));
      final response = await ApiService().get(ApiConfig.automationCatalogue);
      final data = response.data;
      if (!response.success || data == null) {
        throw Exception(
          response.message ?? appL10n.appMsgCouldNotLoadTheCatalogue,
        );
      }
      return AutomationCatalogue.fromJson(data);
    }, retry: (_, _) => null);

/// The rules list answered 404: this API has no automation, which the hosted
/// app can meet while its API is a release behind. Read as "not offered", as
/// custom objects read a 404.
class AutomationNotOffered implements Exception {
  const AutomationNotOffered();

  @override
  String toString() => appL10n.appMsgAutomationRulesAreNotAvailableHere;
}

class AutomationRulesNotifier extends AsyncNotifier<AutomationRulesAnswer> {
  @override
  Future<AutomationRulesAnswer> build() {
    ref.watch(selectedOrgProvider.select((o) => o?.id));
    return _fetch();
  }

  Future<AutomationRulesAnswer> _fetch() async {
    final response = await ApiService().get(ApiConfig.automationRules);
    if (response.statusCode == 404) throw const AutomationNotOffered();
    final data = response.data;
    if (!response.success || data == null) {
      throw Exception(response.message ?? appL10n.appMsgCouldNotLoadTheRules);
    }
    return AutomationRulesAnswer.fromJson(data);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_fetch);
  }

  bool _moving = false;

  /// Moves one rule a place and posts every id in the new order. Null on
  /// success, else the message to show.
  Future<String?> move(String id, String direction) async {
    final held = shownAutomationRules(state);
    if (held == null) return appL10n.appMsgTheRulesAreStillLoading;
    if (_moving) return appL10n.appMsgAMoveIsAlreadyInProgress;
    final step = switch (direction) {
      'up' => -1,
      'down' => 1,
      _ => null,
    };
    if (step == null) return 'Cannot move a rule $direction.';
    final ids = held.rules.map((r) => r.id).toList();
    final at = ids.indexOf(id);
    if (at < 0) return appL10n.appMsgThatRuleIsNoLongerInThe;
    final to = at + step;
    if (to < 0 || to >= ids.length) {
      return appL10n.appMsgThatRuleCannotMoveFurther;
    }
    ids.insert(to, ids.removeAt(at));
    _moving = true;
    try {
      final response = await ApiService().post(ApiConfig.automationReorder, {
        'ids': ids,
      });
      if (!response.success) {
        return response.message ?? appL10n.appMsgCouldNotChangeTheOrder;
      }
      await refresh();
      return null;
    } finally {
      _moving = false;
    }
  }
}

/// The only way to read the rules for display: Riverpod keeps the previous
/// value through a reload and a failed load, which after an org switch is
/// another org's.
AutomationRulesAnswer? shownAutomationRules(
  AsyncValue<AutomationRulesAnswer> v,
) => v.isLoading || v.hasError ? null : v.value;

/// True only when the last load found no automation on this API.
bool automationNotOffered(AsyncValue<AutomationRulesAnswer> v) =>
    v.error is AutomationNotOffered;

final automationRulesProvider =
    AsyncNotifierProvider<AutomationRulesNotifier, AutomationRulesAnswer>(
      AutomationRulesNotifier.new,
      retry: (_, _) => null,
    );

final automationRuleProvider = FutureProvider.autoDispose
    .family<AutomationRule, String>((ref, id) async {
      ref.watch(selectedOrgProvider.select((o) => o?.id));
      final response = await ApiService().get(ApiConfig.automationRule(id));
      final data = response.data;
      if (!response.success || data == null) {
        throw Exception(response.message ?? appL10n.appMsgCouldNotLoadTheRule);
      }
      return AutomationRule.fromJson(data);
    }, retry: (_, _) => null);

final automationRunsProvider = FutureProvider.autoDispose
    .family<RunPage, ({String id, int offset})>((ref, key) async {
      ref.watch(selectedOrgProvider.select((o) => o?.id));
      final response = await ApiService().get(
        ApiConfig.automationRuleRuns(key.id, offset: key.offset),
      );
      final data = response.data;
      if (!response.success || data == null) {
        throw Exception(response.message ?? appL10n.appMsgCouldNotLoadTheRuns);
      }
      return RunPage.fromJson(data, offset: key.offset);
    }, retry: (_, _) => null);

typedef RuleWrite = ({AutomationRule? rule, RuleErrors? errors});

/// The writes. After one succeeds the screen invalidates
/// [automationRulesProvider] and the rule's [automationRuleProvider].
class AutomationApi {
  AutomationApi([ApiService? api]) : _api = api ?? ApiService();

  final ApiService _api;

  RuleWrite _written(ApiResponse<Map<String, dynamic>> r) {
    final data = r.data;
    if (r.success && data != null) {
      return (rule: AutomationRule.fromJson(data), errors: null);
    }
    return (rule: null, errors: RuleErrors.fromResponse(r));
  }

  Future<RuleWrite> create(Map<String, dynamic> body) async =>
      _written(await _api.post(ApiConfig.automationRules, body));

  Future<RuleWrite> update(String id, Map<String, dynamic> body) async =>
      _written(await _api.patch(ApiConfig.automationRule(id), body));

  Future<String?> switchOff(String id) async {
    final r = await _api.patch(ApiConfig.automationRule(id), {
      'is_active': false,
    });
    return r.success
        ? null
        : (r.message ?? appL10n.appMsgCouldNotSwitchTheRuleOff);
  }

  Future<String?> delete(String id) async {
    final r = await _api.delete(ApiConfig.automationRule(id));
    return r.success
        ? null
        : (r.message ?? appL10n.appMsgCouldNotDeleteTheRule);
  }

  Future<({List<RunStep> steps, String? error})> tryRule(
    String id,
    String recordId,
  ) async {
    final r = await _api.post(ApiConfig.automationRuleTry(id), {
      'record_id': recordId,
    });
    if (r.statusCode == 404) {
      return (
        steps: <RunStep>[],
        error: appL10n.appMsgThatRecordDoesNotExistOrYou,
      );
    }
    final data = r.data;
    if (!r.success || data == null) {
      return (
        steps: <RunStep>[],
        error: r.message ?? appL10n.appMsgCouldNotTryTheRule,
      );
    }
    final raw = data['steps'];
    final steps = raw is List
        ? raw
              .whereType<Map>()
              .map((m) => RunStep.fromJson(Map<String, dynamic>.from(m)))
              .toList()
        : <RunStep>[];
    return (steps: steps, error: null);
  }
}

final automationApiProvider = Provider<AutomationApi>((ref) => AutomationApi());
