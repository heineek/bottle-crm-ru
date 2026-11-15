import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models/lookup_models.dart';
import '../../core/theme/theme.dart';
import '../../data/models/account.dart';
import '../../data/models/deal.dart' show Currency;
import '../../providers/accounts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/duplicates_provider.dart';
import '../../providers/org_modules_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/duplicates/duplicates_panel.dart';
import '../../widgets/objects/related_objects_section.dart';
import '../../l10n/l10n.dart';

/// One account: who they are, what they are worth, and what is open against
/// them.
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  Account? _account;
  bool _loading = true;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    ref.invalidate(
      recordDuplicatesProvider((DuplicateModule.accounts, widget.accountId)),
    );
    var notFound = false;
    final account = await ref
        .read(accountsProvider.notifier)
        .getAccount(widget.accountId, onNotFound: () => notFound = true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _account = account;
      // Only a 404 says "not found", and it covers both a deleted account
      // and one this user may not open. Offline or a 500 is "could not load".
      if (account == null) {
        _error = notFound
            ? context.l10n.accountsDetailNotFound
            : context.l10n.accountsFormLoadFailed;
      }
    });
  }

  /// The server's delete rule for this user (`can_delete` on the detail
  /// response), not a copy of it. The DELETE asks the same rule again.
  bool get _canDelete => _account?.canDelete ?? false;

  Future<void> _confirmDelete() async {
    final account = _account;
    if (account == null || _deleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.accountsDetailDeleteTitle),
        content: Text(context.l10n.accountsDetailDeleteBody(account.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.commonDelete,
              style: TextStyle(color: AppColors.danger600),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final failure = await ref
        .read(accountsProvider.notifier)
        .deleteAccount(account.id);
    if (!mounted) return;
    setState(() => _deleting = false);

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure), backgroundColor: AppColors.danger600),
      );
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(account?.name ?? context.l10n.accountsDetailTitleFallback),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.pop(),
        ),
        actions: [
          // Statements are admin-only on the server; a member would only be
          // told so.
          if (account != null &&
              ref.watch(isOrgAdminProvider) &&
              ref.watch(moduleOnProvider('invoices')))
            IconButton(
              icon: const Icon(LucideIcons.receiptText, size: 20),
              tooltip: context.l10n.accountsDetailStatementTooltip,
              onPressed: () =>
                  context.push('${AppRoutes.accounts}/${account.id}/statement'),
            ),
          if (account != null)
            IconButton(
              icon: const Icon(LucideIcons.edit3, size: 20),
              tooltip: context.l10n.accountsDetailEditTooltip,
              onPressed: () async {
                await context.push('${AppRoutes.accounts}/${account.id}/edit');
                if (mounted) _load();
              },
            ),
          if (_canDelete)
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 20),
              tooltip: context.l10n.accountsDetailDeleteTooltip,
              onPressed: _deleting ? null : _confirmDelete,
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final account = _account;
    if (account == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.alertCircle, size: 40, color: AppColors.danger500),
            const SizedBox(height: 12),
            Text(
              _error ?? context.l10n.accountsFormLoadFailed,
              textAlign: TextAlign.center,
              style: AppTypography.body,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 48),
        children: [
          DuplicatesPanel(
            module: DuplicateModule.accounts,
            recordId: account.id,
          ),
          _rollups(account),
          _details(account),
          _relationSection(
            context.l10n.accountsDetailContacts,
            LucideIcons.users,
            account.contacts,
          ),
          if (ref.watch(moduleOnProvider('deals')))
            _relationSection(
              context.l10n.accountsDetailDeals,
              LucideIcons.trendingUp,
              account.opportunities,
            ),
          if (ref.watch(moduleOnProvider('tickets')))
            _relationSection(
              context.l10n.accountsDetailTickets,
              LucideIcons.lifeBuoy,
              account.cases,
            ),
          if (ref.watch(moduleOnProvider('tasks')))
            _relationSection(
              context.l10n.accountsDetailTasks,
              LucideIcons.checkCheck,
              account.tasks,
            ),
          RelatedObjectsSection(to: 'account', recordId: account.id),
        ],
      ),
    );
  }

  /// Absent rollups and zero rollups are different things. The server sends
  /// null from any endpoint that did not run the annotation, and a panel of
  /// zeroes would be a claim this screen has not earned.
  Widget _rollups(Account account) {
    final rollups = account.rollups;
    if (rollups == null || rollups.isEmpty) return const SizedBox.shrink();
    final dealsOn = ref.watch(moduleOnProvider('deals'));
    final ticketsOn = ref.watch(moduleOnProvider('tickets'));
    if (!dealsOn && !ticketsOn) return const SizedBox.shrink();
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (dealsOn) ...[
            _metric(
              context.l10n.accountsDetailOpenPipeline,
              _perCurrency(account, rollups, (m) => m.openPipeline),
            ),
            _metric(
              context.l10n.accountsDetailWon,
              _perCurrency(account, rollups, (m) => m.wonAmount),
            ),
          ],
          if (ticketsOn)
            _metric(
              context.l10n.accountsDetailOpenTickets,
              '${rollups.openTickets ?? 0}',
            ),
        ],
      ),
    );
  }

  /// One amount per currency that has any, never a sum across currencies:
  /// there are no exchange rates. Nothing at all reads as zero in the
  /// account's own currency, as it always has.
  String _perCurrency(
    Account account,
    AccountRollups rollups,
    double Function(RollupMoney) amount,
  ) {
    String format(double value, String code) => NumberFormat.compactCurrency(
      symbol: code.isEmpty
          ? Currency.fromString(account.currency).symbol
          : Currency.symbolFor(code),
    ).format(value);
    final shown = [
      for (final m in rollups.money)
        if (amount(m) != 0) format(amount(m), m.currency),
    ];
    return shown.isEmpty ? format(0, '') : shown.join('\n');
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(Account account) {
    final l10n = context.l10n;
    final rows = <(String, String?)>[
      (l10n.accountsFormWebsite, account.website),
      (l10n.commonEmail, account.email),
      (l10n.commonPhone, account.phone),
      (
        l10n.accountsFormIndustry,
        account.industry == null ? null : industryLabel(account.industry),
      ),
      (
        l10n.accountsDetailEmployees,
        account.numberOfEmployees == null
            ? null
            : '${account.numberOfEmployees}',
      ),
      (l10n.accountsDetailAnnualRevenue, account.annualRevenue),
      (l10n.accountsFormAddress, _address(account)),
      (
        l10n.commonAssignedTo,
        account.assignedToNames.isEmpty
            ? null
            : account.assignedToNames.join(', '),
      ),
      (
        l10n.commonTags,
        account.tagNames.isEmpty ? null : account.tagNames.join(', '),
      ),
      (l10n.commonNotes, account.description),
    ].where((row) => row.$2 != null && row.$2!.trim().isNotEmpty).toList();

    if (rows.isEmpty) {
      return _card(
        child: Text(
          l10n.accountsDetailNoDetails,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      row.$1,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(child: Text(row.$2!, style: AppTypography.body)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _address(Account account) {
    final parts = [
      account.addressLine,
      account.city,
      account.state,
      account.postcode,
      account.countryDisplay ?? account.country,
    ].where((p) => p != null && p.trim().isNotEmpty).join(', ');
    return parts.isEmpty ? null : parts;
  }

  Widget _relationSection(
    String title,
    IconData icon,
    List<AccountRelation> rows,
  ) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                '$title (${rows.length})',
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body,
                    ),
                  ),
                  if (row.detail != null)
                    Text(
                      row.detail!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.gray200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
