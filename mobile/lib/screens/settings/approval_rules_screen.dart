import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/approval_rule.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common/badge.dart';
import 'approval_rule_form_sheet.dart';

/// What gates a ticket close, and who can clear it.
///
/// The approvals queue answers "what is waiting on me". This answers "what will
/// be gated next time, and by whom": the same rows, a different question.
///
/// **A ticket is gated by one rule**, the most specific that matches it, so the
/// list is a set of gates and fallbacks rather than a stack. Two rules with
/// identical conditions are not equals either: the newest takes every case, so
/// the older never runs however live it looks.
///
/// Reading is open to every member; every write is admin-only and the server
/// answers 403 to anyone else.
class ApprovalRulesScreen extends ConsumerWidget {
  const ApprovalRulesScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ApprovalRule? existing,
  ) async {
    final payload = await showApprovalRuleFormSheet(
      context,
      existing: existing,
    );
    if (payload == null || !context.mounted) return;
    final notifier = ref.read(approvalRulesProvider.notifier);
    final error = existing == null
        ? await notifier.createRule(payload)
        : await notifier.updateRule(existing.id, payload);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (existing == null
                  ? context.l10n.settingsApprovalRulesAdded
                  : context.l10n.settingsApprovalRulesSaved),
        ),
      ),
    );
  }

  Future<void> _turnOff(
    BuildContext context,
    WidgetRef ref,
    ApprovalRule rule,
  ) async {
    final error = await ref
        .read(approvalRulesProvider.notifier)
        .deactivateRule(rule.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? context.l10n.settingsApprovalRulesTurnedOffToast,
        ),
      ),
    );
  }

  Future<void> _turnOn(
    BuildContext context,
    WidgetRef ref,
    ApprovalRule rule,
  ) async {
    final error = await ref
        .read(approvalRulesProvider.notifier)
        .activateRule(rule.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? context.l10n.settingsApprovalRulesTurnedOnToast),
      ),
    );
  }

  /// Delete, or turn off. Which one is the server's decision, so the dialog
  /// names both outcomes and the snackbar reports the one that happened.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ApprovalRule rule,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsApprovalRulesDeleteTitle(rule.name)),
        content: Text(approvalRuleDeleteExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.settingsApprovalRulesKeepIt),
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
    final result = await ref
        .read(approvalRulesProvider.notifier)
        .deleteRule(rule.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.error ?? approvalRuleDeleteResult(turnedOff: result.turnedOff),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(approvalRulesProvider);
    final isAdmin = ref.watch(isOrgAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsApprovalRulesTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: context.l10n.settingsApprovalRulesNewRule,
              onPressed: () => _edit(context, ref, null),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.read(approvalRulesProvider.notifier).refresh(),
        ),
        data: (state) {
          if (state.rules.isEmpty) return _EmptyState(isAdmin: isAdmin);
          final shadowed = state.shadowed;
          return RefreshIndicator(
            onRefresh: () => ref.read(approvalRulesProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _Summary(state: state),
                for (final rule in state.rules)
                  _RuleRow(
                    rule: rule,
                    beatenBy: shadowed.contains(rule.id)
                        ? shadowedBy(rule, state.rules)
                        : null,
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

  final ApprovalRulesState state;

  @override
  Widget build(BuildContext context) {
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
                label: context.l10n.settingsApprovalRulesStatActive,
              ),
              _Stat(
                value: '${state.count - state.active}',
                label: context.l10n.settingsApprovalRulesStatTurnedOff,
              ),
              _Stat(
                value: '${state.pending}',
                label: context.l10n.settingsApprovalRulesStatWaiting,
              ),
            ],
          ),
          if (state.stranding > 0) ...[
            const SizedBox(height: 14),
            _Warning(
              text: context.l10n.settingsApprovalRulesStranding(
                state.stranding,
              ),
            ),
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
    required this.beatenBy,
    required this.canEdit,
    required this.onEdit,
    required this.onTurnOff,
    required this.onTurnOn,
    required this.onDelete,
  });

  final ApprovalRule rule;

  /// The rule that takes this one's tickets, when one does. Non-null means this
  /// row never runs.
  final ApprovalRule? beatenBy;

  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onTurnOff;
  final VoidCallback onTurnOn;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rule.name,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: rule.isActive
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.settingsApprovalRulesGates(rule.matchSentence),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.settingsApprovalRulesClearedBy(rule.approverSentence),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (!rule.isActive)
                StatusBadge(
                  label: context.l10n.settingsApprovalRulesBadgeTurnedOff,
                  color: AppColors.gray500,
                ),
              if (rule.clearableByNobody)
                StatusBadge(
                  label: context.l10n.settingsApprovalRulesBadgeNobody,
                  color: AppColors.danger600,
                ),
              if (beatenBy != null)
                StatusBadge(
                  label: context.l10n.settingsApprovalRulesBadgeNeverRuns,
                  color: AppColors.danger600,
                ),
              if (rule.pendingCount > 0)
                StatusBadge(
                  label: context.l10n.settingsApprovalRulesBadgeWaiting(
                    rule.pendingCount,
                  ),
                  color: AppColors.gray500,
                ),
            ],
          ),
          if (rule.clearableByNobody) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsApprovalRulesNobodyFlag,
              style: AppTypography.caption.copyWith(
                color: AppColors.warning600,
              ),
            ),
          ],
          if (beatenBy != null) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsApprovalRulesShadowedFlag(beatenBy!.name),
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
                    child: Text(context.l10n.commonEdit),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: rule.isActive
                      ? OutlinedButton(
                          onPressed: onTurnOff,
                          child: Text(
                            context.l10n.settingsApprovalRulesTurnOff,
                          ),
                        )
                      : OutlinedButton(
                          onPressed: onTurnOn,
                          child: Text(context.l10n.settingsApprovalRulesTurnOn),
                        ),
                ),
                SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: onDelete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger600,
                    ),
                    child: Text(context.l10n.commonDelete),
                  ),
                ),
              ],
            ),
          ],
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
        context.l10n.settingsApprovalRulesFootnote,
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
              LucideIcons.circleCheckBig,
              size: 40,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsApprovalRulesEmptyTitle,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? context.l10n.settingsApprovalRulesEmptyAdmin
                  : context.l10n.settingsApprovalRulesEmptyMember,
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
              context.l10n.settingsApprovalRulesLoadError,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.settingsApprovalRulesTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
