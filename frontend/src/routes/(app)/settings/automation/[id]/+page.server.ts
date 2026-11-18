import { error, fail, redirect } from '@sveltejs/kit';
import {
  getCatalogue,
  getRule,
  listRules,
  updateRule,
  ruleFromForm,
  refusedSave,
  tryRule,
  switchOff,
  deleteRule,
  ruleGone
} from '#lib/server/v2/automation.js';
import { UUID } from '#lib/v2/custom-objects.js';
import { checkId } from '#lib/server/v2/custom-objects.js';
import { readableError } from '#lib/server/v2/form-errors.js';
import { m } from '#lib/paraglide/messages.js';
import { apiErrorBody, apiStatus } from '#lib/api-errors.js';
import type { Actions, PageServerLoad } from './$types';

const recordGone = () => m.settings_automation_record_gone();

function sentence(err: unknown, fallback: string) {
  const detail = apiErrorBody(err)?.detail;
  return typeof detail === 'string' ? detail : readableError(err, fallback);
}

function statusOf(err: unknown) {
  const status = apiStatus(err);
  return status !== undefined && Number.isInteger(status) && status >= 400 && status < 600
    ? status
    : 400;
}

/**
 * The rule beside its row from the list, since only the list computes a
 * status. The list goes first so a member is refused once, not three times.
 */
export const load: PageServerLoad = async (event) => {
  const { id } = event.params;
  if (!UUID.test(id)) error(404, ruleGone());
  const list = await listRules(event);
  if (list.forbidden) return { forbidden: true as const };
  const [catalogue, rule] = await Promise.all([getCatalogue(event), getRule(event, id)]);
  const row = (list.rules ?? []).find((r) => r.id === rule.id) ?? null;
  return { catalogue, rule, row };
};

export const actions: Actions = {
  async save(event) {
    const { id } = event.params;
    if (!UUID.test(id)) return fail(400, { save: { general: ruleGone(), rows: {} } });
    const form = await event.request.formData();
    try {
      const body = ruleFromForm(form, { create: false });
      if (form.get('switch_on') === 'true') body.is_active = true;
      await updateRule(event, id, body);
    } catch (err) {
      return refusedSave(err);
    }
    return { saved: true };
  },

  /** Plans the saved rule on one record; nothing is written. */
  async try(event) {
    const { id } = event.params;
    if (!UUID.test(id)) return fail(404, { tryError: ruleGone() });
    const form = await event.request.formData();
    const recordId = form.get('record_id');
    const name = form.get('record_name');
    let record: string;
    try {
      record = checkId(recordId);
    } catch {
      return fail(404, { tryError: recordGone() });
    }
    try {
      const steps = await tryRule(event, id, record);
      const recordName = typeof name === 'string' ? name.trim().slice(0, 120) : '';
      return { tried: { recordName, steps } };
    } catch (err) {
      if (apiStatus(err) === 404) return fail(404, { tryError: recordGone() });
      return fail(statusOf(err), { tryError: sentence(err, m.settings_automation_try_failed()) });
    }
  },

  async switchOff(event) {
    const { id } = event.params;
    if (!UUID.test(id)) return fail(400, { switchOff: { general: ruleGone() } });
    try {
      await switchOff(event, id);
    } catch (err) {
      return fail(statusOf(err), {
        switchOff: { general: sentence(err, m.settings_automation_switch_off_failed()) }
      });
    }
    return { switchedOff: true };
  },

  async remove(event) {
    const { id } = event.params;
    if (!UUID.test(id)) return fail(400, { remove: { general: ruleGone() } });
    try {
      await deleteRule(event, id);
    } catch (err) {
      return fail(statusOf(err), {
        remove: { general: sentence(err, m.settings_automation_delete_failed()) }
      });
    }
    redirect(303, '/settings/automation');
  }
};
