import { fail } from '@sveltejs/kit';
import {
  listApprovals,
  approveApproval,
  rejectApproval,
  cancelApproval
} from '#lib/server/v2/approvals.js';
import { readableError } from '#lib/server/v2/form-errors.js';
import { m } from '#lib/paraglide/messages.js';
import { apiStatus } from '#lib/api-errors.js';
import type { Actions, PageServerLoad } from './$types';

/**
 * The approvals queue. `load` returns `{ approvals, totals, rules }`; the three
 * actions decide a request. Authorization (approver pool, separation of duties,
 * pending-only) is enforced by the backend. These actions just surface its
 * error. On success `use:enhance` re-runs `load`, so the row reflects the real
 * new state rather than an optimistic guess.
 */
export const load: PageServerLoad = async ({ cookies }) => {
  return await listApprovals({ cookies });
};

export const actions: Actions = {
  approve: async ({ cookies, request }) => {
    const form = await request.formData();
    const id = form.get('id')?.toString();
    if (!id) return fail(400, { error: m.tickets_approvals_missing_id() });
    try {
      await approveApproval({ cookies }, id, form.get('note')?.toString() || '');
    } catch (err) {
      return fail(apiStatus(err) === 403 ? 403 : 400, {
        error: readableError(err, m.tickets_approvals_approve_failed())
      });
    }
    return { approved: true };
  },

  reject: async ({ cookies, request }) => {
    const form = await request.formData();
    const id = form.get('id')?.toString();
    const reason = form.get('reason')?.toString()?.trim();
    if (!id) return fail(400, { error: m.tickets_approvals_missing_id() });
    if (!reason) return fail(400, { error: m.tickets_approvals_reason_required() });
    try {
      await rejectApproval({ cookies }, id, reason);
    } catch (err) {
      return fail(apiStatus(err) === 403 ? 403 : 400, {
        error: readableError(err, m.tickets_approvals_reject_failed())
      });
    }
    return { rejected: true };
  },

  cancel: async ({ cookies, request }) => {
    const form = await request.formData();
    const id = form.get('id')?.toString();
    if (!id) return fail(400, { error: m.tickets_approvals_missing_id() });
    try {
      await cancelApproval({ cookies }, id);
    } catch (err) {
      return fail(apiStatus(err) === 403 ? 403 : 400, {
        error: readableError(err, m.tickets_approvals_withdraw_failed())
      });
    }
    return { cancelled: true };
  }
};
