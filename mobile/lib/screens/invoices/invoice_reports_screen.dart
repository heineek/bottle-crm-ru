import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/deal.dart' show Currency;
import '../../data/models/invoice_report.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/invoice_extras_provider.dart';
import 'invoice_format.dart';
import 'invoice_shell.dart';

/// Invoice reports: the money summary and the receivables ageing.
///
/// **Both endpoints are admin-only.** A non-admin gets a 403, and this screen
/// says so plainly instead of showing an empty report with a Retry button that
/// can never work.
///
/// Money is shown one currency at a time. There are no exchange rates, so the
/// server never adds two currencies together and neither does this screen: an
/// org that invoices in several gets a currency picker, the same choice the
/// web reports page makes, and every amount below it is in the picked one.
class InvoiceReportsScreen extends ConsumerStatefulWidget {
  const InvoiceReportsScreen({super.key});

  @override
  ConsumerState<InvoiceReportsScreen> createState() =>
      _InvoiceReportsScreenState();
}

class _InvoiceReportsScreenState extends ConsumerState<InvoiceReportsScreen> {
  String? _picked;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(invoiceReportsProvider);
    final orgCurrency = ref.watch(selectedOrgProvider)?.defaultCurrency;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.invoicesReportsTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (error is ReportsForbidden) {
            return InvoiceErrorState(
              message: context.l10n.invoicesReportsForbidden,
              detail: error.message,
              // No Retry: a 403 does not become a 200 by asking again.
            );
          }
          return InvoiceErrorState(
            message: context.l10n.invoicesReportsLoadError,
            onRetry: () => ref.invalidate(invoiceReportsProvider),
          );
        },
        data: (reports) {
          final d = reports.dashboard;
          final currencies = reports.currencies;
          // The picked currency, else the org's own, else the first invoiced in.
          final code = currencies.contains(_picked)
              ? _picked!
              : currencies.contains(orgCurrency)
              ? orgCurrency!
              : currencies.isEmpty
              ? ''
              : currencies.first;
          // An empty code is an org with no invoices, or an older server that
          // sends no breakdown: both are labelled in the org's own currency.
          // `symbolFor` names a currency the app does not list rather than
          // passing it off as dollars.
          final symbol = Currency.symbolFor(
            code.isEmpty ? (orgCurrency ?? 'USD') : code,
          );
          final m = d.money[code] ?? const DashboardMoney();
          final aging = reports.aging[code] ?? AgingReport.empty;
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(invoiceReportsProvider),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (currencies.length > 1)
                  Container(
                    color: AppColors.surface,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final c in currencies)
                          ChoiceChip(
                            label: Text(c),
                            selected: c == code,
                            onSelected: (_) => setState(() => _picked = c),
                          ),
                      ],
                    ),
                  ),
                _card(context.l10n.invoicesReportsMoney, [
                  InvoiceFactRow(
                    label: context.l10n.invoicesReportsInvoicedAllTime,
                    value: money(m.totalInvoiced, symbol),
                  ),
                  InvoiceFactRow(
                    label: context.l10n.invoicesReportsPaid,
                    value: money(m.totalPaid, symbol),
                  ),
                  InvoiceFactRow(
                    label: context.l10n.invoicesReportsStillOwed,
                    value: money(m.totalDue, symbol),
                  ),
                  InvoiceFactRow(
                    label: context.l10n.invoicesReportsInvoicesRaised,
                    value: '${d.invoiceCount}',
                  ),
                  // Hidden rather than shown as zero: an org that has never
                  // been paid has no average, and "0 days to pay" reads as
                  // instant payment.
                  if (d.averageDaysToPay > 0)
                    InvoiceFactRow(
                      label: context.l10n.invoicesReportsAverageDays,
                      value: '${d.averageDaysToPay}',
                    ),
                ]),
                if (m.overdueCount > 0)
                  _card(context.l10n.invoicesReportsOverdue, [
                    InvoiceFactRow(
                      label: context.l10n.invoicesReportsPastDue,
                      value: '${m.overdueCount}',
                    ),
                    InvoiceFactRow(
                      label: context.l10n.invoicesReportsAmount,
                      value: money(m.overdueAmount, symbol),
                    ),
                  ], tone: AppColors.danger600),
                _card(context.l10n.invoicesReportsLast30, [
                  InvoiceFactRow(
                    label: context.l10n.invoicesReportsCollected,
                    value: money(m.revenue30d, symbol),
                  ),
                  InvoiceFactRow(
                    label: context.l10n.invoicesReportsInvoiced,
                    value: money(m.invoiced30d, symbol),
                  ),
                ]),
                _card(context.l10n.invoicesReportsAgeing, [
                  for (final bucket in aging.buckets)
                    InvoiceFactRow(
                      label: '${bucket.label} (${bucket.count})',
                      value: money(bucket.amount, symbol),
                    ),
                  const Divider(height: 18),
                  InvoiceFactRow(
                    label: context.l10n.invoicesReportsOutstandingTotal,
                    value: money(aging.total, symbol),
                  ),
                ]),
                if (d.estimatesPending +
                        d.estimatesAccepted +
                        d.estimatesDeclined >
                    0)
                  _card(context.l10n.invoicesReportsEstimates, [
                    InvoiceFactRow(
                      label: context.l10n.invoicesReportsWaiting,
                      value: '${d.estimatesPending}',
                    ),
                    InvoiceFactRow(
                      label: context.l10n.invoicesReportsAccepted,
                      value: '${d.estimatesAccepted}',
                    ),
                    InvoiceFactRow(
                      label: context.l10n.invoicesReportsDeclined,
                      value: '${d.estimatesDeclined}',
                    ),
                  ]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.info,
                        size: 14,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          currencies.length > 1
                              ? context.l10n.invoicesReportsScopeMulti
                              : context.l10n.invoicesReportsScope,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _card(String title, List<Widget> rows, {Color? tone}) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.caption.copyWith(
              color: tone ?? AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }
}
