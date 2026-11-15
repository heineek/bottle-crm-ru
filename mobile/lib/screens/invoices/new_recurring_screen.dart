import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/deal.dart' show Currency;
import '../../data/models/lookup_models.dart';
import '../../l10n/l10n.dart';
import '../../data/models/recurring_invoice.dart';
import '../../providers/auth_provider.dart';
import '../../providers/invoice_extras_provider.dart';
import '../../providers/lookup_provider.dart';
import '../../services/app_language.dart';
import '../../services/org_date.dart';
import 'document_adjustments.dart';
import 'invoice_format.dart';
import 'line_item_sheet.dart';

/// Set up a billing schedule.
///
/// The same shape as the new-invoice form, since
/// `RecurringInvoiceCreateSerializer` takes the same required pair
/// (`account_id`, `contact_id`), the same contact-belongs-to-account rule and
/// the same nested `line_items`. It reuses the invoice form's line list
/// ([LineItemsSection]) and adjustments card rather than growing second
/// copies, so a schedule's lines and discounts are sent exactly as an
/// invoice's are and every invoice it raises carries them.
///
/// **One field the web exposes is deliberately not here.**
/// `next_generation_date` and `start_date` are separate columns and the web
/// offers both, which lets a schedule start in March while first billing
/// today: `check_recurring_invoices` only ever reads
/// `next_generation_date` and never consults `start_date`. This form asks when
/// billing starts once and sends that date as both, so the two cannot
/// disagree. Editing them apart stays possible on the web.
class NewRecurringScreen extends ConsumerStatefulWidget {
  const NewRecurringScreen({super.key});

  @override
  ConsumerState<NewRecurringScreen> createState() => _NewRecurringScreenState();
}

class _NewRecurringScreenState extends ConsumerState<NewRecurringScreen> {
  final _title = TextEditingController();
  final _customDays = TextEditingController();

  String? _accountId;
  String? _contactId;
  late String _currency;
  String _frequency = 'MONTHLY';
  String _paymentTerms = 'NET_30';
  DateTime _startDate = orgToday();
  DateTime? _endDate;
  bool _autoSend = false;

  final List<LineItemDraft> _items = [];
  DocumentAdjustments _adjustments = const DocumentAdjustments();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currency =
        ref.read(selectedOrgProvider)?.defaultCurrency ?? Currency.usd.value;
  }

  @override
  void dispose() {
    _title.dispose();
    _customDays.dispose();
    super.dispose();
  }

  String get _symbol => Currency.fromString(_currency).symbol;

  List<LineItemDraft> get _usableItems =>
      _items.where((i) => i.name.trim().isNotEmpty && i.quantity > 0).toList();

  double get _subtotal =>
      _usableItems.fold(0, (sum, item) => sum + item.netAmount);

  /// The interval, or null when it is missing or not a positive number.
  int? get _customDaysValue {
    final parsed = int.tryParse(_customDays.text.trim());
    return (parsed == null || parsed < 1) ? null : parsed;
  }

  /// Lines are optional on a schedule, as on the web and in the API, except
  /// one that emails each invoice: the server refuses that with no lines,
  /// since it would mail the client a blank invoice.
  bool get _needsLine => _autoSend && _usableItems.isEmpty;

  bool get _ready =>
      _accountId != null &&
      _contactId != null &&
      _title.text.trim().isNotEmpty &&
      !_needsLine &&
      _adjustments.isValidFor(_subtotal) &&
      // A CUSTOM cadence with no interval is refused by the serializer, and
      // before that guard existed it was accepted and silently billed monthly.
      cadenceIsComplete(_frequency, _customDaysValue) &&
      !_saving;

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsLookupProvider);
    final contacts = ref.watch(contactsLookupProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.invoicesRecurringNewTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (_error != null)
                  Container(
                    width: double.infinity,
                    color: AppColors.danger50,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.danger700,
                      ),
                    ),
                  ),
                _who(accounts, contacts),
                _cadence(),
                _card(context.l10n.invoicesRecurringLinesCard, [
                  LineItemsSection(
                    items: _items,
                    symbol: _symbol,
                    emptyHint: context.l10n.invoicesRecurringLinesEmpty,
                    onChanged: (items) => setState(() {
                      _items
                        ..clear()
                        ..addAll(items);
                    }),
                  ),
                ]),
                _card(context.l10n.invoicesFormAdjustments, [
                  AdjustmentsSection(
                    value: _adjustments,
                    subtotal: _subtotal,
                    symbol: _symbol,
                    onChanged: (value) => setState(() => _adjustments = value),
                  ),
                ]),
              ],
            ),
          ),
          _totalBar(),
        ],
      ),
    );
  }

  Widget _who(
    AsyncValue<List<AccountLookup>> accounts,
    AsyncValue<List<ContactLookup>> contacts,
  ) {
    final all = contacts.value ?? const <ContactLookup>[];
    final options = _accountId == null
        ? const <ContactLookup>[]
        : all.where((c) => c.billableFor(_accountId)).toList();

    return _card(context.l10n.invoicesRecurringWhoCard, [
      DropdownButtonFormField<String>(
        initialValue: _accountId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.l10n.invoicesDetailAccount,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final a in accounts.value ?? const <AccountLookup>[])
            DropdownMenuItem(value: a.id, child: Text(a.name)),
        ],
        onChanged: (value) => setState(() {
          _accountId = value;
          if (_contactId != null) {
            final kept = all.where((c) => c.id == _contactId).firstOrNull;
            if (kept == null || !kept.billableFor(value)) _contactId = null;
          }
        }),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _contactId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.l10n.invoicesDetailBillTo,
          border: const OutlineInputBorder(),
          helperText: _accountId == null
              ? context.l10n.invoicesFormPickAccountFirst
              : null,
        ),
        items: [
          for (final c in options)
            DropdownMenuItem(
              value: c.id,
              child: Text(
                c.accountName == null
                    ? c.fullName
                    : '${c.fullName} · ${c.accountName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _accountId == null
            ? null
            : (value) => setState(() => _contactId = value),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: context.l10n.invoicesFormWhatFor,
          hintText: context.l10n.invoicesRecurringTitleHint,
          border: const OutlineInputBorder(),
        ),
      ),
    ]);
  }

  Widget _cadence() {
    return _card(context.l10n.invoicesRecurringHowOften, [
      DropdownButtonFormField<String>(
        initialValue: _frequency,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.l10n.invoicesRecurringFrequency,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final entry in recurringFrequencies.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) => setState(() => _frequency = value ?? _frequency),
      ),
      if (_frequency == 'CUSTOM') ...[
        const SizedBox(height: 12),
        TextField(
          controller: _customDays,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: context.l10n.invoicesRecurringCustomDays,
            border: const OutlineInputBorder(),
            // Not merely a hint. Without an interval the server used to accept
            // the schedule and bill monthly; it now refuses, and either way
            // this is the field that makes CUSTOM mean anything.
            errorText: _customDays.text.trim().isEmpty
                ? null
                : _customDaysValue == null
                ? context.l10n.invoicesRecurringCustomDaysError
                : null,
          ),
        ),
      ],
      const SizedBox(height: 12),
      _dateField(
        label: context.l10n.invoicesRecurringFirstOn,
        value: _startDate,
        onPick: (d) => setState(() => _startDate = d),
      ),
      const SizedBox(height: 12),
      _dateField(
        label: context.l10n.invoicesRecurringStopAfter,
        value: _endDate,
        onPick: (d) => setState(() => _endDate = d),
        onClear: _endDate == null
            ? null
            : () => setState(() => _endDate = null),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _paymentTerms,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.l10n.invoicesRecurringPaymentTerms,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final entry in paymentTermLabels().entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (value) =>
            setState(() => _paymentTerms = value ?? _paymentTerms),
      ),
      // Wrapped in its own Material: the card around it is a ColoredBox, and
      // a ListTile paints its ink splash on the nearest Material ancestor, so
      // without this Flutter asserts that the splash would be invisible.
      Material(
        color: AppColors.surface,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _autoSend,
          onChanged: (v) => setState(() => _autoSend = v),
          title: Text(context.l10n.invoicesRecurringAutoSend),
          subtitle: Text(context.l10n.invoicesRecurringAutoSendHint),
        ),
      ),
      if (_needsLine)
        Text(
          context.l10n.invoicesRecurringNeedsLine,
          style: AppTypography.caption.copyWith(color: AppColors.danger600),
        ),
    ]);
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onPick,
    VoidCallback? onClear,
  }) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? orgToday(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  icon: const Icon(LucideIcons.x, size: 16),
                  tooltip: context.l10n.invoicesClearTooltip,
                  onPressed: onClear,
                ),
        ),
        child: Text(
          value == null
              ? context.l10n.invoicesFormPickDate
              : localDateFormat('d MMM yyyy', 'yMMMd').format(value),
          style: AppTypography.body.copyWith(
            color: value == null
                ? AppColors.textSecondary
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _totalBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.gray200)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    money(_adjustments.total(_subtotal), _symbol),
                    style: AppTypography.h3.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _frequency == 'CUSTOM' && _customDaysValue != null
                        ? context.l10n.invoicesRecurringTotalCustom(
                            _customDaysValue!,
                          )
                        : context.l10n.invoicesRecurringTotalCaption(
                            (recurringFrequencies[_frequency] ?? '')
                                .toLowerCase(),
                          ),
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
            // Flexible: a longer translation ellipsizes before it pushes
            // the total off screen.
            Flexible(
              child: SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: _ready ? _submit : null,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          context.l10n.invoicesRecurringStart,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    final start = DateFormat('yyyy-MM-dd').format(_startDate);
    final payload = <String, dynamic>{
      'title': _title.text.trim(),
      'account_id': _accountId,
      'contact_id': _contactId,
      'frequency': _frequency,
      'start_date': start,
      // Sent as the same date on purpose. The generator reads only this field
      // and never `start_date`, so letting the two differ would let a schedule
      // that "starts in March" bill today.
      'next_generation_date': start,
      'payment_terms': _paymentTerms,
      'currency': _currency,
      'auto_send': _autoSend,
      'line_items': [
        for (var i = 0; i < _usableItems.length; i++)
          _usableItems[i].toPayload(order: i),
      ],
      if (_frequency == 'CUSTOM') 'custom_days': _customDaysValue,
      if (_endDate != null)
        'end_date': DateFormat('yyyy-MM-dd').format(_endDate!),
      ..._adjustments.toPayload(),
    };

    final error = await ref
        .read(recurringProvider.notifier)
        .createSchedule(payload);
    if (!mounted) return;
    setState(() => _saving = false);

    if (error != null) {
      setState(() => _error = error);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.invoicesRecurringCreated)),
    );
    context.pop();
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
