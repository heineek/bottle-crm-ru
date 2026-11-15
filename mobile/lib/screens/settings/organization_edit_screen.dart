import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/models/org_locales.dart';
import '../../l10n/l10n.dart';
import '../../services/app_language.dart';
import '../../core/theme/theme.dart';
import '../../data/models/deal.dart' show Currency;
import '../../data/models/org_settings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/org_modules_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/org_date.dart';

/// Editing the organization.
///
/// **Admin-only.** A member sees the notice rather than the form, but that is
/// the courtesy, not the control: `PATCH /api/org/settings/` refuses anyone
/// whose role is not ADMIN, whatever reaches it.
///
/// What this form owns is the org's own settings: the company profile printed
/// on documents, the locale defaults, invoice numbering (#802), and the two
/// org-wide switches. What it
/// deliberately does not own is the org API key (a credential, rotated through
/// its own action) and `is_active`, the org kill switch. Neither is a field
/// here and the server would not accept them if they were.
class OrganizationEditScreen extends ConsumerWidget {
  const OrganizationEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isOrgAdminProvider);
    final async = ref.watch(orgSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsOrgEditTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: !isAdmin
          ? const _MemberNotice()
          : async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(context.l10n.settingsOrgLoadFailed),
                ),
              ),
              data: (org) => _Form(org: org),
            ),
    );
  }
}

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
              context.l10n.settingsOrgEditAdminsOnlyTitle,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsOrgEditAdminsOnlyBody,
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

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.org});

  final OrgSettings org;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final Map<String, TextEditingController> _text;
  late String _country;
  late String _defaultCountry;
  late String _currency;
  late String _timezone;
  late String _defaultLanguage;
  late String _datePart;
  late bool _csat;
  late bool _cascade;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final org = widget.org;
    _text = {
      'company_name': TextEditingController(text: org.companyName),
      'name': TextEditingController(text: org.name),
      'tax_id': TextEditingController(text: org.taxId),
      'phone': TextEditingController(text: org.phone),
      'email': TextEditingController(text: org.email),
      'website': TextEditingController(text: org.website),
      'address_line': TextEditingController(text: org.addressLine),
      'city': TextEditingController(text: org.city),
      'state': TextEditingController(text: org.state),
      'postcode': TextEditingController(text: org.postcode),
      'invoice_number_prefix': TextEditingController(
        text: org.invoiceNumberPrefix,
      ),
      'estimate_number_prefix': TextEditingController(
        text: org.estimateNumberPrefix,
      ),
      'number_padding': TextEditingController(text: '${org.numberPadding}'),
      'invoice_number_start': TextEditingController(
        text: '${org.invoiceNumberStart}',
      ),
    };
    _country = org.country;
    _defaultCountry = org.defaultCountry;
    _currency = org.defaultCurrency;
    _timezone = org.timezone;
    _defaultLanguage = org.defaultLanguage;
    _datePart = org.numberDatePart;
    _csat = org.csatEnabled;
    _cascade = org.autoCloseChildren;
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _value(String key) => _text[key]!.text;

  Future<void> _save() async {
    // Hidden numbering fields hold what is stored, so a check on them would
    // block the save with nothing on screen to fix.
    final problem =
        orgSettingsProblem(
          email: _value('email'),
          website: _value('website'),
        ) ??
        (ref.read(moduleOnProvider('invoices'))
            ? numberingProblem(
                invoicePrefix: _value('invoice_number_prefix'),
                estimatePrefix: _value('estimate_number_prefix'),
                datePart: _datePart,
                padding: _value('number_padding'),
                start: _value('invoice_number_start'),
              )
            : null);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });

    final error = await ref
        .read(orgSettingsProvider.notifier)
        .save(
          orgSettingsPayload(
            name: _value('name'),
            companyName: _value('company_name'),
            addressLine: _value('address_line'),
            city: _value('city'),
            state: _value('state'),
            postcode: _value('postcode'),
            country: _country,
            phone: _value('phone'),
            email: _value('email'),
            website: _value('website'),
            taxId: _value('tax_id'),
            defaultCurrency: _currency,
            defaultCountry: _defaultCountry,
            timezone: _timezone,
            defaultLanguage: _defaultLanguage,
            csatEnabled: _csat,
            autoCloseChildren: _cascade,
            invoiceNumberPrefix: _value('invoice_number_prefix'),
            estimateNumberPrefix: _value('estimate_number_prefix'),
            numberDatePart: _datePart,
            numberPadding: int.parse(_value('number_padding').trim()),
            // Checked above when undated; sent as 1 when dated.
            invoiceNumberStart:
                int.tryParse(_value('invoice_number_start').trim()) ?? 1,
          ),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.settingsOrgEditSaved)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(orgTimezonesProvider);
    final countries =
        ref.watch(orgLocalesProvider).value?.countries ??
        OrgLocales.fallback.countries;
    final invoicesOn = ref.watch(moduleOnProvider('invoices'));
    final ticketsOn = ref.watch(moduleOnProvider('tickets'));
    final currencies = [
      for (final currency in Currency.values)
        (value: currency.value, label: '${currency.label} ${currency.symbol}'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        if (invoicesOn) ...[
          Text(
            context.l10n.settingsOrgEditPrintedHint,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
        ],
        _field(
          'company_name',
          context.l10n.settingsOrgLegalName,
          maxLength: 255,
        ),
        _field('name', context.l10n.settingsOrgEditTradingName, maxLength: 100),
        _field('tax_id', context.l10n.settingsOrgTaxId, maxLength: 50),
        _field(
          'phone',
          context.l10n.commonPhone,
          maxLength: 25,
          keyboard: TextInputType.phone,
        ),
        _field(
          'email',
          context.l10n.commonEmail,
          keyboard: TextInputType.emailAddress,
        ),
        _field(
          'website',
          context.l10n.settingsOrgWebsite,
          keyboard: TextInputType.url,
        ),
        _field('address_line', context.l10n.settingsOrgAddress, maxLength: 255),
        _field('city', context.l10n.settingsOrgEditCity, maxLength: 100),
        _field('state', context.l10n.settingsOrgEditState, maxLength: 100),
        _field('postcode', context.l10n.settingsOrgEditPostcode, maxLength: 20),
        _picker(
          label: context.l10n.settingsOrgCountry,
          value: _country,
          // "Not recorded" is a real choice: the column is blank-able and an
          // org that has not said where it is should not be made to guess.
          options: [
            (value: '', label: context.l10n.settingsOrgNotRecorded),
            ...withCurrent(countries, _country),
          ],
          onChanged: (v) => setState(() => _country = v),
        ),
        _SectionLabel(context.l10n.settingsOrgSectionDefaults),
        _picker(
          label: context.l10n.settingsOrgCurrency,
          value: _currency,
          helper: invoicesOn
              ? context.l10n.settingsOrgCurrencyHintInvoices
              : context.l10n.settingsOrgCurrencyHint,
          options: withCurrent(currencies, _currency),
          onChanged: (v) => setState(() => _currency = v),
        ),
        _picker(
          label: context.l10n.settingsOrgEditCountryDefault,
          value: _defaultCountry,
          helper: context.l10n.settingsOrgEditCountryDefaultHint,
          options: [
            (value: '', label: context.l10n.settingsOrgEditNotSet),
            ...withCurrent(countries, _defaultCountry),
          ],
          onChanged: (v) => setState(() => _defaultCountry = v),
        ),
        _picker(
          label: context.l10n.settingsOrgTimeZone,
          value: _timezone,
          helper: context.l10n.settingsOrgEditTimeZoneHint,
          // From the API, not the device: the two vocabularies disagree on
          // aliases, and a picker missing the stored zone would move the org.
          options: withCurrent([
            for (final zone in zones.value ?? const <TimezoneOption>[])
              (value: zone.name, label: zone.label),
          ], _timezone),
          onChanged: (v) => setState(() => _timezone = v),
        ),
        _picker(
          label: context.l10n.orgDefaultLanguageLabel,
          value: _defaultLanguage,
          helper: context.l10n.orgDefaultLanguageHint,
          options: withCurrent([
            for (final code in supportedLanguages)
              (
                value: code,
                label: lookupAppLocalizations(Locale(code)).languageName,
              ),
          ], _defaultLanguage),
          onChanged: (v) => setState(() => _defaultLanguage = v),
        ),
        if (invoicesOn) ...[
          _SectionLabel(context.l10n.settingsOrgSectionInvoiceNumbers),
          Text(
            context.l10n.settingsOrgEditNumbersHint,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          _field(
            'invoice_number_prefix',
            context.l10n.settingsOrgEditInvoicePrefix,
            maxLength: 20,
            capitalization: TextCapitalization.characters,
          ),
          _field(
            'estimate_number_prefix',
            context.l10n.settingsOrgEditEstimatePrefix,
            maxLength: 20,
            capitalization: TextCapitalization.characters,
          ),
          _picker(
            label: context.l10n.settingsOrgEditDatePart,
            value: _datePart,
            options: withCurrent(numberDatePartOptions, _datePart),
            onChanged: (v) => setState(() => _datePart = v),
          ),
          _field(
            'number_padding',
            context.l10n.settingsOrgEditPadding,
            maxLength: 2,
            digits: true,
          ),
          // A dated count restarts each period, so the start only exists for
          // undated numbers; the payload sends 1 otherwise.
          if (_datePart == 'NONE')
            _field(
              'invoice_number_start',
              context.l10n.settingsOrgEditStart,
              maxLength: 9,
              digits: true,
              helper: context.l10n.settingsOrgEditStartHint,
            ),
          ListenableBuilder(
            listenable: Listenable.merge([
              _text['invoice_number_prefix'],
              _text['estimate_number_prefix'],
              _text['number_padding'],
              _text['invoice_number_start'],
            ]),
            builder: (context, _) {
              final today = orgToday();
              final padding =
                  int.tryParse(_value('number_padding').trim()) ?? 1;
              String example(String prefix, {int start = 1}) => exampleNumber(
                prefix: _value(prefix).trim(),
                datePart: _datePart,
                padding: padding,
                start: start,
                today: today,
              );
              final start =
                  int.tryParse(_value('invoice_number_start').trim()) ?? 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  context.l10n.settingsOrgEditExample(
                    example('invoice_number_prefix', start: start),
                    example('estimate_number_prefix'),
                  ),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              );
            },
          ),
        ],
        if (ticketsOn) ...[
          _SectionLabel(context.l10n.settingsOrgSectionBehaviour),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _csat,
            onChanged: (v) => setState(() => _csat = v),
            title: Text(context.l10n.settingsOrgCsat),
            subtitle: Text(
              csatExplanation(_csat),
              style: AppTypography.caption.copyWith(
                color: _csat ? AppColors.textSecondary : AppColors.warning600,
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _cascade,
            onChanged: (v) => setState(() => _cascade = v),
            title: Text(context.l10n.settingsOrgCascade),
            subtitle: Text(
              '${cascadeDefaultExplanation(_cascade)} $cascadeWebGapNote',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: AppTypography.caption.copyWith(color: AppColors.danger600),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(context.l10n.settingsOrgEditSave),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonCancel),
          ),
        ),
      ],
    );
  }

  Widget _field(
    String key,
    String label, {
    int? maxLength,
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    bool digits = false,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _text[key],
        maxLength: maxLength,
        keyboardType: digits ? TextInputType.number : keyboard,
        textCapitalization: capitalization,
        inputFormatters: digits
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          counterText: '',
        ),
      ),
    );
  }

  Widget _picker({
    required String label,
    required String value,
    required List<PickerOption> options,
    required ValueChanged<String> onChanged,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: options.any((o) => o.value == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option.value, child: Text(option.label)),
        ],
        onChanged: (v) => onChanged(v ?? value),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
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
