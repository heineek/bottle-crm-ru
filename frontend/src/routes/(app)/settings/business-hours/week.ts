/**
 * What a week of business hours adds up to.
 *
 * Client-side display logic, in its own module rather than inline in
 * `+page.svelte`, because the harness cannot import a `.svelte` file and this
 * is a rule with a right answer that lives in `business_hours/calendar.py`.
 * The routing and escalation routes do the same with `rotation.js` and
 * `outcome.js`.
 *
 * `mobile/lib/data/models/business_calendar.dart` carries the same rules.
 */
import { m } from '#lib/paraglide/messages.js';

/** The API's English weekday names, Sunday first to match `Date.getDay()`. */
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** The weekday name the API uses for `date`, for matching against `calendar.days`. */
export function weekdayName(date = new Date()) {
  return DAY_NAMES[date.getDay()];
}

/** A weekday's label in the reader's language; the API sends the English name. */
export function dayLabel(day: string) {
  switch (day) {
    case 'Monday':
      return m.settings_hours_day_monday();
    case 'Tuesday':
      return m.settings_hours_day_tuesday();
    case 'Wednesday':
      return m.settings_hours_day_wednesday();
    case 'Thursday':
      return m.settings_hours_day_thursday();
    case 'Friday':
      return m.settings_hours_day_friday();
    case 'Saturday':
      return m.settings_hours_day_saturday();
    case 'Sunday':
      return m.settings_hours_day_sunday();
    default:
      return day;
  }
}

/**
 * Hours a day is open, or 0.
 *
 * Zero for a day whose close is not after its open, which is what
 * `_has_any_open_window` does with the same pair (`c > o`) and what the walker
 * does per day (`close_t <= open_t` counts as closed). The serializer refuses
 * that combination on write, so it can only arrive from older data, but it can
 * arrive.
 */
export function dayHours(day: { open: string | null; close: string | null }) {
  if (!day?.open || !day?.close) return 0;
  const [oh, om] = day.open.split(':').map(Number);
  const [ch, cm] = day.close.split(':').map(Number);
  if ([oh, om, ch, cm].some((n) => Number.isNaN(n))) return 0;
  const span = ch * 60 + cm - (oh * 60 + om);
  return span > 0 ? span / 60 : 0;
}

export function weeklyHours(days: { open: string | null; close: string | null }[]) {
  return (days ?? []).reduce((total, day) => total + dayHours(day), 0);
}

/**
 * Whether this calendar is consulted at all.
 *
 * **A calendar with no open window is a 24/7 calendar, not a closed one.**
 * `add_business_hours` checks `_has_any_open_window` first and, when nothing is
 * open, returns `start_dt + timedelta(hours=hours)`: plain wall-clock
 * arithmetic, holidays included. So marking every day Closed does not stop the
 * SLA clock, it makes it run continuously, which is the opposite of what a page
 * showing seven "Closed" rows otherwise implies. The one state where this page
 * has to contradict its own rows.
 */
export function isAlwaysOn(days: { open: string | null; close: string | null }[]) {
  return (days ?? []).every((day) => dayHours(day) <= 0);
}
