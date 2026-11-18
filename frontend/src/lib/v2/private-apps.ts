/** Private apps on screen, browser-safe: the fixed copy and plain-word access. */
import { scopeLabel } from '#lib/v2/connected-apps.js';
import { m } from '#lib/paraglide/messages.js';

export const notReviewed = () => m.settings_private_apps_not_reviewed();
export const trustLabel = () => m.settings_private_apps_trust();

/** The consent screen's access block, as the preview sends it. */
export type Access = { scopes: string[]; added: string[]; removed: string[] };

/** The scopes the app held before: the new list, less what it adds, plus what it drops. */
export const previousScopes = (access: Access): string[] => [
  ...access.scopes.filter((s) => !access.added.includes(s)),
  ...access.removed
];

/** Whether applying keeps the app's key: an update of an app that already held access. */
export const keepsKey = (mode: string, access: Access): boolean =>
  mode === 'upgrade' && previousScopes(access).length > 0;

/** The removal confirmation, naming only what the app has. */
export function removeSentence(name: string, has: { objects: boolean; key: boolean }): string {
  const out = [m.settings_private_apps_remove_question({ name })];
  if (has.objects) out.push(m.settings_private_apps_remove_objects());
  if (has.key) out.push(m.settings_private_apps_remove_key());
  return out.join(' ');
}

const names = (scopes: string[], action: string) =>
  scopes
    .filter((s) => s.endsWith(`:${action}`))
    .map((s) => scopeLabel(s).replace(/: [^:]+$/, ''))
    .join(', ');

/**
 * What a set of approved scopes means, one sentence each. Empty for no access.
 * `keeps` is true when the app's existing key carries the new scopes.
 */
export function accessSentences(scopes: string[], keeps = false): string[] {
  if (!scopes.length) return [];
  const out: string[] = [];
  const reads = names(scopes, 'read');
  // Subscriptions are said in their own sentence below, not as a write.
  const writes = names(
    scopes.filter((s) => !s.startsWith('hooks:')),
    'write'
  );
  if (reads) out.push(m.settings_private_apps_may_read({ list: reads }));
  if (writes) out.push(m.settings_private_apps_may_write({ list: writes }));
  if (scopes.some((s) => s.startsWith('objects:'))) {
    out.push(m.settings_private_apps_objects_scope());
  }
  if (scopes.includes('hooks:write')) {
    out.push(m.settings_private_apps_hooks_scope());
  }
  out.push(keeps ? m.settings_private_apps_key_kept() : m.settings_private_apps_key_new());
  return out;
}

/** The custom objects line, or null when the app needs no new place. */
export function objectsLine(objects: { needed: number; included: number; used: number }) {
  if (!objects.needed) return null;
  return m.settings_private_apps_objects_line({
    needed: objects.needed,
    included: objects.included,
    count: objects.used
  });
}

/** The consent screen's first line: install, update or install again. */
export function modeLine(mode: string, version: number, installed: number | null): string {
  if (mode === 'upgrade') {
    return installed
      ? m.settings_private_apps_mode_update_from({ installed, version })
      : m.settings_private_apps_mode_update({ version });
  }
  if (mode === 'install_again') return m.settings_private_apps_mode_again({ version });
  return m.settings_private_apps_mode_install({ version });
}

/** The page title once the app is applied. */
export const appliedTitle = (mode: string) =>
  mode === 'upgrade' ? m.settings_private_apps_updated() : m.settings_private_apps_installed();

/**
 * What happened to the key when an apply returned none; empty when there is
 * nothing to say, as after an update of an app that never held access.
 */
export function noNewKeyLine(mode: string, asksAccess: boolean, hadAccess: boolean): string {
  if (mode !== 'upgrade') return m.settings_private_apps_no_key();
  if (!hadAccess) return '';
  return asksAccess
    ? m.settings_private_apps_key_kept_review()
    : m.settings_private_apps_key_stopped();
}
