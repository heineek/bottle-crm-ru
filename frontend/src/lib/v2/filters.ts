/**
 * What each list page can be filtered by, and how those filters are drawn.
 *
 * Client-safe on purpose: `.svelte` files import this, and SvelteKit hard-blocks
 * importing `#lib/server/` into a component. The server-side counterpart is
 * `#lib/server/v2/filter-params.js`.
 *
 * Filter state lives in the URL and nowhere else, so a filtered list is
 * shareable and the back button works without any state to synchronise.
 *
 * A descriptor has two parts:
 *
 * - `presets`: named views. Each writes the params the page's `load` ALREADY
 *   reads. Never invent a new spelling: tickets and tasks use `all=1`, not
 *   `all=true`, and a preset writing the wrong one changes the URL and shows
 *   the same rows, which is the failure this whole phase exists to remove.
 * - `fields`: what `+ Filter` offers. Each becomes one removable chip.
 *
 * A `date-range` field names BOTH emitted params explicitly, because the
 * convention is not uniform: invoices uses `due_date_gte` (one underscore)
 * while every other endpoint uses `due_date__gte` (two). Never build a date key
 * by concatenation. A `number-range` field (`amount` on pipeline) is the same
 * shape, two named params and no derived key, only the value it validates is
 * numeric rather than an ISO date.
 */
import {
  CASE_PRIORITIES,
  CASE_PRIORITY_LABEL,
  CASE_STATUSES,
  CASE_STATUS_LABEL,
  CASE_TYPES,
  CASE_TYPE_LABEL,
  DOCUMENT_STATUSES,
  ESTIMATE_STATUSES,
  ESTIMATE_STATUS_LABEL,
  INDUSTRIES,
  INVOICE_STATUSES,
  LEAD_LIST_STATUSES,
  LEAD_STATUS_LABEL,
  SOLUTION_STATUS,
  SOLUTION_STATUS_LABEL,
  TASK_PRIORITY,
  TASK_PRIORITY_LABEL,
  TASK_STATUS,
  TASK_STATUS_LABEL,
  industryLabel,
  invoiceStatusLabel
} from './enums.js';
import { m } from '#lib/paraglide/messages.js';
import { PROJECT_STATUSES, PROJECT_STATUS_LABEL } from './projects.js';
import type { ReadonlyURL } from '$app/state';

export type Preset = { key: string; label: string; params: Record<string, string> };
export type Field = {
  key: string;
  label: string;
  type: string;
  options?: string[];
  labelFor?: (v: string) => string;
  gteKey?: string;
  lteKey?: string;
  multi?: boolean;
  /** A select that keeps a value no longer among its options (a removed custom option still matches records). */
  keepUnknown?: boolean;
};
export type Descriptor = { presets: Preset[]; fields: Field[] };

/** A page's descriptor from its key, or a descriptor built at run time (custom objects). */
export const descriptorFor = (page: string | Descriptor): Descriptor | undefined =>
  typeof page === 'string' ? FILTERS[page] : page;

export const FILTERS: Record<string, Descriptor> = {
  tickets: {
    presets: [
      {
        key: 'open',
        get label() {
          return m.app_list_filters_open_newest_first();
        },
        params: {}
      },
      {
        key: 'mine',
        get label() {
          return m.app_list_filters_mine();
        },
        params: { assigned_to: '@me' }
      },
      {
        key: 'breaching',
        get label() {
          return m.app_list_filters_breaching_sla();
        },
        params: { sla_breached: 'true' }
      },
      {
        key: 'all',
        get label() {
          return m.app_list_filters_everything();
        },
        params: { all: '1' }
      }
    ],
    fields: [
      {
        key: 'assigned_to',
        get label() {
          return m.common_owner();
        },
        type: 'person',
        multi: true
      },
      // Picking a status replaces the open-queue default (see `ticketListQuery`).
      {
        key: 'status',
        get label() {
          return m.common_status();
        },
        type: 'select',
        options: CASE_STATUSES,
        labelFor: (v) => CASE_STATUS_LABEL[v] ?? v,
        multi: true
      },
      {
        key: 'priority',
        get label() {
          return m.common_priority();
        },
        type: 'select',
        options: CASE_PRIORITIES,
        labelFor: (v) => CASE_PRIORITY_LABEL[v] ?? v
      },
      {
        key: 'case_type',
        get label() {
          return m.app_list_filters_type();
        },
        type: 'select',
        options: CASE_TYPES,
        labelFor: (v) => CASE_TYPE_LABEL[v] ?? v
      },
      {
        key: 'sla_breached',
        get label() {
          return m.app_list_filters_breaching_sla();
        },
        type: 'boolean'
      },
      {
        key: 'tags',
        get label() {
          return m.app_list_filters_tag();
        },
        type: 'tag',
        multi: true
      }
    ]
  },

  leads: {
    presets: [
      {
        key: 'open',
        get label() {
          return m.app_list_filters_open_leads();
        },
        params: {}
      },
      // Before `mine`, so a view of my own unanswered leads is named for the
      // stronger claim; the owner shows as a chip.
      {
        key: 'unanswered',
        get label() {
          return m.app_list_filters_unanswered();
        },
        params: { unanswered: 'true' }
      },
      {
        key: 'mine',
        get label() {
          return m.app_list_filters_mine();
        },
        params: { assigned_to: '@me' }
      }
    ],
    fields: [
      {
        key: 'assigned_to',
        get label() {
          return m.common_owner();
        },
        type: 'person',
        multi: true
      },
      {
        key: 'status',
        get label() {
          return m.common_status();
        },
        type: 'select',
        options: LEAD_LIST_STATUSES,
        labelFor: (v) => LEAD_STATUS_LABEL[v] ?? v,
        multi: true
      },
      // The org edits its sources, so the options arrive from the API
      // (FilterBar's `sources` prop), as stages do on the pipeline.
      {
        key: 'source',
        get label() {
          return m.app_list_filters_source();
        },
        type: 'source'
      },
      {
        key: 'tags',
        get label() {
          return m.app_list_filters_tag();
        },
        type: 'tag',
        multi: true
      }
    ]
  },

  contacts: {
    presets: [
      {
        key: 'mine',
        get label() {
          return m.app_list_filters_mine();
        },
        params: { assigned_to: '@me' }
      },
      {
        key: 'inactive',
        get label() {
          return m.app_list_filters_including_inactive();
        },
        params: { inactive: '1' }
      },
      {
        key: 'active',
        get label() {
          return m.app_list_filters_active_contacts();
        },
        params: {}
      }
    ],
    fields: [
      {
        key: 'assigned_to',
        get label() {
          return m.common_owner();
        },
        type: 'person',
        multi: true
      },
      {
        key: 'tags',
        get label() {
          return m.app_list_filters_tag();
        },
        type: 'tag',
        multi: true
      },
      {
        key: 'city',
        get label() {
          return m.app_list_filters_city();
        },
        type: 'text'
      }
    ]
  },

  pipeline: {
    presets: [
      {
        key: 'open',
        get label() {
          return m.app_list_filters_open_deals();
        },
        params: { open: 'true' }
      },
      {
        key: 'mine',
        get label() {
          return m.app_list_filters_mine();
        },
        params: { assigned_to: '@me' }
      },
      {
        key: 'stalled',
        get label() {
          return m.app_list_filters_stalled();
        },
        params: { rotten: 'true' }
      },
      {
        key: 'all',
        get label() {
          return m.app_list_filters_all_deals();
        },
        params: {}
      }
    ],
    fields: [
      {
        key: 'assigned_to',
        get label() {
          return m.common_owner();
        },
        type: 'person',
        multi: true
      },
      // Stages are per pipeline and configured by the org, so the options
      // arrive from the API (FilterBar's `stages` prop), not from an enum.
      {
        key: 'stage',
        get label() {
          return m.app_list_filters_stage();
        },
        type: 'stage'
      },
      {
        key: 'lead_source',
        get label() {
          return m.app_list_filters_source();
        },
        type: 'source'
      },
      {
        key: 'amount',
        get label() {
          return m.app_list_filters_value();
        },
        type: 'number-range',
        gteKey: 'amount__gte',
        lteKey: 'amount__lte'
      },
      {
        key: 'tags',
        get label() {
          return m.app_list_filters_tag();
        },
        type: 'tag',
        multi: true
      }
    ]
  },

  tasks: {
    presets: [
      {
        key: 'open',
        get label() {
          return m.app_list_filters_open_tasks();
        },
        params: {}
      },
      {
        key: 'mine',
        get label() {
          return m.app_list_filters_my_tasks();
        },
        params: { assigned_to: '@me' }
      },
      {
        key: 'all',
        get label() {
          return m.app_list_filters_all_tasks();
        },
        params: { all: '1' }
      }
    ],
    fields: [
      {
        key: 'assigned_to',
        get label() {
          return m.common_owner();
        },
        type: 'person'
      },
      {
        key: 'priority',
        get label() {
          return m.common_priority();
        },
        type: 'select',
        options: TASK_PRIORITY,
        labelFor: (v) => TASK_PRIORITY_LABEL[v] ?? v
      },
      {
        key: 'status',
        get label() {
          return m.common_status();
        },
        type: 'select',
        options: TASK_STATUS,
        labelFor: (v) => TASK_STATUS_LABEL[v] ?? v
      },
      {
        key: 'due_date',
        get label() {
          return m.common_due_date();
        },
        type: 'date-range',
        gteKey: 'due_date__gte',
        lteKey: 'due_date__lte'
      }
    ]
  },

  accounts: {
    presets: [
      {
        key: 'mine',
        get label() {
          return m.app_list_filters_mine();
        },
        params: { assigned_to: '@me' }
      },
      {
        key: 'all',
        get label() {
          return m.app_list_filters_all_accounts();
        },
        params: {}
      }
    ],
    fields: [
      {
        key: 'assigned_to',
        get label() {
          return m.common_owner();
        },
        type: 'person',
        multi: true
      },
      {
        key: 'tags',
        get label() {
          return m.app_list_filters_tag();
        },
        type: 'tag',
        multi: true
      },
      {
        key: 'industry',
        get label() {
          return m.app_list_filters_industry();
        },
        type: 'select',
        options: INDUSTRIES,
        labelFor: industryLabel
      },
      {
        key: 'city',
        get label() {
          return m.app_list_filters_city();
        },
        type: 'text'
      }
    ]
  },

  invoices: {
    presets: [
      {
        key: 'overdue',
        get label() {
          return m.app_list_filters_overdue();
        },
        params: { status: 'Overdue' }
      },
      {
        key: 'draft',
        get label() {
          return m.app_list_filters_draft();
        },
        params: { status: 'Draft' }
      },
      {
        key: 'all',
        get label() {
          return m.app_list_filters_all_invoices();
        },
        params: {}
      }
    ],
    fields: [
      {
        key: 'status',
        get label() {
          return m.common_status();
        },
        type: 'select',
        options: INVOICE_STATUSES,
        labelFor: invoiceStatusLabel
      },
      {
        key: 'account',
        get label() {
          return m.app_list_filters_account();
        },
        type: 'account'
      },
      {
        key: 'assigned_to',
        get label() {
          return m.common_owner();
        },
        type: 'person'
      },
      // Invoices uses a SINGLE underscore (`due_date_gte`/`due_date_lte`,
      // `backend/invoices/api_views.py:149-152`). Every other date-range field
      // in this file uses a DOUBLE underscore. Never build this key by
      // concatenation; a shared helper that did would silently return an
      // unfiltered list here while working everywhere else.
      {
        key: 'due_date',
        get label() {
          return m.common_due_date();
        },
        type: 'date-range',
        gteKey: 'due_date_gte',
        lteKey: 'due_date_lte'
      }
    ]
  },

  estimates: {
    presets: [
      {
        key: 'accepted',
        get label() {
          return m.app_list_filters_accepted();
        },
        params: { status: 'Accepted' }
      },
      {
        key: 'all',
        get label() {
          return m.app_list_filters_all_estimates();
        },
        params: {}
      }
    ],
    fields: [
      {
        key: 'status',
        get label() {
          return m.common_status();
        },
        type: 'select',
        options: ESTIMATE_STATUSES,
        labelFor: (v) => ESTIMATE_STATUS_LABEL[v] ?? v
      },
      {
        key: 'account',
        get label() {
          return m.app_list_filters_account();
        },
        type: 'account'
      }
      // No Owner field: `EstimateListView.get` (backend/invoices/api_views.py
      // :1028-1036) reads only `status` and `account`, never `assigned_to`.
      // Offering one here would draw a chip that filters nothing underneath it.
    ]
  },

  solutions: {
    presets: [
      {
        key: 'published',
        get label() {
          return m.app_list_filters_published();
        },
        params: { visibility: 'published' }
      },
      {
        key: 'drafts',
        get label() {
          return m.app_list_filters_drafts();
        },
        params: { status: 'draft' }
      },
      {
        key: 'all',
        get label() {
          return m.app_list_filters_all_articles_last_edited_first();
        },
        params: {}
      }
    ],
    fields: [
      {
        key: 'status',
        get label() {
          return m.common_status();
        },
        type: 'select',
        options: SOLUTION_STATUS,
        labelFor: (v) => SOLUTION_STATUS_LABEL[v] ?? v
      },
      {
        key: 'tags',
        get label() {
          return m.app_list_filters_tag();
        },
        type: 'tag'
      }
    ]
  },

  documents: {
    // `active` is the empty-params default, and `all` opts in with
    // `archived=1`, the same shape `/contacts` uses for `inactive`. The load
    // applies `status=active` unless that opt-in or an explicit Status choice
    // is present. Written the other way round, with `all` as the default,
    // archived documents come back alongside the live ones on a bare URL,
    // which undoes the only thing archiving does.
    presets: [
      {
        key: 'active',
        get label() {
          return m.app_list_filters_active_documents();
        },
        params: {}
      },
      {
        key: 'all',
        get label() {
          return m.app_list_filters_including_archived();
        },
        params: { archived: '1' }
      }
    ],
    // `tags` and `created_by` are deliberately absent: `DocumentListView.get`
    // (backend/common/views/document_views.py:71-79) reads only `title`,
    // `status` and `shared_to`, `Document` has no `tags` relation at all, and
    // `shared_to` is passed straight to `json.loads`, so a plain
    // `?shared_to=<uuid>` throws `JSONDecodeError` and answers 500. Status is
    // the only filter this endpoint actually honours.
    fields: [
      {
        key: 'status',
        get label() {
          return m.common_status();
        },
        type: 'select',
        options: DOCUMENT_STATUSES,
        labelFor: (v) => (v === 'active' ? m.documents_stat_active() : m.documents_stat_archived())
      }
    ]
  },

  projects: {
    presets: [
      {
        key: 'all',
        get label() {
          return m.app_list_filters_all_projects();
        },
        params: {}
      },
      {
        key: 'active',
        get label() {
          return m.app_list_filters_active();
        },
        params: { status: 'active' }
      },
      {
        key: 'mine',
        get label() {
          return m.app_list_filters_mine();
        },
        params: { assigned_to: '@me' }
      }
    ],
    fields: [
      {
        key: 'status',
        get label() {
          return m.common_status();
        },
        type: 'select',
        options: PROJECT_STATUSES,
        labelFor: (v) => PROJECT_STATUS_LABEL[v] ?? v
      },
      {
        key: 'account',
        get label() {
          return m.app_list_filters_account();
        },
        type: 'account'
      },
      {
        key: 'assigned_to',
        get label() {
          return m.app_list_filters_person();
        },
        type: 'person'
      }
    ]
  },

  recurring: {
    presets: [
      {
        key: 'active',
        get label() {
          return m.app_list_filters_active_schedules();
        },
        params: { is_active: 'true' }
      },
      {
        key: 'all',
        get label() {
          return m.app_list_filters_all_schedules();
        },
        params: {}
      }
    ],
    fields: [
      {
        key: 'is_active',
        get label() {
          return m.app_list_filters_active();
        },
        type: 'boolean'
      }
    ]
  }
};

/** Every param key a descriptor's fields can emit, date ranges expanded. */
export function fieldKeys(descriptor: Descriptor) {
  const keys = [];
  for (const field of descriptor.fields) {
    if (field.type === 'date-range' || field.type === 'number-range') {
      keys.push(field.gteKey, field.lteKey);
    } else keys.push(field.key);
  }
  return keys.filter(Boolean) as string[];
}

/** The same URL with `key` removed. Returns a path plus query, never absolute. */
export function withoutParam(url: ReadonlyURL, key: string) {
  const next = new URLSearchParams(url.search);
  next.delete(key);
  const qs = next.toString();
  return qs ? `${url.pathname}?${qs}` : url.pathname;
}

/**
 * The same URL with `params` applied. A null or empty value removes the key, so
 * one helper covers both adding a filter and clearing one.
 */
export function withParams(url: ReadonlyURL, params: Record<string, string | null>) {
  const next = new URLSearchParams(url.search);
  for (const [key, value] of Object.entries(params)) {
    if (value === null || value === '') next.delete(key);
    else next.set(key, value);
  }
  const qs = next.toString();
  return qs ? `${url.pathname}?${qs}` : url.pathname;
}

/**
 * Which preset the current URL represents.
 *
 * A preset matches when every param it sets is present with that value. The
 * empty-params preset is the fallback, so it is checked last and only wins when
 * nothing else does. Presets are ordered most-specific-first in each descriptor
 * for this reason.
 *
 * `meId` is the resolved viewer's profile id. A preset param of `@me` is
 * substituted with `meId` before comparing, so `mine` only matches the
 * viewer's own id, never any other value of the same key. When `meId` is not
 * resolved (null), an `@me` param can never match: labelling an unowned or
 * someone-else's-owned view as "Mine" would assert something false about
 * what is on screen.
 */
export function activePresetKey(
  pageKey: string | Descriptor,
  url: ReadonlyURL,
  meId: string | null = null
) {
  const descriptor = descriptorFor(pageKey);
  if (!descriptor) return '';
  const withParamsSet = descriptor.presets.filter((p) => Object.keys(p.params).length > 0);
  for (const preset of withParamsSet) {
    const hit = Object.entries(preset.params).every(([k, v]) => {
      const wanted = v === '@me' ? meId : v;
      // An unresolved viewer cannot match a "@me" preset. Returning true here
      // would label any owner-filtered view as "Mine".
      return wanted !== null && url.searchParams.get(k) === wanted;
    });
    if (hit) return preset.key;
  }
  return descriptor.presets.find((p) => Object.keys(p.params).length === 0)?.key ?? '';
}

type ChipLookup = { id: string; name?: string | null };

/**
 * One chip per explicitly-set filter param.
 *
 * A chip only ever represents a param that is actually in the URL, which is
 * what makes every chip removable. The old bar rendered chips describing
 * implicit defaults, and their X had nothing to remove, so it did nothing. An
 * implicit default belongs in the preset name, not in a chip.
 *
 * `lookups` resolves opaque ids, stage codes and source keys to names:
 * `{ people: [{id,name}], tags, accounts, stages, sources }`. A missing lookup
 * falls back to the raw value rather than rendering an empty chip.
 */
export function activeChips(
  pageKey: string | Descriptor,
  url: ReadonlyURL,
  lookups: { [K in 'people' | 'tags' | 'accounts' | 'stages' | 'sources']?: ChipLookup[] } = {}
) {
  const descriptor = descriptorFor(pageKey);
  if (!descriptor) return [];
  const nameFrom = (list: ChipLookup[], id: string) => list?.find((o) => o.id === id)?.name ?? id;

  const chips = [];
  for (const field of descriptor.fields) {
    if (field.type === 'date-range' || field.type === 'number-range') {
      const from = url.searchParams.get(field.gteKey as string);
      const to = url.searchParams.get(field.lteKey as string);
      if (!from && !to) continue;
      const value =
        field.type === 'number-range'
          ? from && to
            ? m.app_list_filters_number_range({ from, to })
            : from
              ? m.app_list_filters_number_over({ from })
              : m.app_list_filters_number_under({ to: to ?? '' })
          : from && to
            ? m.app_list_filters_date_range({ from, to })
            : from
              ? m.app_list_filters_date_from({ from })
              : m.app_list_filters_date_up_to({ to: to ?? '' });
      chips.push({
        key: field.key,
        label: field.label,
        value,
        href: withParams(url, {
          [field.gteKey as string]: null,
          [field.lteKey as string]: null
        })
      });
      continue;
    }

    // A `multi` field names every value it holds, so a list filtered by two
    // owners does not wear a chip that names one.
    const raws = (
      field.multi ? url.searchParams.getAll(field.key) : [url.searchParams.get(field.key)]
    ).filter((v) => Boolean(v));
    if (raws.length === 0) continue;
    const show = (raw: string) => {
      if (field.type === 'person') return nameFrom(lookups.people ?? [], raw);
      if (field.type === 'tag') return nameFrom(lookups.tags ?? [], raw);
      if (field.type === 'account') return nameFrom(lookups.accounts ?? [], raw);
      if (field.type === 'stage') return nameFrom(lookups.stages ?? [], raw);
      if (field.type === 'source') return nameFrom(lookups.sources ?? [], raw);
      if (field.type === 'boolean') return raw === 'true' ? m.common_yes() : m.common_no();
      return field.labelFor ? field.labelFor(raw) : raw;
    };
    const value = raws.map((raw) => show(raw as string)).join(', ');

    chips.push({ key: field.key, label: field.label, value, href: withoutParam(url, field.key) });
  }
  return chips;
}
