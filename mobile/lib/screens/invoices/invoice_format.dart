import 'package:intl/intl.dart';

import '../../data/models/invoice.dart';
import '../../l10n/l10n.dart';
import '../../services/app_language.dart';

/// Formatting shared by the invoice list and the invoice detail.
///
/// Money on this app is per-record rather than per-org, so the symbol is always
/// passed in from the invoice being drawn. Nothing here reaches for an org
/// default: an invoice raised in euros stays in euros on a dollar org.

// Built per call: a top-level format would freeze the first language. The
// pattern is fixed so English stays "1,234.50"; the locale picks the grouping
// and decimal marks ("1.234,50" in German).
NumberFormat _money() => NumberFormat('#,##0.00', currentLanguage);
NumberFormat _wholeMoney() => NumberFormat('#,##0', currentLanguage);
bool get _symbolFirst => currentLanguage == baseLanguage;

/// A symbol-last message gains a stray space from an empty or padded symbol.
String _bare(String text) =>
    _symbolFirst ? text : text.replaceAll(RegExp(r'\s+'), ' ').trimRight();

String _oneDecimal(double value) => currentLanguage == baseLanguage
    ? value.toStringAsFixed(1)
    : NumberFormat('0.0', currentLanguage).format(value);

/// An exact amount, for anything a person might reconcile against a bank line.
/// The sign leads ("-$40.00"): a statement's payments and credit balances are
/// negative, and "$-40.00" reads as a typo. Outside English the symbol follows
/// the figure ("-40,00 ₽").
String money(double value, String symbol) {
  final sign = value < 0 ? '-' : '';
  final amount = _money().format(value.abs());
  if (_symbolFirst) return '$sign$symbol$amount';
  // `symbolFor` pads an unlisted code ("RUB ") for the symbol-first order.
  final mark = symbol.trim();
  return mark.isEmpty ? '$sign$amount' : '$sign$amount\u00a0$mark';
}

/// A shortened amount for header figures, where the magnitude is the point and
/// the cents are noise. An empty [symbol] is a deliberate caller choice, used
/// when the underlying sum spans more than one currency.
String compactMoney(double value, String symbol) {
  final absolute = value.abs();
  if (absolute >= 1000000) {
    return _bare(
      appL10n.invoicesCompactMillions(symbol, _oneDecimal(value / 1000000)),
    );
  }
  if (absolute >= 1000) {
    return _bare(
      appL10n.invoicesCompactThousands(symbol, _oneDecimal(value / 1000)),
    );
  }
  final amount = _wholeMoney().format(value);
  if (_symbolFirst || symbol.trim().isEmpty) return '$symbol$amount';
  return '$amount\u00a0${symbol.trim()}';
}

/// `invoices.models.PAYMENT_TERMS` without `CUSTOM`, which each form words
/// for itself.
Map<String, String> paymentTermLabels() => {
  'DUE_ON_RECEIPT': appL10n.invoicesTermsDueOnReceipt,
  'NET_15': appL10n.invoicesTermsNet(15),
  'NET_30': appL10n.invoicesTermsNet(30),
  'NET_45': appL10n.invoicesTermsNet(45),
  'NET_60': appL10n.invoicesTermsNet(60),
};

/// How late an invoice is, or how long is left.
///
/// Null on a settled or undated invoice rather than a placeholder, so the
/// caller can leave the slot out entirely. Once an invoice is paid or
/// cancelled its due date stops meaning anything, and "4d late" against a paid
/// invoice was on screen in v1.
String? ageLabel(Invoice invoice) {
  final days = invoice.daysLate;
  if (days == null) return null;
  if (days > 0) return appL10n.invoicesAgeLate(days);
  if (days == 0) return appL10n.invoicesAgeDueToday;
  return appL10n.invoicesAgeLeft(days.abs());
}

/// The status pill is the shared `StatusBadge`, drawn from
/// `invoice.statusLabel` and `invoice.statusColor`. There is no invoice-only
/// pill widget here on purpose: the app already had one badge and did not need
/// a second.
