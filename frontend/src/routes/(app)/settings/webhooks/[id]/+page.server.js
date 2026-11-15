import { error, fail, redirect } from '@sveltejs/kit';
import {
  getWebhook,
  updateWebhook,
  deleteWebhook,
  testWebhook,
  rotateWebhookSecret,
  redeliverWebhook,
  eventsFromForm
} from '#lib/server/v2/webhooks.js';
import { readableError } from '#lib/server/v2/form-errors.js';
import { m } from '#lib/paraglide/messages.js';

/**
 * One webhook: its settings, its actions and a page of its delivery log.
 *
 * A 404 means the id belongs to another org or to nothing, and is the answer.
 * A 403 is a member, who gets the same "admins only" state as the list.
 *
 * @type {import('./$types').PageServerLoad}
 */
export async function load(event) {
  const offset = Math.max(0, Number.parseInt(event.url.searchParams.get('offset') ?? '0', 10) || 0);
  try {
    return { forbidden: false, ...(await getWebhook(event, event.params.id, offset)) };
  } catch (/** @type {any} */ err) {
    if (err?.status === 404) error(404, m.settings_webhooks_not_found());
    if (err?.status === 403) return { forbidden: true };
    throw err;
  }
}

/**
 * Turn an API refusal into the sentence the page shows, under `key`.
 * @param {string} key @param {any} err @param {string} fallback
 */
function refused(key, err, fallback) {
  if (err?.status === 403) {
    return fail(403, { [key]: { error: m.settings_webhooks_change_forbidden() } });
  }
  return fail(400, { [key]: { error: readableError(err, fallback) } });
}

/** @type {import('./$types').Actions} */
export const actions = {
  async update(event) {
    const form = await event.request.formData();
    const values = {
      url: form.get('url')?.toString().trim() ?? '',
      description: form.get('description')?.toString().trim() ?? '',
      format: form.get('format')?.toString() ?? 'json',
      events: eventsFromForm(form)
    };
    if (!values.events.length) {
      return fail(400, { update: { error: m.settings_webhooks_events_required() } });
    }
    try {
      await updateWebhook(event, event.params.id, values);
    } catch (err) {
      return refused('update', err, m.settings_webhooks_save_failed());
    }
    return { updated: true };
  },

  // Its own action carrying only `is_active`, so switching an endpoint on or
  // off can never send a half-empty settings body along with it.
  async toggle(event) {
    const form = await event.request.formData();
    const isActive = form.get('is_active') === 'true';
    try {
      await updateWebhook(event, event.params.id, { is_active: isActive });
    } catch (err) {
      return refused('toggle', err, m.settings_webhooks_toggle_failed());
    }
    return { toggled: true };
  },

  async test(event) {
    try {
      await testWebhook(event, event.params.id);
    } catch (err) {
      return refused('test', err, m.settings_webhooks_test_failed());
    }
    return { tested: true };
  },

  async rotate(event) {
    try {
      const res = await rotateWebhookSecret(event, event.params.id);
      return { rotated: { secret: res.secret } };
    } catch (err) {
      return refused('rotate', err, m.settings_webhooks_rotate_failed());
    }
  },

  async redeliver(event) {
    const form = await event.request.formData();
    const deliveryId = form.get('delivery_id')?.toString() ?? '';
    try {
      await redeliverWebhook(event, deliveryId);
    } catch (err) {
      return refused('redeliver', err, m.settings_webhooks_redeliver_failed());
    }
    return { redelivered: true };
  },

  async remove(event) {
    try {
      await deleteWebhook(event, event.params.id);
    } catch (err) {
      return refused('remove', err, m.settings_webhooks_delete_failed());
    }
    redirect(303, '/settings/webhooks');
  }
};
