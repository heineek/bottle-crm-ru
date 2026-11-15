/**
 * Every menu the shell draws, as data. Icons are lucide export names; the
 * components map them to the imported components. A module's items vanish
 * when it is switched off, and the server refuses its routes regardless.
 */
import { MODULE_KEYS, isOn } from '#lib/v2/modules.js';
import { t } from '#lib/terminology.js';
import { m } from '#lib/paraglide/messages.js';

/**
 * @typedef {{ href: string, label: string, icon: string, count?: string, exact?: boolean }} NavItem
 * @typedef {import('#lib/v2/modules.js').ModuleRow} ModuleRow
 */

// Labels are functions so each request reads its own locale. A group's
// `label` below is its code; the heading comes from GROUP_LABEL.
const GROUP_LABEL = {
  Sell: () => m.app_nav_group_sell(),
  Serve: () => m.app_nav_group_serve(),
  Bill: () => m.app_nav_group_bill(),
  Run: () => m.app_nav_group_run()
};

/** Sidebar item for each module, with the group it sits in. */
const MODULE_ITEMS = {
  deals: {
    group: 'Sell',
    item: {
      href: '/pipeline',
      label: () => m.app_nav_pipeline(),
      icon: 'Columns3',
      count: 'pipeline',
      termKey: 'opportunity.plural'
    }
  },
  leads: {
    group: 'Sell',
    item: {
      href: '/leads',
      label: () => m.app_nav_leads(),
      icon: 'Target',
      count: 'leads',
      termKey: 'lead.plural'
    }
  },
  goals: {
    group: 'Sell',
    item: { href: '/goals', label: () => m.app_nav_goals(), icon: 'Trophy' }
  },
  tasks: {
    group: 'Serve',
    item: { href: '/tasks', label: () => m.app_nav_tasks(), icon: 'CircleCheck', count: 'tasks' }
  },
  tickets: {
    group: 'Serve',
    item: { href: '/tickets', label: () => m.app_nav_tickets(), icon: 'LifeBuoy', count: 'tickets' }
  },
  knowledge_base: {
    group: 'Serve',
    item: { href: '/solutions', label: () => m.app_nav_knowledge_base(), icon: 'BookOpen' }
  },
  documents: {
    group: 'Serve',
    item: { href: '/documents', label: () => m.app_nav_documents(), icon: 'FileText' }
  },
  invoices: {
    group: 'Bill',
    item: {
      href: '/invoices',
      label: () => m.app_nav_invoices(),
      icon: 'Receipt',
      count: 'invoices',
      termKey: 'invoice.plural'
    }
  },
  timesheet: {
    group: 'Bill',
    item: { href: '/timesheet', label: () => m.app_nav_timesheet(), icon: 'Clock' }
  }
};

/**
 * Module keys in the org's order: the rows' order, then any key the list
 * does not carry. A null list is the default order.
 *
 * @param {ModuleRow[] | null | undefined} modules
 * @returns {string[]}
 */
function orderedKeys(modules) {
  const fromRows = Array.isArray(modules) ? modules.map((m) => m.key) : [];
  const known = fromRows.filter((k) => MODULE_KEYS.includes(k));
  return [...known, ...MODULE_KEYS.filter((k) => !known.includes(k))];
}

/**
 * The sidebar's groups, without the Objects group.
 *
 * @param {ModuleRow[] | null | undefined} modules
 * @param {{ isAdmin?: boolean, terminology?: Record<string, string> | null }} [opts]
 * @returns {{ label: string, items: NavItem[] }[]}
 */
export function sidebarGroups(modules, { isAdmin = false, terminology = undefined } = {}) {
  const keys = orderedKeys(modules).filter((k) => isOn(modules, k));
  /** @param {string} group */
  const moduleItems = (group) =>
    keys
      .map((k) => MODULE_ITEMS[k])
      .filter((m) => m.group === group)
      .map((m) => m.item);

  const groups = [
    {
      label: 'Sell',
      items: [
        { href: '/', label: () => m.app_nav_today(), icon: 'Sun', exact: true },
        ...moduleItems('Sell'),
        {
          href: '/accounts',
          label: () => m.app_nav_accounts(),
          icon: 'Building2',
          termKey: 'account.plural'
        },
        {
          href: '/contacts',
          label: () => m.app_nav_contacts(),
          icon: 'Users',
          termKey: 'contact.plural'
        }
      ]
    },
    { label: 'Serve', items: moduleItems('Serve') },
    { label: 'Bill', items: moduleItems('Bill') },
    {
      label: 'Run',
      items: [
        { href: '/team', label: () => m.app_nav_team(), icon: 'UserCog', admin: true },
        { href: '/settings', label: () => m.common_settings(), icon: 'SlidersHorizontal' }
      ]
    }
  ];

  return groups
    .map((group) => ({
      label: GROUP_LABEL[/** @type {keyof typeof GROUP_LABEL} */ (group.label)](),
      items: group.items
        .filter((item) => isAdmin || !('admin' in item && item.admin))
        .map((item) => {
          const { termKey, admin: _admin, ...rest } = /** @type {any} */ (item);
          const label = rest.label();
          return { ...rest, label: termKey ? t(terminology, termKey, label) : label };
        })
    }))
    .filter((group) => group.items.length > 0);
}

/** Tab bar candidates after Today, in priority order. */
const TAB_CANDIDATES = [
  {
    key: 'deals',
    href: '/pipeline',
    label: () => m.app_nav_pipeline(),
    icon: 'Columns3',
    termKey: 'opportunity.plural'
  },
  { key: 'tickets', href: '/tickets', label: () => m.app_nav_tickets(), icon: 'LifeBuoy' },
  {
    key: 'invoices',
    href: '/invoices',
    label: () => m.app_nav_invoices(),
    icon: 'Receipt',
    termKey: 'invoice.plural'
  },
  {
    key: 'leads',
    href: '/leads',
    label: () => m.app_nav_leads(),
    icon: 'Target',
    termKey: 'lead.plural'
  },
  { key: 'tasks', href: '/tasks', label: () => m.app_nav_tasks(), icon: 'CircleCheck' }
];

/**
 * Today, then the first three candidates that are on.
 *
 * @param {ModuleRow[] | null | undefined} modules
 * @param {Record<string, string> | null | undefined} [terminology]
 * @returns {NavItem[]}
 */
export function tabBar(modules, terminology) {
  const rest = TAB_CANDIDATES.filter((c) => isOn(modules, c.key))
    .slice(0, 3)
    .map(({ href, label, icon, termKey }) => ({
      href,
      label: termKey ? t(terminology, termKey, label()) : label(),
      icon
    }));
  return [{ href: '/', label: m.app_nav_today(), icon: 'Sun', exact: true }, ...rest];
}

const FAB_CANDIDATES = [
  { key: 'deals', href: '/pipeline/new', label: () => m.app_nav_new_deal(), icon: 'Plus' },
  { key: 'tickets', href: '/tickets/new', label: () => m.app_nav_new_ticket(), icon: 'Plus' },
  { key: 'leads', href: '/leads/new', label: () => m.app_nav_new_lead(), icon: 'Plus' },
  { key: 'tasks', href: '/tasks/new', label: () => m.app_nav_new_task(), icon: 'Plus' }
];

/**
 * The floating button: the first candidate whose module is on, or null.
 *
 * @param {ModuleRow[] | null | undefined} modules
 * @returns {{ href: string, label: string, icon: string } | null}
 */
export function fabAction(modules) {
  const hit = FAB_CANDIDATES.find((c) => isOn(modules, c.key));
  return hit ? { href: hit.href, label: hit.label(), icon: hit.icon } : null;
}

/**
 * The palette's actions before anything is typed.
 *
 * @param {ModuleRow[] | null | undefined} modules
 */
export function paletteActions(modules) {
  const all = [
    {
      module: 'deals',
      id: 'act-deal',
      title: m.app_nav_new_deal(),
      meta: m.app_nav_pipeline(),
      href: '/pipeline/new',
      icon: 'Plus'
    },
    {
      module: null,
      id: 'act-today',
      title: m.app_palette_go_today(),
      meta: '',
      href: '/',
      icon: 'Columns3'
    },
    {
      module: 'tasks',
      id: 'act-tasks',
      title: m.app_palette_go_tasks(),
      meta: '',
      href: '/tasks',
      icon: 'Columns3'
    },
    {
      module: 'invoices',
      id: 'act-invoices',
      title: m.app_palette_go_invoices(),
      meta: '',
      href: '/invoices',
      icon: 'Receipt'
    }
  ];
  return all
    .filter((a) => !a.module || isOn(modules, a.module))
    .map(({ module: _m, ...a }) => ({ kind: 'Actions', ...a }));
}

/**
 * @param {ModuleRow[] | null | undefined} modules
 * @returns {string}
 */
export function searchPlaceholder(modules) {
  const words = [
    isOn(modules, 'deals') && m.app_palette_word_deals(),
    m.app_palette_word_accounts(),
    m.app_palette_word_people(),
    isOn(modules, 'tickets') && m.app_palette_word_tickets(),
    isOn(modules, 'invoices') && m.app_palette_word_invoices()
  ].filter(Boolean);
  return m.app_palette_search_placeholder({ list: words.join(', ') });
}

/**
 * @param {string} query
 * @param {ModuleRow[] | null | undefined} modules
 * @returns {string}
 */
export function noHitsText(query, modules) {
  const deals = isOn(modules, 'deals');
  const invoices = isOn(modules, 'invoices');
  if (deals && invoices) return m.app_palette_no_hits_all({ query });
  if (deals) return m.app_palette_no_hits_deals({ query });
  if (invoices) return m.app_palette_no_hits_invoices({ query });
  return m.app_palette_no_hits({ query });
}
