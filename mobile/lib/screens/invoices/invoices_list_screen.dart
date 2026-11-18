import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/api_config.dart';
import '../../core/theme/theme.dart';
import '../../data/models/deal.dart' show Currency;
import '../../data/models/invoice.dart';
import '../../l10n/l10n.dart';
import '../../providers/invoices_provider.dart';
import '../../providers/saved_views_provider.dart';
import '../../routes/app_router.dart';
import '../../services/app_language.dart';
import '../../widgets/common/badge.dart';
import '../../widgets/common/export_csv_button.dart';
import '../../widgets/common/saved_views_button.dart';
import 'invoice_format.dart';

/// The invoices list.
///
/// The web page is a seven-column table with the money right-aligned. At 390px
/// that is either a horizontal scroll or seven unreadable slivers, so each
/// invoice is a card: number and account on top, then the amount, the status
/// and how late it is on one wrapping line.
class InvoicesListScreen extends ConsumerStatefulWidget {
  const InvoicesListScreen({super.key});

  @override
  ConsumerState<InvoicesListScreen> createState() => _InvoicesListScreenState();
}

class _InvoicesListScreenState extends ConsumerState<InvoicesListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  /// The statuses worth a chip. All eight would not fit and most are rare;
  /// these are the four a person filters by, and "All" clears back.
  static const _filters = <InvoiceStatus?>[
    null,
    InvoiceStatus.draft,
    InvoiceStatus.sent,
    InvoiceStatus.overdue,
    InvoiceStatus.paid,
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(invoicesProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(invoicesProvider.notifier).search(value);
    });
  }

  /// The search box and the status chips. The list's fixed order (`sort`)
  /// is not a filter and is not saved.
  static const _savedViewKeys = {'search', 'status'};

  void _applySavedView(Map<String, List<String>> filters) {
    final search = filters['search']?.first ?? '';
    _debounce?.cancel();
    _searchController.text = search;
    ref
        .read(invoicesProvider.notifier)
        .applyView(
          search: search,
          status: InvoiceStatus.fromString(filters['status']?.first),
        );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(invoicesProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.invoicesListTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          SavedViewsButton(
            list: SavedViewList.invoices,
            keys: _savedViewKeys,
            currentQuery: () async =>
                ref.read(invoicesProvider.notifier).filterQuery,
            onApply: _applySavedView,
          ),
          ExportCsvButton(
            endpoint: ApiConfig.invoicesExport,
            filePrefix: 'invoices',
            query: () async => ref.read(invoicesProvider.notifier).filterQuery,
          ),
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: context.l10n.invoicesListNewTooltip,
            onPressed: () => context.push(AppRoutes.invoiceNew),
          ),
          // The web reaches its sibling pages through a tab strip. Six tabs do
          // not fit at 390px, so they live behind one menu instead.
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical),
            tooltip: context.l10n.invoicesListMoreTooltip,
            onSelected: (route) => context.push(route),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: AppRoutes.estimates,
                child: Text(context.l10n.invoicesMenuEstimates),
              ),
              PopupMenuItem(
                value: AppRoutes.recurring,
                child: Text(context.l10n.invoicesMenuRecurring),
              ),
              PopupMenuItem(
                value: AppRoutes.products,
                child: Text(context.l10n.invoicesMenuProducts),
              ),
              PopupMenuItem(
                value: AppRoutes.invoiceTemplates,
                child: Text(context.l10n.invoicesMenuTemplates),
              ),
              PopupMenuItem(
                value: AppRoutes.invoiceReports,
                child: Text(context.l10n.invoicesMenuReports),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _searchBar(),
          _statusChips(async.value?.status),
          Expanded(child: _list(async)),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: context.l10n.invoicesListSearchHint,
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(LucideIcons.x, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(invoicesProvider.notifier).search('');
                    setState(() {});
                  },
                ),
        ),
      ),
    );
  }

  Widget _statusChips(InvoiceStatus? active) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final status in _filters) ...[
              _chip(
                status?.label ?? context.l10n.invoicesFilterAll,
                active == status,
                status,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, InvoiceStatus? status) {
    return GestureDetector(
      onTap: () => ref.read(invoicesProvider.notifier).filterByStatus(status),
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? AppColors.primary600 : AppColors.surface,
          border: Border.all(
            color: active ? AppColors.primary600 : AppColors.gray300,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _list(AsyncValue<InvoicesListData> async) {
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _errorState(),
      data: (data) {
        if (data.invoices.isEmpty) return _emptyState(data);
        return RefreshIndicator(
          onRefresh: () => ref.read(invoicesProvider.notifier).refresh(),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: data.invoices.length + (data.hasMore ? 2 : 1),
            itemBuilder: (context, index) {
              if (index == 0) return _summary(data);
              final row = index - 1;
              if (row >= data.invoices.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _InvoiceCard(
                invoice: data.invoices[row],
                onSend: () => _send(data.invoices[row]),
              );
            },
          ),
        );
      },
    );
  }

  /// The header figures.
  ///
  /// Deliberately not labelled as describing the filtered list: the API
  /// computes `totals` over everything the caller can see, whatever filter is
  /// active. Saying otherwise would be false while a chip is selected.
  Widget _summary(InvoicesListData data) {
    final totals = data.totals;
    // One line of figures per currency: the server never adds two currencies
    // together, and neither does this. An org with nothing visible still gets
    // its line of zeroes, bare, as before.
    final money = totals.money.isEmpty
        ? const {'': InvoiceMoneyTotals()}
        : totals.money;

    return Container(
      width: double.infinity,
      color: AppColors.surfaceDim,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final MapEntry(key: code, value: m) in money.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _stat(
                    context.l10n.invoicesStatOutstanding,
                    compactMoney(m.outstanding, _symbol(code, data)),
                  ),
                  if (m.overdue > 0)
                    _stat(
                      context.l10n.invoicesStatOverdue,
                      compactMoney(m.overdue, _symbol(code, data)),
                      tone: AppColors.danger600,
                    ),
                  _stat(
                    context.l10n.invoicesStatDraft,
                    compactMoney(m.draft, _symbol(code, data)),
                  ),
                ],
              ),
            ),
          if (money.length > 1) ...[
            const SizedBox(height: 4),
            Text(
              context.l10n.invoicesListCurrencyNote,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            data.invoices.length < totals.count
                ? context.l10n.invoicesListShownOf(
                    data.invoices.length,
                    totals.count,
                  )
                : context.l10n.invoicesListCount(totals.count),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// The symbol for a totals line. An empty [code] is a server that sent only
  /// plain figures, so the loaded rows are the only hint at the currency.
  String _symbol(String code, InvoicesListData data) {
    if (code.isNotEmpty) return Currency.symbolFor(code);
    return data.invoices.isEmpty ? '' : data.invoices.first.currencyInfo.symbol;
  }

  /// One figure. A single rich Text rather than a Row of two, because a Row
  /// inside a Wrap cannot shrink and overflows once the system font is scaled.
  Widget _stat(String label, String value, {Color? tone}) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: tone ?? AppColors.textPrimary,
            ),
          ),
          TextSpan(
            text: label.toLowerCase(),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send(Invoice invoice) async {
    final error = await ref.read(invoicesProvider.notifier).send(invoice.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? context.l10n.invoicesListSentSnack(invoice.invoiceNumber),
        ),
      ),
    );
  }

  Widget _emptyState(InvoicesListData data) {
    final String message;
    if (_searchController.text.isNotEmpty) {
      message = context.l10n.invoicesListEmptySearch;
    } else if (data.status != null) {
      message = context.l10n.invoicesListEmptyStatus(
        data.status!.label.toLowerCase(),
      );
    } else {
      message = context.l10n.invoicesListEmpty;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.receipt, size: 48, color: AppColors.gray300),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.alertCircle, size: 40, color: AppColors.danger500),
            const SizedBox(height: 12),
            Text(
              context.l10n.invoicesListLoadError,
              style: AppTypography.body.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ref.read(invoicesProvider.notifier).refresh(),
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, required this.onSend});

  final Invoice invoice;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final isLate = invoice.isLate;
    final age = ageLabel(invoice);

    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => context.push('${AppRoutes.invoices}/${invoice.id}'),
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.gray200)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoice.invoiceNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          invoice.accountName ??
                              (invoice.clientName.isNotEmpty
                                  ? invoice.clientName
                                  : context.l10n.invoicesNoAccount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    money(invoice.totalAmount, invoice.currencyInfo.symbol),
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Wrap, not Row: "Partially paid" beside "12d late" and a due
              // date overflows a 390px card once the system font is scaled up.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(
                    label: invoice.statusLabel,
                    color: invoice.statusColor,
                  ),
                  if (invoice.dueDate != null)
                    Text(
                      context.l10n.invoicesDueOn(
                        localDateFormat(
                          'd MMM',
                          'MMMd',
                        ).format(invoice.dueDate!),
                      ),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  if (age != null)
                    Text(
                      age,
                      style: AppTypography.caption.copyWith(
                        color: isLate
                            ? AppColors.danger600
                            : AppColors.textSecondary,
                        fontWeight: isLate ? FontWeight.w600 : null,
                      ),
                    ),
                ],
              ),
              if (invoice.canSend) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: onSend,
                    child: Text(
                      invoice.status == InvoiceStatus.overdue
                          ? context.l10n.invoicesSendReminder
                          : context.l10n.invoicesSend,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
