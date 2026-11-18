/**
 * Editor logic for the automation builder. Browser-safe: pages and components
 * render from these helpers, and the catalogue is the only source of labels.
 */
import { runTime } from '#lib/v2/format.js';
import { m } from '#lib/paraglide/messages.js';
import { isOn, OBJECT_MODULES, type ModuleRow } from '#lib/v2/modules.js';
import { budgetNotificationText, retainerInvoiceNotificationText } from '#lib/v2/projects.js';
import { estimateNotificationText } from '#lib/v2/estimates.js';
import type { Tone } from '#lib/v2/enums.js';
import type { components } from '#lib/api-schema.js';

type Schemas = components['schemas'];
export type Catalogue = Schemas['AutomationCatalogueResponse'];
export type CatalogueObject = Schemas['AutomationCatalogueObject'];
export type Field = Schemas['AutomationCatalogueField'];
/** An object `set_field` can write to, which may be one the catalogue no longer lists. */
type TargetObject = Omit<CatalogueObject, 'label_plural'>;
export type Option = {
  value: string;
  label: string;
  group?: string;
  settable?: boolean;
  gone?: boolean;
};

/**
 * The rule language, as `backend/automation/validation.py` accepts it. A
 * value is text, a number, a date or choice as text, true or false, a member
 * id, or a list of them; null on a trigger or condition means none.
 */
export type RuleValue = string | number | boolean | null | Array<string | number | boolean>;
type RuleTrigger = { event: string; field?: string | null; to?: RuleValue };
export type RuleCondition = { field: string; op: string; value: RuleValue };

/**
 * One action as the editor holds it. Each type has its own keys
 * (`ACTION_KEYS`) and any may be unset mid-edit; `value` is undefined until
 * chosen and null for a deliberate clear.
 */
export type RuleAction = {
  type: string;
  target?: string;
  field?: string;
  value?: RuleValue;
  mode?: string;
  people?: string[];
  title?: string;
  due_in_days?: number | null;
  priority?: string;
  assign_to?: string;
  person?: string | null;
  to?: string[];
  message?: string;
  endpoint?: string;
};

export type RuleDraft = {
  name: string;
  object_key: string;
  match: string;
  trigger: RuleTrigger;
  conditions: RuleCondition[];
  actions: RuleAction[];
};

/**
 * A rule as it arrives: a saved one, whose JSON parts the API leaves untyped,
 * or the editor's own draft.
 */
type RuleLike = {
  name?: unknown;
  object_key?: unknown;
  match?: unknown;
  trigger?: unknown;
  conditions?: unknown;
  actions?: unknown;
};

/** What the editor reads off its page's `form`. */
export type EditorForm =
  | {
      save?: { general?: string | null; rows?: Record<string, string>; plan?: boolean };
      saved?: boolean;
      switchedOff?: boolean;
      switchOff?: { general?: string };
      remove?: { general?: string };
      tried?: { recordName: string; steps: Schemas['AutomationStep'][] };
      tryError?: string;
    }
  | null
  | undefined;

export function objectOf(
  catalogue: Catalogue | null | undefined,
  key: string
): CatalogueObject | null {
  return (catalogue?.objects ?? []).find((o) => o.key === key) ?? null;
}

export function fieldOf(
  object: { fields: Field[] } | null | undefined,
  key: string | null | undefined
): Field | null {
  return (object?.fields ?? []).find((f) => f.key === key) ?? null;
}

export function triggerFields(object: { fields: Field[] } | null | undefined) {
  return (object?.fields ?? []).filter((f) => f.type !== 'people');
}

export function operatorsFor(
  catalogue: Catalogue | null | undefined,
  field: Field | null,
  event: string
): string[] {
  if (!field) return [];
  const base = catalogue?.operators?.[field.type] ?? [];
  if (event === 'updated' && field.type !== 'people') {
    return [...base, ...(catalogue?.update_only_operators ?? [])];
  }
  return [...base];
}

const OPERATOR_LABELS: Record<string, () => string> = {
  eq: () => m.settings_automation_op_eq(),
  neq: () => m.settings_automation_op_neq(),
  contains: () => m.settings_automation_op_contains(),
  not_contains: () => m.settings_automation_op_not_contains(),
  gt: () => m.settings_automation_op_gt(),
  lt: () => m.settings_automation_op_lt(),
  in: () => m.settings_automation_op_in(),
  not_in: () => m.settings_automation_op_not_in(),
  true: () => m.settings_automation_op_true(),
  false: () => m.settings_automation_op_false(),
  includes: () => m.settings_automation_op_includes(),
  excludes: () => m.settings_automation_op_excludes(),
  empty: () => m.settings_automation_op_empty(),
  not_empty: () => m.settings_automation_op_not_empty(),
  was: () => m.settings_automation_op_was(),
  was_not: () => m.settings_automation_op_was_not()
};

export function operatorLabel(op: string, fieldType?: string) {
  if (fieldType === 'date' && op === 'gt') return m.settings_automation_op_date_after();
  if (fieldType === 'date' && op === 'lt') return m.settings_automation_op_date_before();
  if (fieldType === 'people' && op === 'eq') return m.settings_automation_op_people_exactly();
  return Object.hasOwn(OPERATOR_LABELS, op) ? OPERATOR_LABELS[op]() : op;
}

/**
 * `none`, `choices`, `people`, `person`, `boolean`, or the field's own type
 * (`text`, `number`, `date`, `choice`, ...).
 */
export function valueKind(field: { type: string }, op: string): string {
  if (['empty', 'not_empty', 'true', 'false'].includes(op)) return 'none';
  if (op === 'in' || op === 'not_in') return 'choices';
  if (field.type === 'people') return op === 'eq' ? 'people' : 'person';
  if ((op === 'was' || op === 'was_not') && field.type === 'boolean') return 'boolean';
  return field.type;
}

export function blankCondition(): RuleCondition {
  return { field: '', op: '', value: null };
}

export function blankAction(type: string): RuleAction {
  switch (type) {
    case 'create_task':
      return {
        type,
        title: '',
        due_in_days: 2,
        priority: 'Medium',
        assign_to: 'record',
        person: null
      };
    case 'notify':
      return { type, to: [], people: [], message: '' };
    case 'set_field':
      return { type, target: 'record', field: '', value: null };
    case 'assign':
      return { type, mode: 'replace', people: [] };
    case 'webhook':
      return { type, endpoint: '' };
    default:
      return { type };
  }
}

export function actionTypes(
  catalogue: Catalogue | null | undefined,
  object: CatalogueObject | null | undefined
): string[] {
  const assignees = fieldOf(object, 'assigned_to');
  const canAssign = assignees?.type === 'people' && assignees.settable;
  const canHook =
    !String(object?.key ?? '').startsWith('obj:') && (catalogue?.endpoints ?? []).length > 0;
  return (catalogue?.actions ?? []).filter(
    (a) => (a !== 'assign' || canAssign) && (a !== 'webhook' || canHook)
  );
}

/** Where `set_field` can write: the record, its parent, then each link. */
export function targetsFor(
  catalogue: Catalogue | null | undefined,
  object: CatalogueObject | null | undefined
): { value: string; label: string; object: TargetObject }[] {
  if (!object) return [];
  const out: { value: string; label: string; object: TargetObject }[] = [
    {
      value: 'record',
      label: m.settings_automation_target_record({ object: object.label.toLowerCase() }),
      object
    }
  ];
  if (object.parent) {
    out.push({
      value: 'parent',
      label: m.settings_automation_target_parent({ object: object.parent.label.toLowerCase() }),
      object: objectOf(catalogue, object.parent.key) ?? {
        key: object.parent.key,
        label: object.parent.label,
        fields: [],
        parent: null,
        links: []
      }
    });
  }
  for (const link of object.links ?? []) {
    out.push({
      value: link.id,
      label: link.label,
      object: objectOf(catalogue, link.object_key) ?? {
        key: link.object_key,
        label: link.label,
        fields: [],
        parent: null,
        links: []
      }
    });
  }
  return out;
}

export function recipientsFor(
  object: CatalogueObject | null | undefined
): { value: string; label: string }[] {
  const out: { value: string; label: string }[] = [
    { value: 'record_assignees', label: m.settings_automation_recipient_assignees() },
    { value: 'record_creator', label: m.settings_automation_recipient_creator() }
  ];
  const parent = parentAssignees(object);
  if (parent) out.push({ value: 'parent_assignees', label: parent });
  out.push({ value: 'admins', label: m.settings_automation_recipient_admins() });
  for (const link of object?.links ?? []) {
    out.push({
      value: `linked:${link.id}`,
      label: m.settings_automation_recipient_linked({ link: link.label })
    });
  }
  return out;
}

/** Whether the object has a parent a task or notification can reach. */
export function offersParent(
  object: { key: string; parent: Schemas['AutomationCatalogueParent'] | null } | null | undefined
) {
  if (object?.key === 'task') return true;
  return (object?.key === 'deal' || object?.key === 'ticket') && Boolean(object.parent);
}

/** How the parent's assignees read in a list, or null where there is no parent. */
export function parentAssignees(
  object: { key: string; parent: Schemas['AutomationCatalogueParent'] | null } | null | undefined
): string | null {
  if (!object || !offersParent(object)) return null;
  if (object.key === 'task') return m.settings_automation_recipient_parent_task();
  return object.parent
    ? m.settings_automation_recipient_parent_named({ object: object.parent.label.toLowerCase() })
    : null;
}

/** Who a created task can be for. */
export function taskAudience(
  object: CatalogueObject | null | undefined
): { value: string; label: string }[] {
  const out: { value: string; label: string }[] = [
    { value: 'record', label: m.settings_automation_recipient_assignees() }
  ];
  const parent = parentAssignees(object);
  if (parent) out.push({ value: 'parent', label: parent });
  out.push(
    { value: 'owner', label: m.settings_automation_recipient_owner() },
    { value: 'person', label: m.settings_automation_recipient_person() }
  );
  return out;
}

const ACTION_LABELS: Record<string, () => string> = {
  set_field: () => m.settings_automation_action_set_field(),
  assign: () => m.settings_automation_action_assign(),
  create_task: () => m.settings_automation_action_create_task(),
  notify: () => m.settings_automation_action_notify(),
  webhook: () => m.settings_automation_action_webhook()
};

export function actionLabel(type: string) {
  return Object.hasOwn(ACTION_LABELS, type) ? ACTION_LABELS[type]() : type;
}

/** How a recipient or task audience the object no longer offers reads. */
export function recipientLabel(value: string) {
  if (value.startsWith('linked:')) return m.settings_automation_recipient_removed_link();
  const usual: Record<string, string> = {
    record_assignees: m.settings_automation_recipient_assignees(),
    record_creator: m.settings_automation_recipient_creator(),
    parent_assignees: m.settings_automation_recipient_parent_gone(),
    parent: m.settings_automation_recipient_parent_gone(),
    admins: m.settings_automation_recipient_admins(),
    record: m.settings_automation_recipient_assignees(),
    owner: m.settings_automation_recipient_owner(),
    person: m.settings_automation_recipient_person()
  };
  return Object.hasOwn(usual, value)
    ? usual[value]
    : m.settings_automation_no_longer_available({ value });
}

/** The action types to offer, plus the stored one the catalogue lost. */
export function actionOptions(
  catalogue: Catalogue | null | undefined,
  object: CatalogueObject | null | undefined,
  stored: string
) {
  const offered = actionTypes(catalogue, object).map((t) => ({ value: t, label: actionLabel(t) }));
  return withStored(offered, stored, {
    label: (type) => m.settings_automation_no_longer_available({ value: actionLabel(type) })
  });
}

/**
 * Ticking "Clear it instead" sets null; unticking brings back what the action
 * held before, or leaves the value unchosen.
 */
export function applyClear(
  action: { value?: RuleValue },
  on: boolean,
  previous: RuleValue | undefined
) {
  action.value = on ? null : (previous ?? undefined);
}

/** Null is a deliberate clear. */
export function isClearing(action: { value?: RuleValue }) {
  return action.value === null;
}

/**
 * A value from the input. Null from a select or number input means nothing is
 * chosen, never a clear.
 */
export function setActionValue(action: { value?: RuleValue }, value: RuleValue | undefined) {
  action.value = value === null ? undefined : value;
}

/** What the value input shows: a placeholder while nothing is chosen. */
export function shownValue(action: { value?: RuleValue }): RuleValue {
  return action.value === undefined ? null : action.value;
}

/** Changing assign's mode empties its people, which differ in count. */
export function applyMode(action: RuleAction, mode: string) {
  action.mode = mode;
  action.people = [];
}

/** A `set_field` row pointed at another target starts over, in place. */
export function applyTarget(action: RuleAction, target: string) {
  action.target = target;
  action.field = '';
  action.value = undefined;
}

/** A chosen field has no value yet; an absent value is refused, a null one clears. */
export function applyField(action: RuleAction, field: string) {
  action.field = field;
  action.value = undefined;
}

/** Who a task is for; only a chosen person keeps a person. */
export function applyAssignTo(action: RuleAction, who: string) {
  action.assign_to = who;
  if (who !== 'person') action.person = null;
}

/**
 * Options plus any stored value they no longer carry, so editing a rule never
 * silently drops what it holds.
 *
 * Only text values can be options; any other kind of stored value is the
 * input's own, which draws no options.
 *
 * @param stored One value, a list of them, or empty.
 * @param opts `person`: stored values are member ids. `label`: how a lost value reads.
 */
export function withStored(
  options: Option[],
  stored: unknown,
  {
    person = false,
    label = undefined
  }: { person?: boolean; label?: (value: string) => string | undefined } = {}
): Option[] {
  const out = [...options];
  const seen = new Set(options.map((o) => o.value));
  const values: unknown[] = Array.isArray(stored) ? stored : [stored];
  for (const value of values) {
    if (typeof value !== 'string' || value === '' || seen.has(value)) continue;
    seen.add(value);
    out.push({
      value,
      label:
        label?.(value) ??
        (person
          ? m.settings_automation_someone_inactive()
          : m.settings_automation_no_longer_available({ value })),
      group: '',
      settable: false,
      gone: true
    });
  }
  return out;
}

/**
 * The person a replace assign shows as chosen. A stored rule can hold several
 * though the API takes exactly one, so none is preselected then and the admin
 * chooses who stays.
 */
export function replacePerson(action: { people?: string[] }): { id: string; several: boolean } {
  const people = Array.isArray(action?.people) ? action.people : [];
  return { id: people.length === 1 ? people[0] : '', several: people.length > 1 };
}

export function triggerSentence(
  rule: { object_key?: string; trigger?: unknown } | null | undefined,
  catalogue: Catalogue | null | undefined
) {
  const trigger = asObject(rule?.trigger) ?? {};
  if (trigger.event === 'created') return m.settings_automation_trigger_created();
  if (!trigger.field) return m.settings_automation_trigger_updated();
  const field =
    typeof trigger.field === 'string'
      ? fieldOf(objectOf(catalogue, rule?.object_key ?? ''), trigger.field)
      : null;
  if (!field) return m.settings_automation_trigger_field_gone();
  const to = trigger.to;
  if (to === undefined || to === null) {
    return m.settings_automation_trigger_changes({ field: field.label });
  }
  let value = String(to);
  if (field.type === 'boolean') {
    value = to === true || to === 'true' ? m.common_yes() : m.common_no();
  } else if (field.type === 'choice') {
    const option = field.choices.find((c) => c.value === String(to));
    value = option ? option.label : String(to);
  }
  return m.settings_automation_trigger_changes_to({ field: field.label, value });
}

export function runsLabel(row: { runs_7d?: number; failures_7d?: number }) {
  const runs = row?.runs_7d ?? 0;
  if (!runs) return m.settings_automation_runs_none();
  const text = m.settings_automation_runs_count({ count: runs });
  return row.failures_7d
    ? m.settings_automation_runs_failed({ runs: text, failed: row.failures_7d })
    : text;
}

/** Names for a rule's object when the catalogue no longer lists it. */
export const OBJECT_LABELS = {
  get lead() {
    return m.settings_automation_object_lead();
  },
  get contact() {
    return m.settings_automation_object_contact();
  },
  get account() {
    return m.settings_automation_object_account();
  },
  get deal() {
    return m.settings_automation_object_deal();
  },
  get ticket() {
    return m.settings_automation_object_ticket();
  },
  get task() {
    return m.settings_automation_object_task();
  }
} as Record<string, string>;

/**
 * A rule the server paused because its object's module is switched off.
 * It resumes by itself when the module is back on.
 */
export function pausedByModule(
  row: { status?: string; object_key?: string } | null | undefined,
  modules: ModuleRow[] | null | undefined
): boolean {
  const key = OBJECT_MODULES[row?.object_key ?? ''];
  return row?.status === 'paused' && Boolean(key) && !isOn(modules, key);
}

/** The note for a rule paused by its module. */
export function modulePausedNote(row: { name?: string; status_text?: string }): string {
  return m.settings_automation_module_paused_note({
    name: row.name ?? '',
    status: row.status_text ?? ''
  });
}

export const STATUS: Record<string, { readonly label: string; tone: Tone }> = {
  on: {
    get label() {
      return m.settings_automation_status_on();
    },
    tone: 'moss'
  },
  off: {
    get label() {
      return m.settings_automation_status_off();
    },
    tone: 'slate'
  },
  paused: {
    get label() {
      return m.settings_automation_status_paused();
    },
    tone: 'clay'
  },
  over_limit: {
    get label() {
      return m.settings_automation_status_over_limit();
    },
    tone: 'clay'
  },
  needs_attention: {
    get label() {
      return m.settings_automation_status_needs_attention();
    },
    tone: 'rust'
  }
};

/**
 * The line under a list row's pill, or null. A paused rule's sentence is shown
 * once, in its paused note above the list.
 */
export function statusNote(
  rule: { status?: string; status_text?: string } | null | undefined
): string | null {
  if (!rule?.status_text || rule.status === 'paused') return null;
  const label = STATUS[rule.status ?? '']?.label;
  return rule.status_text === (label ?? rule.status) ? null : rule.status_text;
}

/** What a run's card head says beside its time and record. */
export function runNotes(
  run: { reason?: unknown; triggered_by?: { rule_name?: unknown } | null } | null | undefined
): { reason: string | null; by: string | null } {
  const reason = typeof run?.reason === 'string' && run.reason ? run.reason : null;
  const rule = run?.triggered_by?.rule_name;
  return {
    reason,
    by: typeof rule === 'string' && rule ? m.settings_automation_set_off_by({ rule }) : null
  };
}

export { recordHref as recordRoute } from '#lib/v2/custom-objects.js';

const ACTION_KEYS: Record<string, string[]> = {
  set_field: ['target', 'field', 'value'],
  assign: ['mode', 'people'],
  create_task: ['title', 'due_in_days', 'priority', 'assign_to', 'person'],
  notify: ['to', 'people', 'message'],
  webhook: ['endpoint']
};

function asObject(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function isScalar(value: unknown): value is string | number | boolean {
  return typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean';
}

function isRuleValue(value: unknown): value is RuleValue {
  return value === null || isScalar(value) || (Array.isArray(value) && value.every(isScalar));
}

function isTextList(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((v) => typeof v === 'string');
}

const textOr = (value: unknown, fallback: string) => (typeof value === 'string' ? value : fallback);

/**
 * A stored trigger, or the created trigger a new rule starts with. Anything
 * the validator would not have saved is dropped rather than carried.
 */
function readTrigger(raw: unknown): RuleTrigger {
  if (raw === null || raw === undefined) return { event: 'created' };
  const trigger = asObject(raw) ?? {};
  const t: RuleTrigger = { event: textOr(trigger.event, '') };
  if (Object.hasOwn(trigger, 'field')) {
    const field = trigger.field;
    if (typeof field === 'string' || field === null) t.field = field;
  }
  if (Object.hasOwn(trigger, 'to') && isRuleValue(trigger.to)) t.to = trigger.to;
  return t;
}

function readCondition(raw: unknown): RuleCondition {
  const c = asObject(raw) ?? {};
  return {
    field: textOr(c.field, ''),
    op: textOr(c.op, ''),
    value: isRuleValue(c.value) ? c.value : null
  };
}

/** An action with only its type's keys, each of the kind the validator takes. */
function readAction(raw: unknown): RuleAction {
  const a = asObject(raw) ?? {};
  const type = textOr(a.type, '');
  const out: RuleAction = { type };
  for (const key of Object.hasOwn(ACTION_KEYS, type) ? ACTION_KEYS[type] : []) {
    if (!Object.hasOwn(a, key)) continue;
    const v = a[key];
    switch (key) {
      case 'value':
        if (isRuleValue(v)) out.value = v;
        break;
      case 'people':
      case 'to':
        if (isTextList(v)) out[key] = v;
        break;
      case 'due_in_days':
        if (v === null || typeof v === 'number') out.due_in_days = v;
        break;
      case 'person':
        if (v === null || typeof v === 'string') out.person = v;
        break;
      case 'target':
      case 'field':
      case 'mode':
      case 'title':
      case 'priority':
      case 'assign_to':
      case 'message':
      case 'endpoint':
        if (typeof v === 'string') out[key] = v;
        break;
    }
  }
  return out;
}

/**
 * The rule's body keys in a fixed order, copied, so two drafts compare by what
 * would be saved.
 */
function normalise(rule: RuleLike | null | undefined, objectKey: string): RuleDraft {
  const draft = {
    name: textOr(rule?.name, ''),
    object_key: textOr(rule?.object_key, objectKey),
    match: textOr(rule?.match, 'all'),
    trigger: readTrigger(rule?.trigger),
    conditions: Array.isArray(rule?.conditions) ? rule.conditions.map(readCondition) : [],
    actions: Array.isArray(rule?.actions) ? rule.actions.map(readAction) : []
  };
  return JSON.parse(JSON.stringify(draft)) as RuleDraft;
}

/** @param objectKey Used for a new rule. */
export function editorState(rule: RuleLike | null, objectKey: string) {
  return normalise(rule, objectKey);
}

export function isDirty(draft: RuleLike, saved: RuleLike) {
  return JSON.stringify(normalise(draft, '')) !== JSON.stringify(normalise(saved, ''));
}

/**
 * Why Try is unavailable: the hint to show, `''` when blocked with nothing to
 * say (sending, or no record chosen), or null when it may run.
 */
export function tryBlocked({
  dirty,
  busy,
  chosen
}: {
  dirty: boolean;
  busy: boolean;
  chosen: unknown[];
}): string | null {
  if (dirty) return m.settings_automation_try_save_first();
  return busy || chosen.length === 0 ? '' : null;
}

/** @param direction 1 up, 1 down */
export function moveItem<T>(list: T[], index: number, direction: number): T[] {
  const next = [...list];
  const to = index + direction;
  if (index < 0 || index >= next.length || to < 0 || to >= next.length) return next;
  [next[index], next[to]] = [next[to], next[index]];
  return next;
}

/**
 * A condition's value once its operator changes. It survives only while the
 * new operator reads the same kind of value, so a stale one is never sent.
 */
export function keptValue(
  field: Field | null,
  fromOp: string,
  toOp: string,
  value: RuleValue | undefined
): RuleValue {
  if (!field) return null;
  const kind = valueKind(field, toOp);
  return kind === 'none' || kind !== valueKind(field, fromOp) ? null : (value ?? null);
}

/**
 * The draft moved to another object: conditions go, and so does any action the
 * object cannot take; a task for a missing parent falls back to the record.
 */
export function switchObject(
  draft: RuleDraft,
  catalogue: Catalogue | null | undefined,
  key: string
): RuleDraft {
  const copy = JSON.parse(JSON.stringify(draft)) as RuleDraft;
  const next = objectOf(catalogue, key);
  const offered = new Set(recipientsFor(next).map((r) => r.value));
  const offeredTypes = actionTypes(catalogue, next);
  const parent = offersParent(next);
  return {
    ...copy,
    object_key: key,
    trigger: { event: copy.trigger?.event ?? 'created' },
    conditions: [],
    actions: (copy.actions ?? [])
      .filter((a) => offeredTypes.includes(a.type))
      .map((a) => {
        if (a.type === 'create_task' && a.assign_to === 'parent' && !parent) {
          return { ...a, assign_to: 'record' };
        }
        if (a.type === 'set_field') return blankAction('set_field');
        if (a.type === 'notify') {
          return { ...a, to: (a.to ?? []).filter((v) => offered.has(v)) };
        }
        return a;
      })
  };
}

/** The note under a "changes to" value, or null until there is one. */
export function changeHint(field: Field | null, to: RuleValue | undefined) {
  if (!field || to === undefined || to === null || to === '') return null;
  let value = String(to);
  if (field.type === 'boolean')
    value = to === true || to === 'true' ? m.common_yes() : m.common_no();
  if (field.type === 'choice') {
    value = field.choices.find((c) => c.value === value)?.label ?? value;
  }
  return m.settings_automation_change_hint({ field: field.label.toLowerCase(), value });
}

/**
 * A save's errors split between the rows the page shows and one general line
 * for the rest, so no refusal goes unseen.
 */
export function placeErrors(
  save: { general?: string | null; rows?: Record<string, string> } | null | undefined,
  shown: (key: string) => boolean
): { general: string | null; rows: Record<string, string> } {
  const rows: Record<string, string> = {};
  const rest = save?.general ? [save.general] : [];
  for (const [key, message] of Object.entries(save?.rows ?? {})) {
    const row = /^(conditions|actions)\.(\d+)$/.exec(key);
    if (shown(key)) rows[key] = message;
    else if (row) {
      const n = Number(row[2]) + 1;
      rest.push(
        row[1] === 'conditions'
          ? m.settings_automation_condition_error({ n, message })
          : m.settings_automation_action_error({ n, message })
      );
    } else rest.push(message);
  }
  return { general: rest.length ? rest.join(' ') : null, rows };
}

/** Keys the editor shows under their own section or field. */
const SECTION_KEYS = ['name', 'match', 'trigger', 'conditions', 'actions'];

/** Rows are compared by identity and by their JSON, so any row object will do. */
type SentRows = {
  conditions: object[];
  actions: object[];
  copies: { conditions: string[]; actions: string[] };
};

/**
 * The rows a save sends: the row objects themselves, and a copy of each as it
 * was, so `editorErrors` can tell a row edited since.
 */
export function sentRows(draft: { conditions?: object[]; actions?: object[] }): SentRows {
  const conditions = [...(draft?.conditions ?? [])];
  const actions = [...(draft?.actions ?? [])];
  const copy = (row: object) => JSON.stringify(row);
  return {
    conditions,
    actions,
    copies: { conditions: conditions.map(copy), actions: actions.map(copy) }
  };
}

/**
 * A save's errors as the editor shows them. A row's message goes to the row
 * object it was sent as, so it stays with that row when another is removed,
 * and leaves once that row is edited; anything with no place on the page
 * joins the general line.
 * @param sent From `sentRows` when the save was sent.
 * @param current The rows on the page now.
 */
export function editorErrors(
  save: { general?: string | null; rows?: Record<string, string> } | null | undefined,
  sent: SentRows,
  current: { conditions: object[]; actions?: object[] }
): {
  general: string | null;
  rows: Record<string, string>;
  conditions: (string | null)[];
  actions: (string | null)[];
} {
  const asSent = { conditions: sent?.conditions ?? [], actions: sent?.actions ?? [] };
  const placed = placeErrors(save, (key) => {
    if (SECTION_KEYS.includes(key)) return true;
    const at = /^(conditions|actions)\.(\d+)$/.exec(key);
    return Boolean(at) && Number(at?.[2]) < asSent[at?.[1] as 'conditions' | 'actions'].length;
  });
  const onRows = (kind: 'conditions' | 'actions') =>
    (current?.[kind] ?? []).map((row) => {
      const at = asSent[kind].indexOf(row);
      if (at === -1 || sent?.copies?.[kind]?.[at] !== JSON.stringify(row)) return null;
      return placed.rows[`${kind}.${at}`] ?? null;
    });
  // "Add at least one action." and its like are about the list as sent.
  const now = current?.actions ?? [];
  const same = now.length === asSent.actions.length && now.every((a, i) => a === asSent.actions[i]);
  const { actions: listError, ...rows } = placed.rows;
  return {
    general: placed.general,
    rows: same && listError ? { ...rows, actions: listError } : rows,
    conditions: onRows('conditions'),
    actions: onRows('actions')
  };
}

/**
 * A saved rule's status: its list row's, or else what the rule itself says.
 * Null for a rule not saved yet.
 */
export function ruleStatus(
  rule: { is_active?: boolean; paused_reason?: string } | null | undefined,
  row: { status?: string } | null | undefined
): string | null {
  if (!rule) return null;
  if (row?.status) return row.status;
  return rule.is_active ? 'on' : rule.paused_reason ? 'paused' : 'off';
}

/**
 * The second save button for a status, or null when the rule is already on.
 * @param status Null for a rule not saved yet.
 */
export function switchLabel(status: string | null | undefined) {
  if (status === 'paused') return m.settings_automation_save_take_over();
  if (status === 'off' || status === null || status === undefined)
    return m.settings_automation_save_switch_on();
  return null;
}

/**
 * Whether the Settings hub offers the Automation row: admins only, and not
 * where the API answered 404 (`automationSummary` returns false there).
 */
export function showAutomationSetting(
  summary: { active: number; failing: number; attention: boolean } | null | false,
  isAdmin: boolean
): boolean {
  return isAdmin && summary !== false;
}

/** The settings hub row's value and warning from `automationSummary`. */
export function hubValue(
  summary: { active: number; failing: number; attention: boolean } | null | false | undefined
): { value: string | null; warn: boolean } {
  if (!summary) return { value: null, warn: false };
  const rules = summary.active
    ? m.settings_automation_hub_active({ count: summary.active })
    : m.settings_automation_hub_none();
  return {
    value:
      summary.failing > 0
        ? m.settings_automation_hub_failing({ rules, failing: summary.failing })
        : rules,
    warn: Boolean(summary.attention)
  };
}

const str = (v: unknown): v is string => typeof v === 'string';

/**
 * The sentence an automation, project budget, retainer invoice or estimate notification shows,
 * composed from `data`. Null for any other verb or data of the wrong type, so
 * the row keeps its usual copy; an estimate's verb has a fallback sentence
 * instead (see `estimateNotificationText`).
 */
export function notificationText(
  n: { verb?: string; data?: unknown } | null | undefined,
  timeZone: string
): { text: string; source: string | null } | null {
  const estimate = estimateNotificationText(n?.verb, n?.data);
  if (estimate) return { text: estimate, source: null };
  const d = asObject(n?.data);
  if (!d || !n) return null;
  switch (n.verb) {
    case 'automation.message':
      if (!str(d.message) || !str(d.rule)) return null;
      return { text: d.message, source: m.settings_automation_notify_from_rule({ rule: d.rule }) };
    case 'automation.failed':
      if (!str(d.rule) || !str(d.reason)) return null;
      return {
        text: m.settings_automation_notify_failed({ rule: d.rule, reason: d.reason }),
        source: null
      };
    case 'automation.paused':
      if (!str(d.reason) || !Array.isArray(d.rules) || !d.rules.every(str)) return null;
      return {
        text: m.settings_automation_notify_paused({ reason: d.reason, rules: d.rules.join(', ') }),
        source: null
      };
    case 'automation.limit': {
      if (!str(d.window_start)) return null;
      const from = midSentence(runTime(d.window_start, timeZone));
      return {
        text: m.settings_automation_notify_limit({ from }),
        source: null
      };
    }
    case 'project.budget': {
      const text = budgetNotificationText(d);
      return text ? { text, source: null } : null;
    }
    case 'project.retainer_invoice': {
      const text = retainerInvoiceNotificationText(d);
      return text ? { text, source: null } : null;
    }
    default:
      return null;
  }
}

/**
 * `runTime`'s "Today 10:00" read inside a sentence: the day word lowercased.
 */
function midSentence(when: string) {
  for (const day of [m.time_today_at({ time: '' }), m.time_yesterday_at({ time: '' })]) {
    const word = day.trim();
    if (word && when.startsWith(`${word} `)) return word.toLowerCase() + when.slice(word.length);
  }
  return when;
}

/**
 * Who a notification row credits. The API's actor carries `user_details.email`
 * and no `name`.
 */
export function actorName(
  n:
    | { actor?: { id?: string; name?: string; user_details?: { email?: string } | null } | null }
    | null
    | undefined
): string {
  return n?.actor?.name || n?.actor?.user_details?.email || m.settings_automation_someone();
}

export function automationFallback() {
  return m.settings_automation_notify_fallback();
}
