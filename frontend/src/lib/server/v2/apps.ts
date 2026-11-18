/**
 * Industry apps (`/api/apps/`): the catalogue with this org's install state,
 * what an action would do, and install, upgrade and remove. Any member reads
 * the list; the rest is for admins, and the server decides. An API without
 * apps answers 404 and the Apps page hides the section.
 *
 * Every call takes something with a `.get('jwt_access')`, so signup can pass
 * a bearer-only reader for the org it just created (`org/new/+page.server.ts`).
 */
import { apiRequest } from '#lib/api-helpers.js';
import { apiStatus } from '#lib/api-errors.js';
import { readableError } from '#lib/server/v2/form-errors.js';
import { m } from '#lib/paraglide/messages.js';
import type { Cookies } from '@sveltejs/kit';
import type { components } from '#lib/api-schema.js';

type Schemas = components['schemas'];

type CookieReader = Cookies | { get: (name: string) => string | undefined };

const APP_ACTIONS = ['install', 'upgrade', 'remove'] as const;

/** Catalogue ids look like `professional-services`; anything else is never sent. */
const APP_ID = /^[a-z0-9][a-z0-9_-]{0,63}$/;

export function isAppId(id: unknown) {
  return typeof id === 'string' && APP_ID.test(id);
}

export function isAppAction(action: unknown): action is (typeof APP_ACTIONS)[number] {
  return APP_ACTIONS.some((known) => known === action);
}

const auth = (cookies: CookieReader) => ({ cookies: cookies as Cookies });

function toApp(raw: Schemas['IndustryApp']) {
  const by = raw?.installed_by_details;
  return {
    id: String(raw?.id ?? ''),
    name: String(raw?.name ?? raw?.id ?? ''),
    description: String(raw?.description ?? ''),
    version: raw?.version ?? null,
    status: raw?.status === 'installed' || raw?.status === 'removed' ? raw.status : 'not_installed',
    installedVersion: raw?.installed_version ?? null,
    updateAvailable: raw?.update_available === true,
    skippedModules: Array.isArray(raw?.skipped_modules) ? raw.skipped_modules.map(String) : [],
    installedAt: raw?.installed_at ?? null,
    installedBy: by && typeof by === 'object' ? String(by.name ?? '') : ''
  };
}

export type App = ReturnType<typeof toApp>;

/**
 * The catalogue, in its own order. `absent` on an API without apps (404),
 * `failed` when the read broke, so the page can say which.
 */
export async function listApps(
  cookies: CookieReader
): Promise<{ state: 'ok' | 'absent' | 'failed'; apps: App[] }> {
  try {
    const resp: Schemas['AppListResponse'] = await apiRequest(
      '/apps/',
      { quietErrors: true, expectedStatuses: [404] },
      auth(cookies)
    );
    const rows = Array.isArray(resp?.apps) ? resp.apps : [];
    return { state: 'ok', apps: rows.map(toApp).filter((a) => a.id) };
  } catch (err) {
    return { state: apiStatus(err) === 404 ? 'absent' : 'failed', apps: [] };
  }
}

/** Preview item types in the order the confirmation lists them. */
const TYPES: [string, () => string][] = [
  ['wording', () => m.settings_apps_type_wording()],
  ['object', () => m.settings_apps_type_object()],
  ['field', () => m.settings_apps_type_field()],
  ['pipeline', () => m.settings_apps_type_pipeline()],
  ['stage', () => m.settings_apps_type_stage()],
  ['tag', () => m.settings_apps_type_tag()],
  ['source', () => m.settings_apps_type_source()],
  ['product', () => m.settings_apps_type_product()]
];

const EFFECTS: Record<string, () => string> = {
  add: () => m.settings_apps_effect_add(),
  keep: () => m.settings_apps_effect_keep(),
  turn_off: () => m.settings_apps_effect_turn_off(),
  turn_on: () => m.settings_apps_effect_turn_on(),
  restore_wording: () => m.settings_apps_effect_restore_wording(),
  skipped_module: () => m.settings_apps_effect_skipped_module(),
  add_by_hand: () => m.settings_apps_effect_add_by_hand(),
  conflict: () => m.settings_apps_effect_conflict(),
  restore: () => m.settings_apps_effect_restore()
};

const TARGETS: Record<string, () => string> = {
  lead: () => m.settings_apps_target_lead(),
  contact: () => m.settings_apps_target_contact(),
  account: () => m.settings_apps_target_account(),
  deal: () => m.settings_apps_target_deal(),
  opportunity: () => m.settings_apps_target_deal(),
  ticket: () => m.settings_apps_target_ticket(),
  case: () => m.settings_apps_target_ticket(),
  task: () => m.settings_apps_target_task(),
  invoice: () => m.settings_apps_target_invoice(),
  estimate: () => m.settings_apps_target_estimate(),
  recurring_invoice: () => m.settings_apps_target_recurring_invoice()
};

type PreviewItem = { label: string; target: string; effect: string; effectLabel: string };

/**
 * Preview items grouped by type, in a fixed order, each group keeping the
 * server's order. A type this client does not know is listed last under its
 * own name rather than dropped.
 */
export function groupPreview(
  items: Schemas['AppPreviewItem'][]
): { type: string; label: string; items: PreviewItem[] }[] {
  const byType: Map<string, PreviewItem[]> = new Map();
  for (const item of Array.isArray(items) ? items : []) {
    const type = String(item?.type ?? '');
    if (!type) continue;
    const effect = String(item?.effect ?? '');
    const target = item?.target ? String(item.target) : '';
    byType.set(type, [
      ...(byType.get(type) ?? []),
      {
        label: String(item?.label ?? ''),
        target: target ? (Object.hasOwn(TARGETS, target) ? TARGETS[target]() : target) : '',
        effect,
        effectLabel: Object.hasOwn(EFFECTS, effect)
          ? EFFECTS[effect]()
          : effect.replaceAll('_', ' ')
      }
    ]);
  }
  const known = TYPES.filter(([type]) => byType.has(type)).map(([type, label]) => ({
    type,
    label: label(),
    items: byType.get(type) ?? []
  }));
  const other = [...byType.keys()]
    .filter((type) => !TYPES.some(([t]) => t === type))
    .map((type) => ({ type, label: type.replaceAll('_', ' '), items: byType.get(type) ?? [] }));
  return [...known, ...other];
}

/** What an action would do, grouped for the confirmation. Writes nothing. */
export async function previewApp(cookies: CookieReader, id: string, action: string) {
  const resp: Schemas['AppPreviewResponse'] = await apiRequest(
    `/apps/${encodeURIComponent(id)}/preview/?action=${encodeURIComponent(action)}`,
    { quietErrors: true, expectedStatuses: [403, 404] },
    auth(cookies)
  );
  const sample = resp?.sample_data;
  return {
    action: String(resp?.action ?? action),
    groups: groupPreview(resp?.items),
    sampleData: {
      offered: sample?.offered === true,
      defaultOn: sample?.default_on === true,
      records: sample && Number.isFinite(sample.records) ? sample.records : 0
    }
  };
}

/** @param sampleData sent on every install, true or false */
export async function installApp(cookies: CookieReader, id: string, sampleData: boolean) {
  const resp: Schemas['AppActionResponse'] = await apiRequest(
    `/apps/${encodeURIComponent(id)}/install/`,
    { method: 'POST', body: { sample_data: sampleData === true } },
    auth(cookies)
  );
  return resp?.app ? toApp(resp.app) : null;
}

export async function upgradeApp(cookies: CookieReader, id: string) {
  const resp: Schemas['AppActionResponse'] = await apiRequest(
    `/apps/${encodeURIComponent(id)}/upgrade/`,
    { method: 'POST', body: {} },
    auth(cookies)
  );
  return resp?.app ? toApp(resp.app) : null;
}

export async function removeApp(cookies: CookieReader, id: string) {
  const resp: Schemas['AppActionResponse'] = await apiRequest(
    `/apps/${encodeURIComponent(id)}/remove/`,
    { method: 'POST', body: {} },
    auth(cookies)
  );
  return resp?.app ? toApp(resp.app) : null;
}

/**
 * A refused action as one sentence. A 409 carries the server's own reason
 * (nothing new to add, not installed).
 */
export function appRefusal(err: unknown, action: string) {
  if (apiStatus(err) === 404) return m.settings_apps_refusal_missing();
  const forbidden = apiStatus(err) === 403;
  if (action === 'install') {
    return forbidden
      ? m.settings_apps_refusal_install_admin()
      : readableError(err, m.settings_apps_refusal_install());
  }
  if (action === 'upgrade') {
    return forbidden
      ? m.settings_apps_refusal_update_admin()
      : readableError(err, m.settings_apps_refusal_update());
  }
  if (action === 'remove') {
    return forbidden
      ? m.settings_apps_refusal_remove_admin()
      : readableError(err, m.settings_apps_refusal_remove());
  }
  return forbidden
    ? m.settings_apps_refusal_change_admin()
    : readableError(err, m.settings_apps_refusal_change());
}
