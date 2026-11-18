/**
 * How an entry from `GET /api/org/audit-log/` reads on the page.
 *
 * The API sends only allow-listed `details` keys (ids, counts, and sentences
 * the server wrote), never the stored description, so every string built here
 * comes from those.
 */
import { m } from '#lib/paraglide/messages.js';

/**
 * Who the entry is about: a name, else an email. An entry with no person is a
 * system event, or one whose user has since been deleted.
 */
export function auditActor(entry: { actor?: { name?: string; email?: string } | null }) {
  const a = entry?.actor;
  if (!a) return m.settings_audit_no_user();
  return a.name || a.email || m.settings_audit_no_user();
}

/** One line on what happened, or '' when the event label says it all. */
export function auditDetail(entry: {
  event_type?: string;
  actor?: { id?: string } | null;
  details?: Record<string, unknown> | null;
}) {
  const d = entry?.details ?? {};
  if (d.pause_reason) return String(d.pause_reason);
  if (entry?.event_type === 'RECORD_MERGED' && d.merged_name !== undefined) {
    // Duplicates usually share a name, and "X into X" says nothing, so equal
    // names each carry the start of their id.
    const same = d.merged_name === d.kept_name;
    const tag = (id: unknown) => (same && id ? ` (${String(id).slice(0, 8)})` : '');
    return m.settings_audit_merged({
      entity: String(d.entity || m.settings_audit_merged_record()),
      merged: String(d.merged_name),
      mergedTag: tag(d.merged_id),
      kept: String(d.kept_name),
      keptTag: tag(d.kept_id)
    });
  }
  if (
    (entry?.event_type === 'API_TOKEN_CREATED' || entry?.event_type === 'API_TOKEN_REVOKED') &&
    d.token_prefix
  ) {
    // An empty scope list is a token with the owner's full access. The owner
    // is named only when someone else acted: an admin revoking their token.
    const scopes = Array.isArray(d.scopes) ? d.scopes : [];
    const scoped = scopes.length > 0;
    const values = {
      name: String(d.token_name ?? ''),
      prefix: String(d.token_prefix),
      scopes: scopes.join(', '),
      owner: String(d.owner_name ?? '')
    };
    if (d.owner_id && d.owner_id !== entry?.actor?.id) {
      return scoped
        ? m.settings_audit_token_scoped_owned(values)
        : m.settings_audit_token_full_owned(values);
    }
    return scoped ? m.settings_audit_token_scoped(values) : m.settings_audit_token_full(values);
  }
  if (entry?.event_type === 'WEBHOOK_REENABLED') {
    return m.settings_audit_webhook_reenabled();
  }
  if (entry?.event_type === 'WEBHOOK_CHANGED' && Array.isArray(d.changed)) {
    return m.settings_audit_webhook_changed({ fields: d.changed.join(', ') });
  }
  if (d.action && d.resource) {
    return m.settings_audit_action_on({ action: d.action, resource: d.resource });
  }
  if (d.deleted_count !== undefined && d.deleted_count !== null) {
    return m.settings_audit_sample_removed({ count: Number(d.deleted_count) });
  }
  return '';
}

/** The webhook an entry is about, for a link, or null. */
export function auditWebhookId(entry: { details?: Record<string, unknown> | null }): string | null {
  const id = entry?.details?.endpoint_id;
  return typeof id === 'string' && id ? id : null;
}
