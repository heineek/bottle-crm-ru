import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/routing_rule.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common/badge.dart';
import 'routing_rule_form_sheet.dart';

/// Who a new ticket lands on.
///
/// **The list order is the program.** The engine walks active rules by
/// `priority_order` and takes the first match, so the rows are numbered and
/// never re-sorted client-side. A rule that stops processing says so, because
/// combined with an empty pool that is how a rule silently swallows every
/// ticket it matches.
///
/// Reading is open to every member; every write is admin-only and the server
/// answers 403 to anyone else.
class RoutingScreen extends ConsumerWidget {
  const RoutingScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    RoutingRule? existing,
  ) async {
    final payload = await showRoutingRuleFormSheet(context, existing: existing);
    if (payload == null || !context.mounted) return;
    final notifier = ref.read(routingRulesProvider.notifier);
    final error = existing == null
        ? await notifier.createRule(payload)
        : await notifier.updateRule(existing.id, payload);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (existing == null
                  ? context.l10n.settingsRoutingRuleAdded
                  : context.l10n.settingsRoutingRuleSaved),
        ),
      ),
    );
  }

  Future<void> _turnOff(
    BuildContext context,
    WidgetRef ref,
    RoutingRule rule,
  ) async {
    final error = await ref
        .read(routingRulesProvider.notifier)
        .deactivateRule(rule.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? context.l10n.settingsRoutingRuleTurnedOff),
      ),
    );
  }

  Future<void> _turnOn(
    BuildContext context,
    WidgetRef ref,
    RoutingRule rule,
  ) async {
    final error = await ref
        .read(routingRulesProvider.notifier)
        .activateRule(rule.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? context.l10n.settingsRoutingRuleTurnedOn),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    RoutingRule rule,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // "Delete", not "Turn off", because this one really does delete.
        title: Text(context.l10n.settingsRoutingDeleteTitle(rule.name)),
        content: Text(routingRemovalExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.settingsRoutingKeepIt),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger600),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await ref
        .read(routingRulesProvider.notifier)
        .deleteRule(rule.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? context.l10n.settingsRoutingRuleDeleted)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(routingRulesProvider);
    final isAdmin = ref.watch(isOrgAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsRoutingTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: context.l10n.settingsRoutingNewRule,
              onPressed: () => _edit(context, ref, null),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.read(routingRulesProvider.notifier).refresh(),
        ),
        data: (state) {
          if (state.rules.isEmpty) return _EmptyState(isAdmin: isAdmin);
          return RefreshIndicator(
            onRefresh: () => ref.read(routingRulesProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _Summary(state: state),
                for (final (index, rule) in state.rules.indexed)
                  _RuleRow(
                    rule: rule,
                    position: index + 1,
                    canEdit: isAdmin,
                    onEdit: () => _edit(context, ref, rule),
                    onTurnOff: () => _turnOff(context, ref, rule),
                    onTurnOn: () => _turnOn(context, ref, rule),
                    onDelete: () => _delete(context, ref, rule),
                  ),
                const _Footnote(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final RoutingRulesState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      margin: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _Stat(
                value: '${state.active}',
                label: l10n.settingsRoutingStatRunning,
              ),
              _Stat(
                value: '${state.count - state.active}',
                label: l10n.settingsRoutingStatTurnedOff,
              ),
              _Stat(
                value: '${state.unroutedLast30d}',
                label: l10n.settingsRoutingStatUnrouted,
              ),
            ],
          ),
          if (state.dead > 0) ...[
            const SizedBox(height: 14),
            _Warning(text: l10n.settingsRoutingDeadWarning(state.dead)),
          ],
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 18,
            color: AppColors.warning600,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.h2.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.position,
    required this.canEdit,
    required this.onEdit,
    required this.onTurnOff,
    required this.onTurnOn,
    required this.onDelete,
  });

  final RoutingRule rule;

  /// Where this rule sits in the run order, counting from one. Shown rather
  /// than `priority_order`, which is a sparse number an admin picks (100, 200)
  /// and does not answer "which runs first".
  final int position;

  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onTurnOff;
  final VoidCallback onTurnOn;
  final VoidCallback onDelete;

  String _target(AppLocalizations l10n) {
    if (rule.routesToTeam) {
      return rule.targetTeam == null
          ? l10n.settingsRoutingTargetNoTeam
          : l10n.settingsRoutingTargetTeam(rule.targetTeam!.name);
    }
    if (rule.targetAssignees.isEmpty) return l10n.settingsRoutingTargetNobody;
    if (rule.targetAssignees.length == 1) {
      return rule.targetAssignees.first.name;
    }
    return l10n.settingsRoutingTargetPeople(rule.targetAssignees.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final next = rule.nextInRotation;
    final inactive = rule.targetAssignees.where((p) => !p.isActive).toList();
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  '$position',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  rule.name,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: rule.isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routingMatchSentence(rule),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.settingsRoutingGoesTo(
                    _target(l10n),
                    routingStrategyLabel(rule.strategy).toLowerCase(),
                  ),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.settingsRoutingNextInRotation(next.name),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (!rule.isActive)
                      StatusBadge(
                        label: l10n.settingsRoutingBadgeTurnedOff,
                        color: AppColors.gray500,
                      ),
                    if (rule.stopProcessing)
                      StatusBadge(
                        label: l10n.settingsRoutingBadgeStopsHere,
                        color: AppColors.gray500,
                      ),
                    StatusBadge(
                      label: l10n.settingsRoutingBadgeMatched(
                        rule.matchedLast30d,
                      ),
                      color: AppColors.gray500,
                    ),
                  ],
                ),
                // Two failures that look identical on a list that only shows
                // names, and both leave tickets unassigned.
                if (rule.assignsNobody) ...[
                  const SizedBox(height: 8),
                  Text(
                    rule.stopProcessing
                        ? l10n.settingsRoutingNobodyStops
                        : l10n.settingsRoutingNobodyFallsThrough,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning600,
                    ),
                  ),
                ] else if (inactive.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    inactive.length == 1
                        ? l10n.settingsRoutingOneInactive(inactive.first.name)
                        : l10n.settingsRoutingManyInactive(inactive.length),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning600,
                    ),
                  ),
                ],
                if (canEdit) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          onPressed: onEdit,
                          child: Text(l10n.commonEdit),
                        ),
                      ),
                      SizedBox(
                        height: 40,
                        child: rule.isActive
                            ? OutlinedButton(
                                onPressed: onTurnOff,
                                child: Text(l10n.settingsRoutingTurnOff),
                              )
                            : OutlinedButton(
                                onPressed: onTurnOn,
                                child: Text(l10n.settingsRoutingTurnOn),
                              ),
                      ),
                      SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          onPressed: onDelete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger600,
                          ),
                          child: Text(l10n.commonDelete),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(
        context.l10n.settingsRoutingFootnote,
        style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.gitBranch,
              size: 40,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsRoutingEmptyTitle,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? context.l10n.settingsRoutingEmptyAdmin
                  : context.l10n.settingsRoutingEmptyMember,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.triangleAlert,
              size: 40,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsRoutingLoadError,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.settingsRoutingTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
