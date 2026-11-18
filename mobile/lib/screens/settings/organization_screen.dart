import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/l10n.dart';
import '../../services/app_language.dart';
import '../../core/theme/theme.dart';
import '../../data/models/org_settings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../providers/org_modules_provider.dart';
import '../../providers/settings_provider.dart';
import '../../routes/app_router.dart';
import '../../services/org_date.dart';

/// The organization itself, read view.
///
/// Most of this is the company profile, and the thing worth saying about it is
/// where it ends up: these fields are printed on every invoice and estimate a
/// customer receives, so a wrong tax ID is a wrong document rather than a wrong
/// preference.
///
/// **The org API key is not here, in any form.** It authenticates as the org's
/// first admin, so the API never serializes it onto this payload. Rotating it
/// belongs behind its own audited action.
///
/// The read is open to any member: the company profile is not a secret, and
/// members legitimately see their org's address and currency. Editing is
/// admin-only, enforced server-side; hiding the button is UX. Industry apps
/// and sample data live on the Apps screen.
///
/// Where the server offers billing, the plan's name shows under the header,
/// read-only for everyone: the phone never offers to buy or manage a plan.
class OrganizationScreen extends ConsumerWidget {
  const OrganizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isOrgAdminProvider);
    final async = ref.watch(orgSettingsProvider);
    final invoicesOn = ref.watch(moduleOnProvider('invoices'));
    final ticketsOn = ref.watch(moduleOnProvider('tickets'));
    // While it reloads, the previous value may be another org's plan.
    final plan = ref.watch(orgPlanNameProvider);
    final planName = plan.isLoading || plan.hasError ? null : plan.value;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsOrgTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isAdmin && async.value != null)
            IconButton(
              icon: const Icon(LucideIcons.pencil),
              tooltip: context.l10n.settingsOrgEditDetails,
              onPressed: () => context.push(AppRoutes.settingsOrganizationEdit),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.read(orgSettingsProvider.notifier).refresh(),
        ),
        data: (org) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(orgPlanNameProvider);
            return ref.read(orgSettingsProvider.notifier).refresh();
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              _Header(org: org),
              if (planName != null)
                _Field(label: context.l10n.settingsOrgPlan, value: planName),
              _SectionHeader(context.l10n.settingsOrgSectionCustomersSee),
              _Field(
                label: context.l10n.settingsOrgLegalName,
                value: org.companyName,
              ),
              _Field(label: context.l10n.settingsOrgTradingAs, value: org.name),
              _Field(
                label: context.l10n.settingsOrgAddress,
                value: org.addressSummary,
              ),
              _Field(label: context.l10n.settingsOrgTaxId, value: org.taxId),
              _Field(label: context.l10n.commonEmail, value: org.email),
              _Field(label: context.l10n.commonPhone, value: org.phone),
              _Field(
                label: context.l10n.settingsOrgWebsite,
                value: org.website,
              ),
              if (invoicesOn) const _PrintedNote(),
              _SectionHeader(context.l10n.settingsOrgSectionDefaults),
              _Field(
                label: context.l10n.settingsOrgCurrency,
                value: '${org.defaultCurrency} ${org.currencySymbol}',
                detail: invoicesOn
                    ? context.l10n.settingsOrgCurrencyHintInvoices
                    : context.l10n.settingsOrgCurrencyHint,
              ),
              _Field(
                label: context.l10n.settingsOrgCountry,
                value: org.defaultCountry,
                detail: context.l10n.settingsOrgCountryHint,
              ),
              _Field(
                label: context.l10n.settingsOrgTimeZone,
                value: org.timezoneLabel,
                detail: context.l10n.settingsOrgTimeZoneHint,
              ),
              _Field(
                label: context.l10n.orgDefaultLanguageLabel,
                value: supportedLanguage(org.defaultLanguage) != null
                    ? lookupAppLocalizations(
                        Locale(org.defaultLanguage),
                      ).languageName
                    : org.defaultLanguage,
                detail: context.l10n.orgDefaultLanguageHint,
              ),
              if (invoicesOn) ...[
                _SectionHeader(context.l10n.settingsOrgSectionInvoiceNumbers),
                _Field(
                  label: context.l10n.settingsOrgNewInvoices,
                  value: exampleNumber(
                    prefix: org.invoiceNumberPrefix,
                    datePart: org.numberDatePart,
                    padding: org.numberPadding,
                    start: org.invoiceNumberStart,
                    today: orgToday(),
                  ),
                  detail: context.l10n.settingsOrgNumberingHint(
                    _datePartLabel(org.numberDatePart),
                  ),
                ),
                _Field(
                  label: context.l10n.settingsOrgNewEstimates,
                  value: exampleNumber(
                    prefix: org.estimateNumberPrefix,
                    datePart: org.numberDatePart,
                    padding: org.numberPadding,
                    today: orgToday(),
                  ),
                  detail: context.l10n.settingsOrgEstimatesHint,
                ),
              ],
              if (ticketsOn) ...[
                _SectionHeader(context.l10n.settingsOrgSectionBehaviour),
                _Field(
                  label: context.l10n.settingsOrgCsat,
                  value: org.csatEnabled
                      ? context.l10n.settingsOrgCsatSending
                      : context.l10n.settingsOrgCsatOff,
                  detail: csatExplanation(org.csatEnabled),
                ),
                _Field(
                  label: context.l10n.settingsOrgCascade,
                  value: org.autoCloseChildren
                      ? context.l10n.settingsOrgCascadeTicked
                      : context.l10n.settingsOrgCascadeUnticked,
                  detail:
                      '${cascadeDefaultExplanation(org.autoCloseChildren)} '
                      '$cascadeWebGapNote',
                ),
              ],
              const _ApiKeyNote(),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Year, count restarts each year" for a stored date part.
String _datePartLabel(String datePart) => numberDatePartOptions
    .firstWhere(
      (option) => option.value == datePart,
      orElse: () => (value: datePart, label: datePart),
    )
    .label;

class _Header extends StatelessWidget {
  const _Header({required this.org});

  final OrgSettings org;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            org.name.isEmpty ? context.l10n.settingsOrgUnnamed : org.name,
            style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text(
            context.l10n.settingsOrgMemberCount(org.memberCount),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final shown = value.trim();
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            shown.isEmpty ? context.l10n.settingsOrgNotRecorded : shown,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w500,
              color: shown.isEmpty
                  ? AppColors.textTertiary
                  : AppColors.textPrimary,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrintedNote extends StatelessWidget {
  const _PrintedNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Text(
        context.l10n.settingsOrgPrintedNote,
        style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

class _ApiKeyNote extends StatelessWidget {
  const _ApiKeyNote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.shieldAlert,
            size: 16,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.settingsOrgApiKeyNote,
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
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
              context.l10n.settingsOrgLoadFailed,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.settingsOrgTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
