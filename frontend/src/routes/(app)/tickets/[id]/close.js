/**
 * Closing a parent ticket, and what goes with it.
 *
 * `POST /cases/<id>/close-with-children/` closes the ticket and, when
 * `cascade` is true, every OPEN DESCENDANT of it. This module works out which
 * tickets those are, so the confirm step can name them before anything is
 * closed.
 *
 * **The tree endpoint does not return the ticket you are closing.** `GET
 * /cases/<id>/tree/` walks UP to the highest ancestor in the org and returns
 * that as `root`, with `focus_id` naming the ticket you asked about. So the
 * subtree that will actually be closed has to be found inside the response
 * first. A previous version of this feature (`CloseWithChildrenDialog.svelte`,
 * written, never wired to a button, deleted with this change) walked from
 * `root` and collected every open node except the focus. For a ticket that is
 * itself a child that listed its parent, its siblings and its cousins as
 * about to be closed, and none of them would have been. Overstating the blast
 * radius of a destructive action is worse than saying nothing.
 *
 * [openDescendants] mirrors `_open_descendants` in `cases/parent_views.py`
 * exactly, including the two things that are easy to get wrong:
 *
 * - a node counts only when it is open (neither Closed nor Duplicate) AND
 *   active, since a merged ticket's status is not the cascade's to change, and
 * - recursion goes through closed nodes anyway, so an open grandchild under a
 *   closed child is still cascaded.
 */

import { restrictedTicketName } from '#lib/v2/enums.js';
import { m } from '#lib/paraglide/messages.js';

/** Statuses a cascading close leaves alone: already closed, or merged away. */
const NOT_OPEN = ['Closed', 'Duplicate'];

/**
 * The node for `id` inside the tree, or null.
 *
 * @param {any} root
 * @param {string} id
 */
export function findNode(root, id) {
  if (!root || !id) return null;
  if (root.id === id) return root;
  for (const child of root.children ?? []) {
    const hit = findNode(child, id);
    if (hit) return hit;
  }
  return null;
}

/**
 * The tickets a cascading close would actually close.
 *
 * @param {any} root the tree response's `root`
 * @param {string} id the ticket being closed
 * @returns {Array<{id: string, name: string, status: string, restricted: boolean}>}
 */
export function openDescendants(root, id) {
  const focus = findNode(root, id);
  if (!focus) return [];

  /** @type {Array<{id: string, name: string, status: string, restricted: boolean}>} */
  const out = [];
  /** @param {any} node */
  const walk = (node) => {
    for (const child of node.children ?? []) {
      // Open AND active, matching `_open_descendants`: a Duplicate child was
      // merged away and an inactive one deleted, and the backend skips both.
      if (!NOT_OPEN.includes(child.status) && child.is_active !== false) {
        out.push({
          id: child.id,
          name: child.restricted ? restrictedTicketName() : child.name,
          status: child.status,
          restricted: Boolean(child.restricted)
        });
      }
      // Through closed children regardless: an open grandchild under a closed
      // child still cascades.
      walk(child);
    }
  };
  walk(focus);
  return out;
}

/**
 * True when the subtree hit the API's depth cap, so the list above is a floor
 * rather than the whole set.
 *
 * `_build_tree` stops at `Case.PARENT_MAX_DEPTH` and marks the node
 * `truncated`. The close itself has no such cap, so in that case more tickets
 * close than the confirm step can name, and it says so instead of implying a
 * complete list.
 *
 * @param {any} root
 * @param {string} id
 */
export function subtreeTruncated(root, id) {
  const focus = findNode(root, id);
  if (!focus) return false;
  /** @param {any} node @returns {boolean} */
  const walk = (node) =>
    Boolean(node.truncated) || (node.children ?? []).some((/** @type {any} */ c) => walk(c));
  return walk(focus);
}

/**
 * The line above the checkbox: what happens if it stays ticked.
 *
 * @param {{ count: number, truncated?: boolean }} args
 */
export function cascadeSummary({ count, truncated = false }) {
  if (count === 0) return m.tickets_detail_cascade_none();
  return truncated
    ? m.tickets_detail_cascade_open_truncated({ count })
    : m.tickets_detail_cascade_open({ count });
}

/**
 * What actually happened, from the response rather than from what was asked.
 *
 * The server returns `cascaded_case_ids`, the tickets it really closed. A
 * message built from the count on screen would claim a cascade that a
 * concurrent close had already made a no-op.
 *
 * @param {{ cascade: boolean, cascaded: number }} args
 */
export function closeResultMessage({ cascade, cascaded }) {
  if (!cascade) return m.tickets_detail_closed();
  if (cascaded === 0) return m.tickets_detail_closed_nothing_linked();
  return m.tickets_detail_closed_cascaded({ count: cascaded });
}

/**
 * How many tickets the response says were closed alongside.
 *
 * @param {any} body
 */
export function cascadedCount(body) {
  return (body?.cascaded_case_ids ?? []).length;
}
