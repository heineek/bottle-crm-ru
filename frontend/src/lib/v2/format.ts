/** Formatting helpers for v2. Every number rendered goes through one of these. */

import { intlLocale } from '#lib/i18n/locale.js';
import { m } from '#lib/paraglide/messages.js';
import { getLocale } from '#lib/paraglide/runtime.js';

// Read per call, not once: on the server the locale is the request's.
const numberLocale = () => intlLocale(getLocale(), 'number');
const dateLocale = () => intlLocale(getLocale(), 'date');

function relative(n: number, unit: 'day' | 'hour' | 'minute') {
  return new Intl.RelativeTimeFormat(numberLocale(), { numeric: 'auto' }).format(n, unit);
}

/** "1h", "48m", "12d" in English; "1 ч", "48 мин" in Russian. */
function unit(n: number, name: 'day' | 'hour' | 'minute') {
  return new Intl.NumberFormat(numberLocale(), {
    style: 'unit',
    unit: name,
    unitDisplay: 'narrow'
  }).format(n);
}

type IsoInput = string | Date | null | undefined;

export function money(n: number | string | null | undefined, currency = 'USD') {
  const v = Number(n ?? 0);
  if (!Number.isFinite(v)) return '—';
  return new Intl.NumberFormat(numberLocale(), {
    style: 'currency',
    currency,
    maximumFractionDigits: v % 1 === 0 ? 0 : 2
  }).format(v);
}

/**
 * One amount per currency, never added together: there are no exchange rates.
 * Empty string for an empty list, so the caller picks its own placeholder.
 */
export function moneyEach(list: { currency: string; amount: number }[] | null | undefined) {
  return (list ?? []).map((m) => money(m.amount, m.currency)).join(' · ');
}

/**
 * Rows that each carry a currency, added up per currency in the shape
 * `moneyEach` prints: ordered by code, zeros dropped. Only for figures a page
 * derives from rows it holds; totals the API computes arrive already split.
 */
export function sumByCurrency(
  rows: Array<{ [key: string]: unknown }>,
  field: string = 'amount'
): { currency: string; amount: number }[] {
  const totals: Record<string, number> = {};
  for (const row of rows) {
    const currency = String(row.currency);
    totals[currency] = (totals[currency] ?? 0) + ((row[field] ?? 0) as number);
  }
  return Object.keys(totals)
    .sort()
    .filter((currency) => totals[currency] !== 0)
    .map((currency) => ({ currency, amount: totals[currency] }));
}

export function count(n: number | string | null | undefined) {
  const v = Number(n ?? 0);
  return Number.isFinite(v) ? v.toLocaleString(numberLocale()) : '—';
}

export function initials(name: string | null | undefined) {
  return String(name ?? '')
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0])
    .join('')
    .toUpperCase();
}

/**
 * ISO string → Date, or null when there is nothing to render.
 *
 * A date-only string ("2026-08-07") names a calendar day, not an instant, and
 * `new Date()` reads it as UTC midnight. A browser west of UTC then prints
 * that as the day before: a due date set for Friday reads as Thursday, and a
 * chart bucket the API labelled Friday sits under the wrong label. Appending a
 * time is what makes it parse as local midnight instead. Anything that carries
 * a time of day is a real instant and is left exactly as it was.
 */
function parseIso(value: IsoInput) {
  if (!value) return null;
  const d =
    typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
      ? new Date(`${value}T00:00:00`)
      : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * ISO date → "8 Aug", or "8 Aug 2023" when it is not this year, otherwise a
 * deal closed three years ago reads as if it closed last week.
 * Returns an em dash for null so table cells never collapse.
 */
export function shortDate(iso: IsoInput, now = new Date()) {
  const d = parseIso(iso);
  if (!d) return '—';
  const sameYear = d.getFullYear() === now.getFullYear();
  return new Intl.DateTimeFormat(dateLocale(), {
    day: 'numeric',
    month: 'short',
    ...(sameYear ? {} : { year: 'numeric' })
  }).format(d);
}

/** ISO date → "8 August 2026". */
export function longDate(iso: IsoInput) {
  const d = parseIso(iso);
  if (!d) return '—';
  return new Intl.DateTimeFormat(dateLocale(), {
    day: 'numeric',
    month: 'long',
    year: 'numeric'
  }).format(d);
}

/** Whole days between an ISO date and today. Negative = in the future. */
export function daysSince(iso: IsoInput, now = new Date()) {
  const d = parseIso(iso);
  if (!d) return null;
  return Math.floor((now.getTime() - d.getTime()) / 86400000);
}

/** "12 days ago" / "today" / "in 4 days", for a person, not a machine. */
export function relativeDays(iso: IsoInput, now = new Date()) {
  const n = daysSince(iso, now);
  if (n === null) return '—';
  return relative(-n, 'day');
}

/**
 * "just now" / "18 minutes ago" / "3 hours ago", then whole days.
 *
 * `relativeDays` is right for records, a lead touched at 09:00 and one
 * touched at 17:00 are both "today" and the difference does not change what
 * you do. A feed is the opposite: a mention from five minutes ago and one from
 * twenty hours ago are different events, and collapsing both to "today" is how
 * you end up re-reading the whole list to find what is new.
 */
export function relativeTime(iso: IsoInput, now = new Date()) {
  const d = parseIso(iso);
  if (!d) return '—';
  const mins = Math.floor((now.getTime() - d.getTime()) / 60000);
  if (mins < 0) return relativeDays(iso, now);
  if (mins < 1) return m.time_just_now();
  if (mins < 60) return relative(-mins, 'minute');
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return relative(-hrs, 'hour');
  return relativeDays(iso, now);
}

/**
 * A duration in minutes as "1h 48m".
 *
 * Logged time is read in hours: "108m" makes the reader do the division, and
 * two of them on the same screen makes them do it twice. Minutes below the
 * hour keep their own suffix so a short entry does not render as "0h 12m".
 */
export function hoursMinutes(mins: number | string | null | undefined) {
  const v = Number(mins ?? 0);
  if (!Number.isFinite(v)) return unit(0, 'minute');
  const total = Math.max(0, Math.round(v));
  const h = Math.floor(total / 60);
  return h ? `${unit(h, 'hour')} ${unit(total % 60, 'minute')}` : unit(total, 'minute');
}

/** Compact age for a table cell: "12d", "3h". */
export function shortAge(iso: IsoInput, now = new Date()) {
  const d = parseIso(iso);
  if (!d) return '—';
  const mins = Math.max(0, Math.floor((now.getTime() - d.getTime()) / 60000));
  if (mins < 60) return unit(mins, 'minute');
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return unit(hrs, 'hour');
  return unit(Math.floor(hrs / 24), 'day');
}

// English only: en-GB's short September is "Sept", and run times always said "Sep".
const RUN_MONTHS = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

/**
 * A run's instant in the org's timezone, 24-hour: "Today 10:42",
 * "Yesterday 18:03", "21 Oct 18:03", "21 Oct 2025 18:03".
 */
export function runTime(iso: string | null | undefined, timeZone: string, now: Date = new Date()) {
  const d = parseIso(iso);
  if (!d) return shortDate(null);
  let zone = timeZone;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone });
  } catch {
    zone = 'UTC';
  }
  const parts = (
    date: Date
  ): {
    hour: string;
    minute: string;
    day: number;
    year: number;
    monthIndex: number;
    month: string;
  } => {
    const out: Record<string, string> = Object.fromEntries(
      new Intl.DateTimeFormat('en-US', {
        timeZone: zone,
        year: 'numeric',
        month: 'numeric',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        hourCycle: 'h23'
      })
        .formatToParts(date)
        .map((p) => [p.type, p.value])
    );
    const monthIndex = Number(out.month) - 1;
    return {
      hour: out.hour,
      minute: out.minute,
      day: Number(out.day),
      year: Number(out.year),
      monthIndex,
      month:
        getLocale() === 'en'
          ? RUN_MONTHS[monthIndex]
          : new Intl.DateTimeFormat(dateLocale(), { timeZone: zone, month: 'short' }).format(date)
    };
  };
  const at = parts(d);
  const today = parts(now);
  const dayNumber = (p: { year: number; monthIndex: number; day: number }) =>
    Date.UTC(p.year, p.monthIndex, p.day) / 86400000;
  const clock = `${at.hour}:${at.minute}`;
  const gap = dayNumber(today) - dayNumber(at);
  if (gap === 0) return m.time_today_at({ time: clock });
  if (gap === 1) return m.time_yesterday_at({ time: clock });
  const date = `${at.day} ${at.month}`;
  return at.year === today.year ? `${date} ${clock}` : `${date} ${at.year} ${clock}`;
}
