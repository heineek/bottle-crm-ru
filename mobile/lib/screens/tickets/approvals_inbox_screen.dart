import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/approval.dart';
import '../../providers/approvals_provider.dart';
import '../../widgets/common/common.dart';
import '../../l10n/l10n.dart';

/// Approvals inbox: Mine vs All, state filter (pending / approved / rejected
/// / cancelled / all). Pending rows expose approve / reject (with reason) /
/// cancel actions inline.
class ApprovalsInboxScreen extends ConsumerStatefulWidget {
  const ApprovalsInboxScreen({super.key});

  @override
  ConsumerState<ApprovalsInboxScreen> createState() =>
      _ApprovalsInboxScreenState();
}

class _ApprovalsInboxScreenState extends ConsumerState<ApprovalsInboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _state = 'pending';
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _mineTab => _tabController.index == 0;

  Future<void> _refresh() async {
    await ref
        .read(approvalsProvider.notifier)
        .fetch(ApprovalsQuery(state: _state, mine: _mineTab));
  }

  Future<void> _approve(Approval a) async {
    setState(() => _isBusy = true);
    final res = await ref.read(approvalsProvider.notifier).approve(a.id);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (res.success) {
      await _refresh();
    } else {
      _toast(
        res.message ?? context.l10n.ticketsInboxApproveFailed,
        error: true,
      );
    }
  }

  Future<void> _reject(Approval a) async {
    final reason = await _promptText(
      context.l10n.ticketsInboxRejectTitle,
      context.l10n.ticketsInboxRejectReason,
      context.l10n.ticketsInboxReject,
      required: true,
    );
    if (reason == null || reason.isEmpty) return;
    setState(() => _isBusy = true);
    final res = await ref.read(approvalsProvider.notifier).reject(a.id, reason);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (res.success) {
      await _refresh();
    } else {
      _toast(res.message ?? context.l10n.ticketsInboxRejectFailed, error: true);
    }
  }

  Future<void> _cancel(Approval a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.ticketsInboxCancelTitle),
        content: Text(context.l10n.ticketsInboxCancelBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.ticketsInboxKeep),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.ticketsInboxCancelRequest),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _isBusy = true);
    final res = await ref.read(approvalsProvider.notifier).cancel(a.id);
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (res.success) {
      await _refresh();
    } else {
      _toast(res.message ?? context.l10n.ticketsInboxCancelFailed, error: true);
    }
  }

  Future<String?> _promptText(
    String title,
    String hint,
    String okLabel, {
    bool required = false,
  }) async {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (required && v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.danger600 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final approvals = ref.watch(approvalsProvider);
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.ticketsInboxTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary600,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary600,
          tabs: [
            Tab(text: context.l10n.ticketsInboxTabMine),
            Tab(text: context.l10n.ticketsInboxTabAll),
          ],
        ),
      ),
      body: Column(
        children: [
          _stateFilter(),
          Expanded(child: _body(approvals)),
        ],
      ),
    );
  }

  Widget _stateFilter() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final s in const [
              'pending',
              'approved',
              'rejected',
              'cancelled',
              'all',
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(_stateLabel(s)),
                  selected: _state == s,
                  onSelected: (_) {
                    setState(() => _state = s);
                    _refresh();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _stateLabel(String s) => s == 'all'
      ? context.l10n.ticketsInboxStateAll
      : ApprovalState.fromString(s).label;

  Widget _body(List<Approval> approvals) {
    if (approvals.isEmpty) {
      return EmptyState(
        icon: LucideIcons.shieldCheck,
        title: context.l10n.ticketsInboxEmptyTitle,
        description: _state == 'pending' && _mineTab
            ? context.l10n.ticketsInboxEmptyMine
            : context.l10n.ticketsInboxEmptyFiltered,
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
        itemCount: approvals.length,
        itemBuilder: (_, i) => _ApprovalTile(
          approval: approvals[i],
          isBusy: _isBusy,
          onTapCase: () =>
              context.push('/tickets/${approvals[i].caseSummary?.id}'),
          onApprove: () => _approve(approvals[i]),
          onReject: () => _reject(approvals[i]),
          onCancel: () => _cancel(approvals[i]),
        ),
      ),
    );
  }
}

class _ApprovalTile extends StatelessWidget {
  final Approval approval;
  final bool isBusy;
  final VoidCallback onTapCase;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCancel;

  const _ApprovalTile({
    required this.approval,
    required this.isBusy,
    required this.onTapCase,
    required this.onApprove,
    required this.onReject,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final c = approval.caseSummary;
    final r = approval.ruleSummary;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppLayout.borderRadiusLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: c == null ? null : onTapCase,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c?.name ?? context.l10n.ticketsInboxTicketFallback,
                        style: AppTypography.label.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (r != null)
                        Text(
                          context.l10n.ticketsInboxRule(r.name),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              StatusBadge(
                label: approval.state.label,
                color: approval.state.color,
              ),
            ],
          ),
          if (approval.note != null && approval.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(approval.note!, style: AppTypography.body),
          ],
          if (approval.reason != null && approval.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.danger50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                context.l10n.ticketsInboxRejection(approval.reason!),
                style: AppTypography.caption.copyWith(
                  color: AppColors.danger700,
                ),
              ),
            ),
          ],
          if (approval.requestedBy != null || approval.approver != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              children: [
                if (approval.requestedBy != null)
                  Text(
                    context.l10n.ticketsInboxRequestedBy(
                      approval.requestedBy!.email,
                    ),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                if (approval.approver != null)
                  Text(
                    context.l10n.ticketsInboxApprover(approval.approver!.email),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ],
          // Each row's actions follow the server's facts about it, not the
          // tab: `can_act` (in the approver pool, not the requester) for
          // Approve and Reject, `can_cancel` (the requester, or an org admin
          // on anyone's) for Withdraw. "Mine" never lists your own requests,
          // so a requester withdraws from "All", as on the web queue.
          if (approval.isPending && approval.canAct) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isBusy ? null : onApprove,
                    icon: const Icon(LucideIcons.check, size: 16),
                    label: Text(context.l10n.ticketsInboxApprove),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success600,
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : onReject,
                    icon: const Icon(LucideIcons.x, size: 16),
                    label: Text(context.l10n.ticketsInboxReject),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger600,
                      minimumSize: const Size(0, 44),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (approval.isPending && approval.canCancel) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onCancel,
                icon: const Icon(LucideIcons.circleMinus, size: 16),
                label: Text(context.l10n.ticketsInboxWithdraw),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
