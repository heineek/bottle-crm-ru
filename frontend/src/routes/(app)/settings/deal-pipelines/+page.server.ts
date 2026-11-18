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
import { apiStatus } from '#lib/api-errors.js';
import type { Actions, PageServerLoad } from './$types';

const KINDS = ['open', 'won', 'lost'];
const DAYS = /^\d{1,4}$/;

/** `?pipeline=<id>` picks whose stages are shown; see `getDealPipelines`. */
export const load: PageServerLoad = async ({ cookies, url }) => {
  return getDealPipelines({ cookies }, url.searchParams.get('pipeline'));
};

function readStage(form: FormData) {
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
 */
function stageProblem(values: ReturnType<typeof readStage>): string | null {
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
 */
async function attempt(key: string, fallback: string, write: () => Promise<unknown>) {
  try {
    await write();
  } catch (err) {
    if (apiStatus(err) === 403)
      return fail(403, { [key]: { error: m.settings_dealpipelines_error_admin_only() } });
    return fail(400, { [key]: { error: readableError(err, fallback) } });
  }
  return null;
}

export const actions: Actions = {
  async createPipeline(event) {
    const form = await event.request.formData();
    const name = form.get('name')?.toString().trim() ?? '';
    if (!name)
      return fail(400, {
        createPipeline: { error: m.settings_dealpipelines_error_pipeline_name() }
      });
    let createdId = '';
    const refused = await attempt(
      'createPipeline',
      m.settings_dealpipelines_error_create_pipeline(),
      async () => {
        createdId = (await createPipeline(event, { name })).id;
      }
    );
    if (refused) return refused;
    // Straight to the new pipeline, so its seeded stages are what is on screen.
    redirect(303, `/settings/deal-pipelines?pipeline=${encodeURIComponent(createdId)}`);
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
