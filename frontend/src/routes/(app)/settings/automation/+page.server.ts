import { fail } from '@sveltejs/kit';
import { getCatalogue, listRules, moveRule, reorderRules } from '#lib/server/v2/automation.js';
import { UUID } from '#lib/v2/custom-objects.js';
import { readableError } from '#lib/server/v2/form-errors.js';
import { m } from '#lib/paraglide/messages.js';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ cookies }) => {
  const answer = await listRules({ cookies });
  if (answer.forbidden) return { forbidden: true as const };
  return {
    summary: answer.summary,
    rules: answer.rules,
    catalogue: await getCatalogue({ cookies })
  };
};

export const actions: Actions = {
  async move(event) {
    const form = await event.request.formData();
    const id = form.get('id')?.toString() ?? '';
    const direction = form.get('direction')?.toString() ?? '';
    if ((direction !== 'up' && direction !== 'down') || !UUID.test(id)) {
      return fail(400, { error: m.settings_automation_move_failed() });
    }
    try {
      const answer = await listRules(event);
      if (answer.forbidden) return fail(403, { error: m.settings_automation_reorder_admin_only() });
      const next = moveRule(
        (answer.rules ?? []).map((r) => r.id),
        id,
        direction
      );
      if (!next) return fail(400, { error: m.settings_automation_move_failed() });
      await reorderRules(event, next);
    } catch (err) {
      return fail(400, { error: readableError(err, m.settings_automation_reorder_failed()) });
    }
    return { moved: true };
  }
};
