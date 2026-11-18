/**
 * Connected apps on screen, browser-safe. The navigation entry shows for an
 * admin where custom objects are offered (`data.customObjects` is not null).
 */
import { m } from '#lib/paraglide/messages.js';

export const CONNECTED_APPS_HREF = '/settings/connected-apps';

const RESOURCE_WORDS: Record<string, () => string> = {
  leads: () => m.settings_connected_apps_res_leads(),
  accounts: () => m.settings_connected_apps_res_accounts(),
  contacts: () => m.settings_connected_apps_res_contacts(),
  opportunities: () => m.settings_connected_apps_res_deals(),
  cases: () => m.settings_connected_apps_res_tickets(),
  tasks: () => m.settings_connected_apps_res_tasks(),
  time_entries: () => m.settings_connected_apps_res_time_entries(),
  objects: () => m.settings_connected_apps_res_objects(),
  hooks: () => m.settings_connected_apps_res_hooks()
};

const ACTION_WORDS: Record<string, () => string> = {
  read: () => m.settings_connected_apps_action_read(),
  write: () => m.settings_connected_apps_action_write()
};

const capital = (word: string) => word.charAt(0).toUpperCase() + word.slice(1);

/** `leads:read` as "Leads: read"; a string with no action is shown as it is. */
export function scopeLabel(scope: string): string {
  const [resource, action] = scope.split(':');
  const noun = Object.hasOwn(RESOURCE_WORDS, resource)
    ? RESOURCE_WORDS[resource]()
    : capital(resource.replace(/_/g, ' '));
  if (!action) return noun;
  const verb = Object.hasOwn(ACTION_WORDS, action) ? ACTION_WORDS[action]() : action;
  return m.settings_connected_apps_scope({ resource: noun, action: verb });
}

/** What an app named `name` is called on screen. */
export function kindLabel(kind: { kind: string; name: string | null }): string {
  return kind.name ?? m.settings_connected_apps_another_app();
}

export const MAX_APP_NAME = 60;

export const keyNotice = () => m.settings_connected_apps_key_notice();

export const replaceSentence = (name: string) =>
  m.settings_connected_apps_replace_confirm({ name });

export const disconnectSentence = (name: string) =>
  m.settings_connected_apps_disconnect_confirm({ name });

/** "Never" for an app that has made no request; otherwise `when` of the date. */
export const lastUsedLabel = (at: string | null, when: (at: string) => string) =>
  at ? when(at) : m.settings_connected_apps_never();
