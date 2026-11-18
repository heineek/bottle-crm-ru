/**
 * Interactions: calls, meetings, emails, WhatsApp and texts logged on a
 * record, plus the enquiries lead intake writes. Labels and formatting only,
 * safe in a component; the API calls are `#lib/server/v2/interactions.js`.
 */
import { m } from '#lib/paraglide/messages.js';

/** What a person may log. `enquiry` is written by lead intake, never a form. */
export const LOGGABLE_KINDS = ['call', 'meeting', 'email', 'whatsapp', 'sms'];

export const KIND_LABEL: Record<string, string> = {
  get call() {
    return m.leads_interaction_kind_call();
  },
  get meeting() {
    return m.leads_interaction_kind_meeting();
  },
  get email() {
    return m.leads_interaction_kind_email();
  },
  whatsapp: 'WhatsApp',
  get sms() {
    return m.leads_interaction_kind_sms();
  },
  get enquiry() {
    return m.leads_interaction_kind_enquiry();
  }
};

export const CALL_OUTCOMES = ['connected', 'no_answer', 'voicemail', 'busy', 'wrong_number'];

export const OUTCOME_LABEL: Record<string, string> = {
  get connected() {
    return m.leads_interaction_outcome_connected();
  },
  get no_answer() {
    return m.leads_interaction_outcome_no_answer();
  },
  get voicemail() {
    return m.leads_interaction_outcome_voicemail();
  },
  get busy() {
    return m.leads_interaction_outcome_busy();
  },
  get wrong_number() {
    return m.leads_interaction_outcome_wrong_number();
  }
};

const ENQUIRY_VIA: Record<string, () => string> = {
  webform: () => m.leads_interaction_via_webform(),
  intake: () => m.leads_interaction_via_intake(),
  email: () => m.leads_interaction_via_email()
};

/**
 * The line a timeline shows for one interaction: "Outgoing call", "Email
 * received", "Enquiry via web form".
 */
export function interactionTitle({
  kind,
  direction,
  origin
}: {
  kind: string;
  direction?: string;
  origin?: string;
}): string {
  const inbound = direction === 'inbound';
  if (kind === 'call')
    return inbound ? m.leads_interaction_call_inbound() : m.leads_interaction_call_outbound();
  if (kind === 'meeting') return m.leads_interaction_kind_meeting();
  if (kind === 'email')
    return inbound ? m.leads_interaction_email_inbound() : m.leads_interaction_email_outbound();
  if (kind === 'whatsapp')
    return inbound
      ? m.leads_interaction_whatsapp_inbound()
      : m.leads_interaction_whatsapp_outbound();
  if (kind === 'sms')
    return inbound ? m.leads_interaction_sms_inbound() : m.leads_interaction_sms_outbound();
  if (kind === 'enquiry') {
    const via = origin && origin !== 'manual' ? (ENQUIRY_VIA[origin]?.() ?? origin) : '';
    return via ? m.leads_interaction_enquiry_via({ via }) : m.leads_interaction_kind_enquiry();
  }
  return m.leads_interaction_activity();
}

/**
 * A span of time for a person: "under a minute", "14 min", "2 h 14 min",
 * "3 d 4 h". Empty for a value that is not a number; negative reads as zero.
 */
export function spanText(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return '';
  const s = Number(seconds);
  if (!Number.isFinite(s)) return '';
  const mins = Math.floor(Math.max(0, s) / 60);
  if (mins < 1) return m.leads_span_under_minute();
  if (mins < 60) return m.leads_span_minutes({ minutes: mins });
  const hours = Math.floor(mins / 60);
  if (hours < 24)
    return mins % 60
      ? m.leads_span_hours_minutes({ hours, minutes: mins % 60 })
      : m.leads_span_hours({ hours });
  const days = Math.floor(hours / 24);
  return hours % 24
    ? m.leads_span_days_hours({ days, hours: hours % 24 })
    : m.leads_span_days({ days });
}

/** Seconds from `iso` to `now`, or null when `iso` is not a date. */
export function secondsSince(iso: string | null | undefined, now: Date = new Date()) {
  if (!iso) return null;
  const at = new Date(iso).getTime();
  return Number.isNaN(at) ? null : (now.getTime() - at) / 1000;
}

/** A call's length, "about 4 min" when the phone estimated it. */
export function durationText(seconds: number | null | undefined, estimated = false) {
  const text = spanText(seconds);
  return text && estimated ? m.leads_span_about({ span: text }) : text;
}

/**
 * A lead's response time, which the API defines as its first response minus
 * its creation, wall clock. Empty until it has one.
 */
export function responseTimeText(lead: {
  first_response_at?: string | null;
  created_at?: string | null;
}) {
  if (!lead.first_response_at || !lead.created_at) return '';
  const first = new Date(lead.first_response_at).getTime();
  const created = new Date(lead.created_at).getTime();
  if (Number.isNaN(first) || Number.isNaN(created)) return '';
  return spanText((first - created) / 1000);
}

/**
 * `https://wa.me/<digits>` for an E.164 number, or null when there is none.
 * The API fills `phone_e164` only for a number it could parse, so a raw
 * `phone` is never used here.
 */
export function whatsappHref(e164: string | null | undefined) {
  const raw = String(e164 ?? '').trim();
  return /^\+[1-9]\d{6,14}$/.test(raw) ? `https://wa.me/${raw.slice(1)}` : null;
}
