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
  LEAD_SOURCE_LABEL,
  LEAD_STATUS_LABEL,
  OPPORTUNITY_TYPE_LABEL,
  TASK_PRIORITY_LABEL,
  TASK_STATUS_LABEL
} from '#lib/v2/enums.js';

/**
 * One option whose label is read per access, so it follows the request's locale.
 *
 * @param {string} value
 * @param {() => string} label
 * @returns {{ value: string, readonly label: string }}
 */
const option = (value, label) => ({
  value,
  get label() {
    return label();
  }
});

/** @type {{ value: string, label: string }[]} */
export const LEAD_STATUSES = [
  option('ALL', () => m.app_enum_filter_all_statuses()),
  option('ASSIGNED', () => LEAD_STATUS_LABEL.assigned),
  option('IN_PROCESS', () => m.app_enum_filter_in_process()),
  option('CONVERTED', () => LEAD_STATUS_LABEL.converted),
  option('RECYCLED', () => LEAD_STATUS_LABEL.recycled),
  option('CLOSED', () => LEAD_STATUS_LABEL.closed)
];

/** @type {{ value: string, label: string }[]} */
export const LEAD_SOURCES = [
  option('ALL', () => m.app_enum_filter_all_sources()),
  option('call', () => LEAD_SOURCE_LABEL.call),
  option('email', () => LEAD_SOURCE_LABEL.email),
  option('existing customer', () => m.app_enum_filter_existing_customer()),
  option('partner', () => LEAD_SOURCE_LABEL.partner),
  option('public relations', () => m.app_enum_filter_public_relations()),
  option('compaign', () => LEAD_SOURCE_LABEL.compaign),
  option('other', () => LEAD_SOURCE_LABEL.other)
];

/** @type {{ value: string, label: string }[]} */
export const LEAD_RATINGS = [
  option('ALL', () => m.app_enum_filter_all_ratings()),
  option('HOT', () => m.app_enum_rating_hot()),
  option('WARM', () => m.app_enum_rating_warm()),
  option('COLD', () => m.app_enum_rating_cold())
];

/** @type {{ value: string, label: string }[]} */
export const CASE_STATUSES = [
  option('ALL', () => m.app_enum_filter_all_statuses()),
  ...Object.keys(CASE_STATUS_LABEL).map((value) =>
    option(value, () => CASE_STATUS_LABEL[/** @type {keyof typeof CASE_STATUS_LABEL} */ (value)])
  )
];

/** @type {{ value: string, label: string }[]} */
export const CASE_TYPES = [
  option('', () => m.app_enum_filter_select_type()),
  ...Object.keys(CASE_TYPE_LABEL).map((value) =>
    option(value, () => CASE_TYPE_LABEL[/** @type {keyof typeof CASE_TYPE_LABEL} */ (value)])
  )
];

/** @type {{ value: string, label: string }[]} */
export const PRIORITIES = [
  option('ALL', () => m.app_enum_filter_all_priorities()),
  option('High', () => TASK_PRIORITY_LABEL.High),
  option('Medium', () => TASK_PRIORITY_LABEL.Medium),
  option('Low', () => TASK_PRIORITY_LABEL.Low)
];

/** @type {{ value: string, label: string }[]} */
export const TASK_STATUSES = [
  option('ALL', () => m.app_enum_filter_all_statuses()),
  ...Object.keys(TASK_STATUS_LABEL).map((value) =>
    option(value, () => TASK_STATUS_LABEL[/** @type {keyof typeof TASK_STATUS_LABEL} */ (value)])
  )
];

/** @type {{ value: string, label: string }[]} */
export const OPPORTUNITY_TYPES = [
  option('', () => m.app_enum_filter_select_type()),
  ...Object.keys(OPPORTUNITY_TYPE_LABEL).map((value) =>
    option(
      value,
      () => OPPORTUNITY_TYPE_LABEL[/** @type {keyof typeof OPPORTUNITY_TYPE_LABEL} */ (value)]
    )
  )
];

/** @type {{ value: string, label: string }[]} */
export const OPPORTUNITY_SOURCES = [
  option('', () => m.app_enum_filter_select_source()),
  option('NONE', () => m.app_enum_source_none()),
  option('CALL', () => LEAD_SOURCE_LABEL.call),
  option('EMAIL', () => LEAD_SOURCE_LABEL.email),
  option('EXISTING CUSTOMER', () => m.app_enum_filter_existing_customer()),
  option('PARTNER', () => LEAD_SOURCE_LABEL.partner),
  option('PUBLIC RELATIONS', () => m.app_enum_filter_public_relations()),
  option('CAMPAIGN', () => LEAD_SOURCE_LABEL.compaign),
  option('WEBSITE', () => m.app_enum_source_website()),
  option('OTHER', () => LEAD_SOURCE_LABEL.other)
];

/** The English names the list has always shown; other locales ask `Intl`. */
const CURRENCY_NAMES = {
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

/** @param {string} code @param {string} english */
function currencyName(code, english) {
  const locale = getLocale();
  if (locale === 'en') return english;
  const name = new Intl.DisplayNames([intlLocale(locale, 'number')], { type: 'currency' }).of(code);
  return name && name !== code ? name : english;
}

/** @type {{ value: string, label: string }[]} */
export const CURRENCY_CODES = [
  option('', () => m.app_enum_filter_select_currency()),
  ...Object.entries(CURRENCY_NAMES).map(([code, english]) =>
    option(code, () => `${code} - ${currencyName(code, english)}`)
  )
];

/** @type {Record<string, string>} */
export const CURRENCY_SYMBOLS = {
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
