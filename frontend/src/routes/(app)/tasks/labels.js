import { m } from '#lib/paraglide/messages.js';

/** Display labels for task codes. An unknown code is shown as it came. */
const STATUS = {
  New: () => m.tasks_status_new(),
  'In Progress': () => m.tasks_status_in_progress(),
  Completed: () => m.tasks_status_completed()
};
const PRIORITY = {
  Low: () => m.tasks_priority_low(),
  Medium: () => m.tasks_priority_medium(),
  High: () => m.tasks_priority_high()
};
const KIND = {
  account: () => m.tasks_kind_account(),
  deal: () => m.tasks_kind_deal(),
  ticket: () => m.tasks_kind_ticket(),
  lead: () => m.tasks_kind_lead()
};

/** @param {Record<string, () => string>} map @param {string} code */
const label = (map, code) => (Object.hasOwn(map, code) ? map[code]() : code);

/** @param {string} code */
export const taskStatusLabel = (code) => label(STATUS, code);
/** @param {string} code */
export const taskPriorityLabel = (code) => label(PRIORITY, code);
/** The `related.kind` of a task's parent: account, deal, ticket or lead. @param {string} kind */
export const taskKindLabel = (kind) => label(KIND, kind);

export const TASK_STATUS_CODES = Object.keys(STATUS);
export const TASK_PRIORITY_CODES = Object.keys(PRIORITY);

/** The "Attached to" choices on the task forms, keyed by the API's parent column. */
export const parentKinds = () => [
  { key: '', label: m.tasks_parent_none() },
  { key: 'account', label: m.tasks_parent_account() },
  { key: 'opportunity', label: m.tasks_parent_deal(), module: 'deals' },
  { key: 'case', label: m.tasks_parent_ticket(), module: 'tickets' },
  { key: 'lead', label: m.tasks_parent_lead(), module: 'leads' }
];
