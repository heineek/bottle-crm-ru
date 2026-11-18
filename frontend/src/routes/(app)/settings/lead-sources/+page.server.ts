import { fail } from '@sveltejs/kit';
import {
  createLeadSource,
  listSourcesForSettings,
  orderLeadSources,
  updateLeadSource
} from '#lib/server/v2/lead-sources.js';
import { readableError } from '#lib/server/v2/form-errors.js';
import { apiStatus } from '#lib/api-errors.js';
import { moveKeys } from '#lib/v2/lead-sources.js';
import { m } from '#lib/paraglide/messages.js';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async (event) => {
  return await listSourcesForSettings(event);
};

/**
 * The status and sentence for a refused write. Every write is admin-only
 * server-side; the page hides the controls from a member, and a member
 * posting anyway reads this.
 */
function refusal(err: unknown, fallback: string): { status: number; error: string } {
  if (apiStatus(err) === 403) return { status: 403, error: m.settings_lead_sources_admin_only() };
  if (apiStatus(err) === 404) return { status: 404, error: m.settings_lead_sources_gone_now() };
  return { status: 400, error: readableError(err, fallback) };
}

/** A refusal under the action's key, with the row it was about. */
function refused(key: string, id: string, err: unknown, fallback: string) {
  const { status, error } = refusal(err, fallback);
  return fail(status, { [key]: { id, error } });
}

export const actions: Actions = {
  async add(event) {
    const form = await event.request.formData();
    const label = form.get('label')?.toString().trim() ?? '';
    if (!label)
      return fail(400, { add: { id: '', error: m.settings_lead_sources_give_name(), label } });
    try {
      await createLeadSource(event, label);
    } catch (err) {
      const { status, error } = refusal(err, m.settings_lead_sources_add_failed());
      return fail(status, { add: { id: '', error, label } });
    }
    return { added: label };
  },

  async rename(event) {
    const form = await event.request.formData();
    const id = form.get('id')?.toString() ?? '';
    const label = form.get('label')?.toString().trim() ?? '';
    if (!label) return fail(400, { rename: { id, error: m.settings_lead_sources_needs_name() } });
    try {
      await updateLeadSource(event, id, { label });
    } catch (err) {
      return refused('rename', id, err, m.settings_lead_sources_rename_failed());
    }
    return { renamed: id };
  },

  // Retire and restore send `is_active` alone, so neither can carry a stale label.
  async retire(event) {
    const form = await event.request.formData();
    const id = form.get('id')?.toString() ?? '';
    const active = form.get('is_active')?.toString();
    if (active !== 'true' && active !== 'false') {
      return fail(400, { retire: { id, error: m.settings_lead_sources_change_invalid() } });
    }
    try {
      await updateLeadSource(event, id, { is_active: active === 'true' });
    } catch (err) {
      return refused('retire', id, err, m.settings_lead_sources_change_failed());
    }
    return { retired: id };
  },

  /** Re-reads the list, so the order sent is built from what the server holds now. */
  async move(event) {
    const form = await event.request.formData();
    const key = form.get('key')?.toString() ?? '';
    const direction = form.get('direction')?.toString() ?? '';
    let keys;
    try {
      const { sources } = await listSourcesForSettings(event);
      keys = moveKeys(sources, key, direction);
    } catch (err) {
      return refused('move', key, err, m.settings_lead_sources_read_failed());
    }
    if (!keys)
      return fail(400, { move: { id: key, error: m.settings_lead_sources_move_invalid() } });
    try {
      await orderLeadSources(event, keys);
    } catch (err) {
      return refused('move', key, err, m.settings_lead_sources_reorder_failed());
    }
    return { moved: key };
  }
};
