import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/reopen_policy.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import 'reopen_form_sheet.dart';

/// Whether a customer's reply brings a closed ticket back.
///
/// Four fields, and the only question that matters is what number goes in the
/// window. Nothing answers that except how customers actually behave, so the
/// three 30-day figures sit above the settings rather than below them.
///
/// **Admin-only to read, not just to write.** `ReopenPolicyView.get` calls
/// `is_org_admin` before it answers, unlike every other read in this cluster,
/// so a member is told why rather than shown a failed request.
class ReopenScreen extends ConsumerWidget {
  const ReopenScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final policy = ref.read(reopenPolicyProvider).value;
    if (policy == null) return;
    final payload = await showReopenFormSheet(context, policy);
    if (payload == null || !context.mounted) return;
    final error = await ref
        .read(reopenPolicyProvider.notifier)
        .savePolicy(payload);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? context.l10n.settingsReopenSaved)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isOrgAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsReopenTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.pencil),
              tooltip: context.l10n.settingsReopenEditPolicy,
              onPressed: () => _edit(context, ref),
            ),
        ],
      ),
      body: isAdmin ? const _AdminBody() : const _MemberNotice(),
    );
  }
}

/// The read itself is gated, so a member never issues it.
class _MemberNotice extends StatelessWidget {
  const _MemberNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsReopenAdminsOnly,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsReopenMemberBody,
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

class _AdminBody extends ConsumerWidget {
  const _AdminBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reopenPolicyProvider);
    final l10n = context.l10n;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _ErrorState(
        onRetry: () => ref.read(reopenPolicyProvider.notifier).refresh(),
      ),
      data: (policy) => RefreshIndicator(
        onRefresh: () => ref.read(reopenPolicyProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _Summary(policy: policy),
            _SectionHeader(l10n.settingsReopenLast30Days),
            _Metrics(policy: policy),
            _SectionHeader(l10n.settingsReopenRuleSection),
            _SettingRow(
              label: l10n.settingsReopenEnabledLabel,
              detail: l10n.settingsReopenEnabledDetail,
              value: policy.isEnabled
                  ? l10n.settingsReopenOn
                  : l10n.settingsReopenOff,
            ),
            _SettingRow(
              label: l10n.settingsReopenWindowLabel,
              detail: l10n.settingsReopenWindowDetail,
              value: l10n.settingsReopenWindowDays(policy.windowDays),
            ),
            _SettingRow(
              label: l10n.settingsReopenStatusLabel,
              detail: l10n.settingsReopenStatusDetail,
              value: reopenStatusName(policy.reopenToStatus),
            ),
            _SettingRow(
              label: l10n.settingsReopenNotifyLabel,
              detail: l10n.settingsReopenNotifyDetail,
              value: policy.notifyAssigned ? l10n.commonYes : l10n.commonNo,
            ),
            _Footnote(isEnabled: policy.isEnabled),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.policy});

  final ReopenPolicy policy;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      margin: const EdgeInsets.only(bottom: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              LucideIcons.rotateCcw,
              size: 18,
              color: policy.isEnabled
                  ? AppColors.textSecondary
                  : AppColors.warning600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(reopenSummary(policy), style: AppTypography.body),
          ),
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.policy});

  final ReopenPolicy policy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final caveat = missedWindowCaveat(policy);
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 22,
            runSpacing: 12,
            children: [
              _Stat(
                value: '${policy.reopenedLast30d}',
                label: l10n.settingsReopenStatReopened,
                tone: AppColors.textPrimary,
              ),
              _Stat(
                // "n/a" rather than 0 while the policy is off: the figure is
                // a zero by construction there, and a plain 0 reads as
                // reassurance about the one thing certainly happening.
                value: caveat != null
                    ? l10n.settingsReopenNotApplicable
                    : '${policy.repliesAfterWindow30d}',
                label: l10n.settingsReopenStatMissed,
                tone: caveat == null && policy.repliesAfterWindow30d > 0
                    ? AppColors.warning600
                    : AppColors.textPrimary,
              ),
              _Stat(
                value: l10n.settingsReopenMedianDays(policy.medianDaysToReply),
                label: l10n.settingsReopenStatMedian,
                tone: AppColors.textPrimary,
              ),
            ],
          ),
          if (caveat != null) ...[
            const SizedBox(height: 12),
            Container(
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
                    LucideIcons.mailX,
                    size: 18,
                    color: AppColors.warning600,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      caveat,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (policy.repliesAfterWindow30d > 0) ...[
            const SizedBox(height: 12),
            Text(
              l10n.settingsReopenLateReplies(
                policy.repliesAfterWindow30d,
                policy.windowDays,
              ),
              style: AppTypography.caption.copyWith(
                color: AppColors.warning600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.tone});

  final String value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.h2.copyWith(
            fontWeight: FontWeight.w600,
            color: tone,
          ),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.detail,
    required this.value,
  });

  final String label;
  final String detail;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.overline.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.isEnabled});

  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    // Present tense either way, so with the policy off this cannot be written
    // as though a reply still reopened anything.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Text(
        isEnabled
            ? context.l10n.settingsReopenFootnoteOn
            : context.l10n.settingsReopenFootnoteOff,
        style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
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
              context.l10n.settingsReopenLoadError,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.settingsReopenTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
