/**
 * What an inbound address refused, in the words the inbound email settings
 * page uses. `mobile/lib/data/models/mailbox.dart` says the same.
 */
import { count } from '#lib/v2/format.js';
import { m } from '#lib/paraglide/messages.js';

type Phrase = (input: { count: number; shown: string }) => string;

/** The reasons the backend sends, in the order a row names them. */
const REASONS: [string, Phrase][] = [
  ['spam', (i) => m.settings_inbound_drop_spam(i)],
  ['virus', (i) => m.settings_inbound_drop_virus(i)],
  ['spoofed', (i) => m.settings_inbound_drop_spoofed(i)],
  ['automatic', (i) => m.settings_inbound_drop_automatic(i)],
  ['other', (i) => m.settings_inbound_drop_other(i)]
];

function positive(n: unknown) {
  const v = Number(n);
  return Number.isFinite(v) && v > 0 ? v : 0;
}

/**
 * "12 dropped in 30 days: 9 spam, 2 failed the sender check, 1 automatic
 * reply", or null when the address dropped nothing. A reason not in the list
 * above is left out of the breakdown but still counted in the total.
 */
export function dropSummary(mailbox: {
  dropped_last_30d?: number;
  drops_last_30d?: Record<string, number>;
}): string | null {
  const total = positive(mailbox?.dropped_last_30d);
  if (!total) return null;
  const parts = [];
  for (const [key, phrase] of REASONS) {
    const n = positive(mailbox?.drops_last_30d?.[key]);
    if (n) parts.push(phrase({ count: n, shown: count(n) }));
  }
  const shown = count(total);
  return parts.length
    ? m.settings_inbound_drops_with_parts({ shown, parts: parts.join(', ') })
    : m.settings_inbound_drops({ shown });
}

/** The warning for an address that has taken its daily limit, or null. */
export function limitNotice(
  limitReached: boolean | undefined,
  dailyLimit: number | null | undefined
): string | null {
  if (limitReached !== true) return null;
  const n = positive(dailyLimit);
  return n
    ? m.settings_inbound_limit_notice({ count: n, shown: count(n) })
    : m.settings_inbound_limit_notice_daily();
}

/**
 * What every address refuses, for the page's explanation. Null when the API
 * sends no `daily_limit`: an API that old filters none of this, so the
 * sentence would be false.
 */
export function dropPolicy(dailyLimit: number | null | undefined): string | null {
  const n = positive(dailyLimit);
  if (!n) return null;
  // The 20 is `cases.inbound.limits.SENDER_HOURLY_LIMIT`, which the API does not send.
  return m.settings_inbound_drop_policy({ count: n, shown: count(n) });
}
