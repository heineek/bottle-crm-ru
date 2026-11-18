import { m } from '#lib/paraglide/messages.js';

/** Display labels for task codes. An unknown code is shown as it came. */
const STATUS: Record<string, () => string> = {
  New: () => m.tasks_status_new(),
  'In Progress': () => m.tasks_status_in_progress(),
  Completed: () => m.tasks_status_completed()
};
const PRIORITY: Record<string, () => string> = {
  Low: () => m.tasks_priority_low(),
  Medium: () => m.tasks_priority_medium(),
  High: () => m.tasks_priority_high()
};
const KIND: Record<string, () => string> = {
  account: () => m.tasks_kind_account(),
  deal: () => m.tasks_kind_deal(),
  ticket: () => m.tasks_kind_ticket(),
  lead: () => m.tasks_kind_lead(),
  project: () => m.tasks_kind_project()
};

const label = (map: Record<string, () => string>, code: string) =>
  Object.hasOwn(map, code) ? map[code]() : code;

export const taskStatusLabel = (code: string) => label(STATUS, code);
export const taskPriorityLabel = (code: string) => label(PRIORITY, code);
/** The `related.kind` of a task's parent: account, deal, ticket, lead or project. */
export const taskKindLabel = (kind: string) => label(KIND, kind);

export const TASK_STATUS_CODES = Object.keys(STATUS);
export const TASK_PRIORITY_CODES = Object.keys(PRIORITY);

/** The "Attached to" choices on the task forms, keyed by the API's parent column. */
export const parentKinds = (): { key: string; label: string; module?: string }[] => [
  { key: '', label: m.tasks_parent_none() },
  { key: 'account', label: m.tasks_parent_account() },
  { key: 'opportunity', label: m.tasks_parent_deal(), module: 'deals' },
  { key: 'case', label: m.tasks_parent_ticket(), module: 'tickets' },
  { key: 'lead', label: m.tasks_parent_lead(), module: 'leads' },
  { key: 'project', label: m.tasks_parent_project(), module: 'projects' }
];
