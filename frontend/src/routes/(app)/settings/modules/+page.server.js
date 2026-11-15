import { fail } from '@sveltejs/kit';
import {
  getModules,
  moduleErrors,
  moveBody,
  putModules,
  switchBody
} from '#lib/server/v2/modules.js';
import { m } from '#lib/paraglide/messages.js';

/** @type {import('./$types').PageServerLoad} */
export async function load(event) {
  const answer = await getModules(event);
  if (!answer) return { failed: true };
  if (!answer.canEdit) return { forbidden: true };
  return { modules: answer.modules };
}

/**
 * Re-reads the list, builds the body from it and writes it.
 *
 * @param {any} event
 * @param {string} key
 * @param {(rows: import('#lib/v2/modules.js').ModuleRow[]) => { off: string[], order: string[] } | null} build
 */
async function write(event, key, build) {
  const answer = await getModules(event);
  if (!answer) return fail(400, { errors: [m.settings_modules_failed_title()], key });
  if (!answer.canEdit) {
    return fail(403, { errors: [m.settings_modules_forbidden()], key });
  }
  const body = build(answer.modules);
  if (!body) return fail(400, { errors: [m.settings_modules_not_changed()], key });
  try {
    await putModules(event, body);
  } catch (/** @type {any} */ err) {
    return fail(err?.status === 403 ? 403 : 400, { errors: moduleErrors(err), key });
  }
  return { saved: true };
}

/** @type {import('./$types').Actions} */
export const actions = {
  async switch(event) {
    const form = await event.request.formData();
    const key = form.get('key')?.toString() ?? '';
    const on = form.get('on')?.toString();
    if (on !== 'true' && on !== 'false') {
      return fail(400, { errors: [m.settings_modules_not_changed()], key });
    }
    return write(event, key, (rows) => switchBody(rows, key, on === 'true'));
  },

  async move(event) {
    const form = await event.request.formData();
    const key = form.get('key')?.toString() ?? '';
    const direction = form.get('direction')?.toString() ?? '';
    return write(event, key, (rows) => moveBody(rows, key, direction));
  }
};
