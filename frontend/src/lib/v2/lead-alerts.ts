import { m } from '#lib/paraglide/messages.js';
import { missingOptions } from '#lib/v2/pickers.js';

export const REMINDER_CHOICES = [5, 15, 30, 60];

export function reminderLabel(minutes: number | null | undefined): string {
  return minutes ? m.profile_lead_alert_minutes({ count: minutes }) : m.profile_lead_alert_off();
}

/**
 * The stored value as an option when the choices lack it, so a select never
 * submits its first entry in place of a value the API once accepted.
 */
export function reminderExtra(minutes: number | null | undefined): number[] {
  const stored = minutes ? [{ id: String(minutes) }] : [];
  return missingOptions(
    REMINDER_CHOICES.map((m) => ({ id: String(m) })),
    stored
  ).map((o) => Number(o.id));
}

export const DOCS_LEAD_ALERTS = 'https://django-crm.readthedocs.io/en/latest/features/lead-alerts/';
export const DOCS_WEBHOOKS = 'https://django-crm.readthedocs.io/en/latest/integrations/webhooks/';

export const WEBHOOK_FORMATS: { value: string; label: string; short: string }[] = [
  {
    value: 'json',
    get label() {
      return m.profile_webhook_format_json();
    },
    get short() {
      return m.profile_webhook_format_json_short();
    }
  },
  {
    value: 'slack',
    get label() {
      return m.profile_webhook_format_slack();
    },
    get short() {
      return m.profile_webhook_format_slack_short();
    }
  },
  {
    value: 'teams',
    get label() {
      return m.profile_webhook_format_teams();
    },
    get short() {
      return m.profile_webhook_format_teams_short();
    }
  }
];

export function webhookFormatName(format: string): string {
  return WEBHOOK_FORMATS.find((f) => f.value === format)?.short ?? format;
}
