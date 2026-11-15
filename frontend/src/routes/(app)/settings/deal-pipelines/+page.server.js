import { fail, redirect } from '@sveltejs/kit';
import {
  getDealPipelines,
  createPipeline,
  renamePipeline,
  deletePipeline,
  createStage,
  updateStage,
  deleteStage,
  moveStage
} from '#lib/server/v2/deal-pipelines.js';
import { readableError } from '#lib/server/v2/form-errors.js';
import { m } from '#lib/paraglide/messages.js';

const KINDS = ['open', 'won', 'lost'];
const DAYS = /^\d{1,4}$/;

/**
 * `?pipeline=<id>` picks whose stages are shown; see `getDealPipelines`.
 *
 * @type {import('./$types').PageServerLoad}
 */
export async function load({ cookies, url }) {
  return getDealPipelines({ cookies }, url.searchParams.get('pipeline'));
}

/** @param {FormData} form */
function readStage(form) {
  return {
    label: form.get('label')?.toString().trim() ?? '',
    kind: form.get('kind')?.toString() ?? 'open',
    expectedDays: form.get('expected_days')?.toString().trim() ?? '',
    warningDays: form.get('warning_days')?.toString().trim() ?? ''
  };
}

/**
 * The form's own checks, a UX hint: the serializer applies the same rules and
 * is what decides.
 *
 * @param {ReturnType<typeof readStage>} values
 * @returns {string | null}
 */
function stageProblem(values) {
  if (!values.label) return m.settings_dealpipelines_error_stage_name();
  if (!KINDS.includes(values.kind)) return m.settings_dealpipelines_error_kind();
  for (const days of [values.expectedDays, values.warningDays]) {
    if (days !== '' && (!DAYS.test(days) || Number(days) < 1 || Number(days) > 3650)) {
      return m.settings_dealpipelines_error_days();
    }
  }
  return null;
}

/**
 * Run one write and turn its refusal into a sentence under `key`. Every write
 * here is admin-only in `opportunity/views/pipeline_views.py`; `can_edit` only
 * hides the controls, so a 403 is still answered with a sentence rather than
 * the raw backend string.
 *
 * @param {string} key
 * @param {string} fallback
 * @param {() => Promise<any>} write
 */
async function attempt(key, fallback, write) {
  try {
    await write();
  } catch (/** @type {any} */ err) {
    if (err?.status === 403)
      return fail(403, { [key]: { error: m.settings_dealpipelines_error_admin_only() } });
    return fail(400, { [key]: { error: readableError(err, fallback) } });
  }
  return null;
}

/** @type {import('./$types').Actions} */
export const actions = {
  async createPipeline(event) {
    const form = await event.request.formData();
    const name = form.get('name')?.toString().trim() ?? '';
    if (!name)
      return fail(400, {
        createPipeline: { error: m.settings_dealpipelines_error_pipeline_name() }
      });
    /** @type {any} */
    let created = null;
    const refused = await attempt(
      'createPipeline',
      m.settings_dealpipelines_error_create_pipeline(),
      async () => {
        created = await createPipeline(event, { name });
      }
    );
    if (refused) return refused;
    // Straight to the new pipeline, so its seeded stages are what is on screen.
    redirect(303, `/settings/deal-pipelines?pipeline=${encodeURIComponent(created.id)}`);
  },

  async renamePipeline(event) {
    const form = await event.request.formData();
    const id = form.get('id')?.toString() ?? '';
    const name = form.get('name')?.toString().trim() ?? '';
    if (!id || !name)
      return fail(400, {
        renamePipeline: { error: m.settings_dealpipelines_error_pipeline_name() }
      });
    return (
      (await attempt('renamePipeline', m.settings_dealpipelines_error_rename_pipeline(), () =>
        renamePipeline(event, id, { name })
      )) ?? { renamed: true }
    );
  },

  async deletePipeline(event) {
    const form = await event.request.formData();
    const id = form.get('id')?.toString() ?? '';
    if (!id)
      return fail(400, {
        deletePipeline: { error: m.settings_dealpipelines_error_pipeline_unknown() }
      });
    const refused = await attempt(
      'deletePipeline',
      m.settings_dealpipelines_error_delete_pipeline(),
      () => deletePipeline(event, id)
    );
    if (refused) return refused;
    // Its `?pipeline=` id is gone now, so land on the default without it.
    redirect(303, '/settings/deal-pipelines');
  },

  async createStage(event) {
    const form = await event.request.formData();
    const pipelineId = form.get('pipeline_id')?.toString() ?? '';
    const values = readStage(form);
    const problem = pipelineId
      ? stageProblem(values)
      : m.settings_dealpipelines_error_pipeline_unknown();
    if (problem) return fail(400, { stage: { error: problem } });
    return (
      (await attempt('stage', m.settings_dealpipelines_error_add_stage(), () =>
        createStage(event, pipelineId, values)
      )) ?? { saved: true }
    );
  },

  async updateStage(event) {
    const form = await event.request.formData();
    const id = form.get('id')?.toString() ?? '';
    const values = readStage(form);
    const problem = id ? stageProblem(values) : m.settings_dealpipelines_error_stage_unknown();
    if (problem) return fail(400, { stage: { error: problem } });
    return (
      (await attempt('stage', m.settings_dealpipelines_error_save_stage(), () =>
        updateStage(event, id, values)
      )) ?? {
        saved: true
      }
    );
  },

  async deleteStage(event) {
    const form = await event.request.formData();
    const id = form.get('id')?.toString() ?? '';
    if (!id)
      return fail(400, { stageList: { error: m.settings_dealpipelines_error_stage_unknown() } });
    return (
      (await attempt('stageList', m.settings_dealpipelines_error_delete_stage(), () =>
        deleteStage(event, id)
      )) ?? {
        deleted: true
      }
    );
  },

  async moveStage(event) {
    const form = await event.request.formData();
    const pipelineId = form.get('pipeline_id')?.toString() ?? '';
    const id = form.get('id')?.toString() ?? '';
    const direction = form.get('direction')?.toString();
    if (!pipelineId || !id || (direction !== 'up' && direction !== 'down')) {
      return fail(400, { stageList: { error: m.settings_dealpipelines_error_stage_move() } });
    }
    return (
      (await attempt('stageList', m.settings_dealpipelines_error_reorder(), () =>
        moveStage(event, pipelineId, id, direction)
      )) ?? { moved: true }
    );
  }
};
