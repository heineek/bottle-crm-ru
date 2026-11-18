/**
 * Lead webhooks (`/api/leads/intakes/`) as the Lead capture pages read them.
 *
 * Browser-safe, so the pages and tests can import it. An intake is a public
 * URL that turns each post into a lead; its mapping says which field of the
 * post fills which lead field. The server validates every mapping target, so
 * the lists here only decide what the editor offers.
 */
import { WEBFORM_LEAD_FIELDS } from '#lib/v2/webform-fields.js';
import { m } from '#lib/paraglide/messages.js';

/** `LeadIntake.preset` choices, in the order the create panel offers them. */
export const INTAKE_PRESETS: { value: string; readonly label: string }[] = [
  {
    value: 'generic',
    get label() {
      return m.settings_lead_capture_preset_generic();
    }
  },
  {
    value: 'google_ads',
    get label() {
      return m.settings_lead_capture_preset_google_ads();
    }
  },
  { value: 'tally', label: 'Tally' },
  { value: 'gravity_forms', label: 'Gravity Forms' }
];

export function presetLabel(preset: string | null | undefined) {
  return (
    INTAKE_PRESETS.find((p) => p.value === preset)?.label ?? m.settings_lead_capture_preset_any()
  );
}

/** The source a new webhook starts with, by preset, when the org has it. */
const PRESET_SOURCE = {
  generic: 'web form',
  google_ads: 'google ads',
  tally: 'web form',
  gravity_forms: 'web form'
} as Record<string, string>;

/** @returns the preset's usual source key when it is active, else '' */
export function presetSource(
  preset: string,
  sources: { key: string; is_active?: boolean }[]
): string {
  const key = PRESET_SOURCE[preset];
  return key && (sources ?? []).some((s) => s.key === key && s.is_active !== false) ? key : '';
}

/**
 * How a mapping names a custom field. Lead columns are named as web forms
 * name them (`first_name`); a custom field is its definition key behind this.
 */
export const CUSTOM_TARGET_PREFIX = 'custom_fields.';

/**
 * What a mapping row may fill: the web forms' lead columns, then the org's
 * active lead custom fields.
 */
export function mappingTargets(
  customFields: { key: string; label: string }[]
): { value: string; label: string }[] {
  return [
    ...WEBFORM_LEAD_FIELDS.map((f) => ({ value: f.value, label: f.label })),
    ...(customFields ?? []).map((f) => ({
      value: `${CUSTOM_TARGET_PREFIX}${f.key}`,
      label: f.label
    }))
  ];
}

/**
 * The targets plus any a stored row names that the list cannot offer (a
 * preset's own target, or a custom field turned off since), so the row's
 * select keeps its value and a save does not drop it.
 */
export function targetsFor(
  targets: { value: string; label: string }[],
  mapping: { from: string; to: string }[]
) {
  const known = new Set(targets.map((t) => t.value));
  const extra = [];
  for (const row of mapping ?? []) {
    if (row?.to && !known.has(row.to)) {
      known.add(row.to);
      extra.push({ value: row.to, label: row.to });
    }
  }
  return [...targets, ...extra];
}

/** Rows as the API takes them: trimmed strings, both halves set, nothing else. */
export function cleanMapping(rows: unknown): { from: string; to: string }[] {
  if (!Array.isArray(rows)) return [];
  return rows
    .map((r: { from?: unknown; to?: unknown } | null | undefined) => ({
      from: typeof r?.from === 'string' ? r.from.trim() : '',
      to: typeof r?.to === 'string' ? r.to.trim() : ''
    }))
    .filter((r) => r.from && r.to);
}

type Tone = 'moss' | 'ink' | 'slate' | 'rust' | 'clay';

const RESULTS = {
  created: { label: () => m.settings_lead_capture_result_created(), tone: 'moss' },
  merged: { label: () => m.settings_lead_capture_result_merged(), tone: 'ink' },
  duplicate: { label: () => m.settings_lead_capture_result_duplicate(), tone: 'slate' },
  test: { label: () => m.settings_lead_capture_result_test(), tone: 'slate' },
  rejected: { label: () => m.settings_lead_capture_result_rejected(), tone: 'rust' }
} as Record<string, { label: () => string; tone: Tone }>;

/** @param result a delivery's `result` */
export function deliveryResult(result: string): { label: string; tone: Tone } {
  const known = Object.hasOwn(RESULTS, result) ? RESULTS[result] : null;
  if (known) return { label: known.label(), tone: known.tone };
  return { label: result || m.settings_lead_capture_result_unknown(), tone: 'slate' };
}

export function intakeState(intake: { is_active?: boolean; last_received_at?: string | null }): {
  label: string;
  tone: 'moss' | 'slate';
} {
  if (!intake?.is_active) return { label: m.settings_lead_capture_state_off(), tone: 'slate' };
  if (!intake.last_received_at) {
    return { label: m.settings_lead_capture_state_waiting(), tone: 'slate' };
  }
  return { label: m.settings_lead_capture_state_receiving(), tone: 'moss' };
}
