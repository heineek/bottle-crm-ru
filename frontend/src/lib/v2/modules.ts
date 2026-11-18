/**
 * Which modules an org has switched off, and what that means for a route.
 *
 * Browser-safe: no server or framework imports. "On" has one definition,
 * `isOn`: a missing list or a missing row reads as on, so an older API that
 * does not serve the list changes nothing. A module in `NEEDS_ROW` is newer
 * than the list itself, so a list without its row comes from an API that
 * has no such module, and it reads as off. The server refuses an off module
 * regardless; this only decides what to show.
 */
import { m } from '#lib/paraglide/messages.js';

/** One row of `GET /org/modules/`. */
export type ModuleRow = {
  key: string;
  label: string;
  group: 'sell' | 'serve' | 'bill';
  covers: string;
  stops: string;
  enabled: boolean;
  available: boolean;
  needs: string | null;
};

type Requirement = { all: string[] } | { anyOf: string[] };

export const MODULE_KEYS = [
  'deals',
  'leads',
  'goals',
  'tasks',
  'projects',
  'tickets',
  'knowledge_base',
  'documents',
  'invoices',
  'timesheet'
];

export const DEFAULT_LABELS: Record<string, string> = {
  get deals() {
    return m.app_modules_label_deals();
  },
  get leads() {
    return m.app_modules_label_leads();
  },
  get goals() {
    return m.app_modules_label_goals();
  },
  get tasks() {
    return m.app_modules_label_tasks();
  },
  get projects() {
    return m.app_modules_label_projects();
  },
  get tickets() {
    return m.app_modules_label_tickets();
  },
  get knowledge_base() {
    return m.app_modules_label_knowledge_base();
  },
  get documents() {
    return m.app_modules_label_documents();
  },
  get invoices() {
    return m.app_modules_label_invoices();
  },
  get timesheet() {
    return m.app_modules_label_timesheet();
  }
};

/** Record kinds a page can show, by the module that serves them. */
export const OBJECT_MODULES = {
  lead: 'leads',
  deal: 'deals',
  ticket: 'tickets',
  task: 'tasks'
} as Record<string, string>;

/** Custom field targets, by the module that serves them. */
export const TARGET_MODULES = {
  Lead: 'leads',
  Opportunity: 'deals',
  Case: 'tickets',
  Task: 'tasks',
  Project: 'projects',
  Invoice: 'invoices',
  Estimate: 'invoices',
  RecurringInvoice: 'invoices'
} as Record<string, string>;

/** Modules an API serves only if it lists them. */
const NEEDS_ROW = ['projects'];

export function isOn(modules: ModuleRow[] | null | undefined, key: string): boolean {
  if (!Array.isArray(modules)) return true;
  const row = modules.find((m) => m.key === key);
  return row ? row.available !== false : !NEEDS_ROW.includes(key);
}

/** Products are served while deals or invoices is on. */
export function productsOn(modules: ModuleRow[] | null | undefined): boolean {
  return isOn(modules, 'deals') || isOn(modules, 'invoices');
}

/**
 * Inbound mailboxes are served while tickets or leads is on, since an address
 * makes one or the other.
 */
export function mailboxesOn(modules: ModuleRow[] | null | undefined): boolean {
  return isOn(modules, 'tickets') || isOn(modules, 'leads');
}

export function labelOf(modules: ModuleRow[] | null | undefined, key: string): string {
  const row = Array.isArray(modules) ? modules.find((m) => m.key === key) : undefined;
  return row?.label || DEFAULT_LABELS[key] || key;
}

const ROUTES: Record<string, Requirement> = {
  '/leads': { all: ['leads'] },
  '/settings/lead-pipelines': { all: ['leads'] },
  '/settings/lead-capture': { all: ['leads'] },
  '/pipeline': { all: ['deals'] },
  '/settings/deal-pipelines': { all: ['deals'] },
  '/goals': { all: ['goals'] },
  '/tasks': { all: ['tasks'] },
  '/projects': { all: ['projects'] },
  '/profile/calendar-feed': { all: ['tasks'] },
  '/tickets': { all: ['tickets'] },
  '/settings/routing': { all: ['tickets'] },
  '/settings/escalation': { all: ['tickets'] },
  '/settings/business-hours': { all: ['tickets'] },
  '/settings/ticket-approvals': { all: ['tickets'] },
  '/settings/reopen': { all: ['tickets'] },
  '/settings/inbound-email': { anyOf: ['tickets', 'leads'] },
  '/settings/macros': { all: ['tickets'] },
  '/solutions': { all: ['knowledge_base'] },
  '/settings/help-center': { all: ['knowledge_base'] },
  '/timesheet': { all: ['timesheet'] },
  '/invoices': { all: ['invoices'] },
  '/accounts/[id]/statement': { all: ['invoices'] },
  '/invoices/products': { anyOf: ['invoices', 'deals'] },
  '/documents': { all: ['documents'] }
};

/**
 * What a route needs switched on, or null for a core route.
 *
 * @param routeId SvelteKit's `route.id`, groups allowed
 */
export function requirementFor(routeId: string | null | undefined): Requirement | null {
  if (!routeId) return null;
  const path = routeId.replace(/\/\([^/)]*\)/g, '');
  let best = '';
  for (const prefix of Object.keys(ROUTES)) {
    if ((path === prefix || path.startsWith(prefix + '/')) && prefix.length > best.length) {
      best = prefix;
    }
  }
  return best ? ROUTES[best] : null;
}

/** The module a route is waiting on, or null when it can be shown. */
export function refusalFor(
  routeId: string | null | undefined,
  modules: ModuleRow[] | null | undefined
): { key: string; label: string } | null {
  const need = requirementFor(routeId);
  if (!need) return null;
  let key;
  if ('all' in need) key = need.all.find((k) => !isOn(modules, k));
  else if (!need.anyOf.some((k) => isOn(modules, k))) key = need.anyOf[0];
  return key ? { key, label: labelOf(modules, key) } : null;
}

/** What Today says it is clear of, naming only the modules that are on. */
export function todayClearText(modules: ModuleRow[] | null | undefined): string {
  // The first noun that can be late carries "overdue"; quiet deals are never late.
  const nouns: [string, () => string, (() => string) | null][] = [
    ['tickets', m.app_modules_clear_tickets, m.app_modules_clear_overdue_tickets],
    ['invoices', m.app_modules_clear_invoices, m.app_modules_clear_overdue_invoices],
    ['deals', m.app_modules_clear_quiet_deals, null],
    ['tasks', m.app_modules_clear_tasks, m.app_modules_clear_overdue_tasks]
  ];
  const on = nouns.filter(([key]) => isOn(modules, key));
  if (!on.length) return m.app_modules_clear_nothing();
  const first = on.findIndex(([, , overdue]) => overdue !== null);
  const parts = on.map(([, plain, overdue], i) => (i === first && overdue ? overdue() : plain()));
  const list =
    parts.length === 1
      ? parts[0]
      : m.app_modules_list_or({
          rest: parts.slice(0, -1).join(', '),
          last: parts[parts.length - 1]
        });
  return m.app_modules_clear_none_of({ list });
}

/** The empty notifications line; ticket activity is named only while Tickets is on. */
export function notificationsEmptyText(modules: ModuleRow[] | null | undefined): string {
  return isOn(modules, 'tickets')
    ? m.app_modules_notifications_empty_tickets()
    : m.app_modules_notifications_empty();
}

/**
 * The words whose module is on, joined as prose: "a, b and c". A word keyed
 * `null` belongs to no module and always stays.
 *
 * @param words each a module key and its word
 * @param last what joins the final two
 * @returns '' when every word's module is off
 */
export function wordsOn(
  modules: ModuleRow[] | null | undefined,
  words: [string | null, string][],
  last: string = m.app_modules_list_and()
): string {
  const kept = words.filter(([key]) => key === null || isOn(modules, key)).map(([, word]) => word);
  if (kept.length < 2) return kept[0] ?? '';
  return `${kept.slice(0, -1).join(', ')} ${last} ${kept[kept.length - 1]}`;
}
