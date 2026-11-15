import { fail } from '@sveltejs/kit';
import { getSupportTicket, replyToSupportTicket } from '#lib/server/v2/support.js';
import { readableError } from '#lib/server/v2/form-errors.js';
import { m } from '#lib/paraglide/messages.js';

/** @type {import('./$types').PageServerLoad} */
export async function load({ cookies, params }) {
  return { ticket: await getSupportTicket({ cookies }, params.id) };
}

/** @type {import('./$types').Actions} */
export const actions = {
  reply: async ({ cookies, params, request }) => {
    const form = await request.formData();
    const body = form.get('body')?.toString().trim() ?? '';
    const picked = form.get('attachment');
    const attachment =
      picked && typeof picked === 'object' && 'size' in picked && picked.size > 0 ? picked : null;
    if (!body && !attachment) {
      return fail(400, { body, error: m.help_reply_empty() });
    }
    try {
      await replyToSupportTicket({ cookies }, params.id, { body, attachment });
      return { sent: true };
    } catch (/** @type {any} */ error) {
      return fail(400, {
        body,
        error: readableError(error, m.help_reply_failed())
      });
    }
  }
};
