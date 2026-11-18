/**
 * Filter option constants for list pages
 * @module lib/constants/filters
 */

import { m } from '#lib/paraglide/messages.js';
import { getLocale } from '#lib/paraglide/runtime.js';
import { intlLocale } from '#lib/i18n/locale.js';
import {
  CASE_STATUS_LABEL,
  CASE_TYPE_LABEL,
  LEAD_STATUS_LABEL,
  OPPORTUNITY_TYPE_LABEL,
  TASK_PRIORITY_LABEL,
  TASK_STATUS_LABEL
} from '#lib/v2/enums.js';

type Option = { value: string; label: string };

/** One option whose label is read per access, so it follows the request's locale. */
const option = (value: string, label: () => string): Option => ({
  value,
  get label() {
    return label();
  }
});

export const LEAD_STATUSES: Option[] = [
  option('ALL', () => m.app_enum_filter_all_statuses()),
  option('ASSIGNED', () => LEAD_STATUS_LABEL.assigned),
  option('IN_PROCESS', () => m.app_enum_filter_in_process()),
  option('CONVERTED', () => LEAD_STATUS_LABEL.converted),
  option('RECYCLED', () => LEAD_STATUS_LABEL.recycled),
  option('CLOSED', () => LEAD_STATUS_LABEL.closed)
];

export const LEAD_RATINGS: Option[] = [
  option('ALL', () => m.app_enum_filter_all_ratings()),
  option('HOT', () => m.app_enum_rating_hot()),
  option('WARM', () => m.app_enum_rating_warm()),
  option('COLD', () => m.app_enum_rating_cold())
];

export const CASE_STATUSES: Option[] = [
  option('ALL', () => m.app_enum_filter_all_statuses()),
  ...Object.keys(CASE_STATUS_LABEL).map((value) =>
    option(value, () => CASE_STATUS_LABEL[value as keyof typeof CASE_STATUS_LABEL])
  )
];

export const CASE_TYPES: Option[] = [
  option('', () => m.app_enum_filter_select_type()),
  ...Object.keys(CASE_TYPE_LABEL).map((value) =>
    option(value, () => CASE_TYPE_LABEL[value as keyof typeof CASE_TYPE_LABEL])
  )
];

export const PRIORITIES: Option[] = [
  option('ALL', () => m.app_enum_filter_all_priorities()),
  option('High', () => TASK_PRIORITY_LABEL.High),
  option('Medium', () => TASK_PRIORITY_LABEL.Medium),
  option('Low', () => TASK_PRIORITY_LABEL.Low)
];

export const TASK_STATUSES: Option[] = [
  option('ALL', () => m.app_enum_filter_all_statuses()),
  ...Object.keys(TASK_STATUS_LABEL).map((value) =>
    option(value, () => TASK_STATUS_LABEL[value as keyof typeof TASK_STATUS_LABEL])
  )
];

export const OPPORTUNITY_TYPES: Option[] = [
  option('', () => m.app_enum_filter_select_type()),
  ...Object.keys(OPPORTUNITY_TYPE_LABEL).map((value) =>
    option(value, () => OPPORTUNITY_TYPE_LABEL[value as keyof typeof OPPORTUNITY_TYPE_LABEL])
  )
];

/** The English names the list has always shown; other locales ask `Intl`. */
const CURRENCY_NAMES: Record<string, string> = {
  USD: 'Dollar',
  EUR: 'Euro',
  GBP: 'Pound',
  INR: 'Rupee',
  CAD: 'Dollar',
  AUD: 'Dollar',
  JPY: 'Yen',
  CNY: 'Yuan',
  CHF: 'Franc',
  SGD: 'Dollar',
  AED: 'Dirham',
  BRL: 'Real',
  MXN: 'Peso',
  ZAR: 'Rand'
};

function currencyName(code: string, english: string) {
  const locale = getLocale();
  if (locale === 'en') return english;
  const name = new Intl.DisplayNames([intlLocale(locale, 'number')], { type: 'currency' }).of(code);
  return name && name !== code ? name : english;
}

export const CURRENCY_CODES: Option[] = [
  option('', () => m.app_enum_filter_select_currency()),
  ...Object.entries(CURRENCY_NAMES).map(([code, english]) =>
    option(code, () => `${code} - ${currencyName(code, english)}`)
  )
];

export const CURRENCY_SYMBOLS: Record<string, string> = {
  USD: '$',
  EUR: '€',
  GBP: '£',
  INR: '₹',
  CAD: 'CA$',
  AUD: 'A$',
  JPY: '¥',
  CNY: '¥',
  CHF: 'CHF',
  SGD: 'S$',
  AED: 'د.إ',
  BRL: 'R$',
  MXN: 'MX$',
  ZAR: 'R'
};
