/**
 * v2 enums, mirrored 1:1 from the Django models so the API swap is a
 * field mapping, not a translation.
 *
 *   OPPORTUNITY_TYPES, SOURCES          → backend/common/utils.py
 *   LEAD_STATUS, LEAD_SOURCE            → backend/common/utils.py
 *   STATUS_CHOICE, PRIORITY_CHOICE,
 *   CASE_TYPE                           → backend/common/utils.py (cases)
 *   INVOICE_STATUS                      → backend/invoices/models.py
 *   aging_status                        → Opportunity.get_aging_status()
 *                                         returns 'green' | 'yellow' | 'red'
 *
 * TONE is the only place colour is decided. Six tones, and Ember is not one
 * of them. Ember belongs to actions, never to status.
 *   ink   → neutral, structural
 *   slate → nothing to do here (includes aging "green": on pace is the
 *           absence of a problem, not an achievement)
 *   clay  → attention, past expected_days
 *   rust  → overdue, stalled, urgent, lost
 *   moss  → won, paid, completed
 */

import { m } from '#lib/paraglide/messages.js';

/**
 * A label map whose values are read per access, so each request gets its own
 * locale. Keys, iteration and spread behave as on a plain object.
 *
 * @template {Record<string, () => string>} T
 * @param {T} fns
 * @returns {{ [K in keyof T]: string }}
 */
function labels(fns) {
  const out = {};
  for (const [key, fn] of Object.entries(fns)) {
    Object.defineProperty(out, key, { get: fn, enumerable: true });
  }
  return /** @type {any} */ (out);
}

/**
 * Deal stages are configured per org and per pipeline (`DealStage`), so there
 * is no stage list here: pages read the stages from the API. What a stage
 * MEANS is its kind, and these two kinds close a deal, whatever the stage is
 * called.
 */
export const CLOSED_KINDS = ['won', 'lost'];

export const OPPORTUNITY_TYPE_LABEL = labels({
  NEW_BUSINESS: () => m.app_enum_opp_type_new_business(),
  EXISTING_BUSINESS: () => m.app_enum_opp_type_existing_business(),
  RENEWAL: () => m.app_enum_deal_type_renewal(),
  UPSELL: () => m.app_enum_deal_type_upsell(),
  CROSS_SELL: () => m.app_enum_deal_type_cross_sell()
});

/** Opportunity.aging_status. The API returns these three strings verbatim. */
export const AGING_TONE = { green: 'slate', yellow: 'clay', red: 'rust' };
export const AGING_LABEL = labels({
  green: () => m.app_enum_aging_green(),
  yellow: () => m.app_enum_aging_yellow(),
  red: () => m.app_enum_aging_red()
});

export const LEAD_STATUS_TONE = {
  assigned: 'slate',
  'in process': 'ink',
  converted: 'moss',
  recycled: 'slate',
  closed: 'rust'
};

/**
 * common.utils LEAD_STATUS / LEAD_SOURCE / INDCHOICES: the stored values,
 * verbatim, lowercase and misspellings included. "compaign" is the value in
 * the database; correcting it here would produce a form that writes a value
 * the column rejects.
 *
 * Labels are separate because these are stored the way somebody typed them in
 * 2015 and SHOUTING an industry at a person is not a design decision.
 */
export const LEAD_STATUSES = ['assigned', 'in process', 'converted', 'recycled', 'closed'];

export const LEAD_STATUS_LABEL = labels({
  assigned: () => m.app_status_lead_assigned(),
  'in process': () => m.app_status_lead_in_process(),
  converted: () => m.app_status_lead_converted(),
  recycled: () => m.app_status_lead_recycled(),
  closed: () => m.app_status_lead_closed()
});

/**
 * The statuses the leads LIST can display. `LeadListView` excludes `converted`
 * outright and splits `closed` into a `close_leads` block the frontend never
 * reads, so offering either as a filter option gives a permanently empty page
 * that reads as "you have none" rather than "this page cannot show them".
 * The full set stays in LEAD_STATUSES for the detail page's status select.
 */
export const LEAD_LIST_STATUSES = ['assigned', 'in process', 'recycled'];

export const LEAD_SOURCES = [
  'call',
  'email',
  'existing customer',
  'partner',
  'public relations',
  'compaign',
  'other'
];

/** A lead's rating, as `Lead.RATING_CHOICES` stores it. */
export const RATING_LABEL = labels({
  HOT: () => m.app_enum_rating_hot(),
  WARM: () => m.app_enum_rating_warm(),
  COLD: () => m.app_enum_rating_cold()
});

export const LEAD_SOURCE_LABEL = labels({
  call: () => m.app_enum_lead_source_call(),
  email: () => m.common_email(),
  'existing customer': () => m.app_enum_lead_source_existing_customer(),
  partner: () => m.app_enum_lead_source_partner(),
  'public relations': () => m.app_enum_lead_source_public_relations(),
  compaign: () => m.app_enum_lead_source_campaign(),
  other: () => m.app_enum_other()
});

/**
 * Mirrors `leads/workflow.py::IRREVERSIBLE_STATUSES`. A converted lead can be
 * neither re-converted (which would build a second opportunity) nor moved
 * back out (which would orphan the account, contact and opportunity that
 * conversion created). `LeadCreateSerializer.validate_status` refuses both.
 *
 * "closed" is deliberately absent: reopening a closed lead creates nothing and
 * destroys nothing, so it stays an ordinary edit.
 */
export const LEAD_IRREVERSIBLE_STATUSES = ['converted'];

export const INDUSTRIES = [
  'ADVERTISING',
  'AGRICULTURE',
  'APPAREL & ACCESSORIES',
  'AUTOMOTIVE',
  'BANKING',
  'BIOTECHNOLOGY',
  'BUILDING MATERIALS & EQUIPMENT',
  'CHEMICAL',
  'COMPUTER',
  'EDUCATION',
  'ELECTRONICS',
  'ENERGY',
  'ENTERTAINMENT & LEISURE',
  'FINANCE',
  'FOOD & BEVERAGE',
  'GROCERY',
  'HEALTHCARE',
  'INSURANCE',
  'LEGAL',
  'MANUFACTURING',
  'PUBLISHING',
  'REAL ESTATE',
  'SERVICE',
  'SOFTWARE',
  'SPORTS',
  'TECHNOLOGY',
  'TELECOMMUNICATIONS',
  'TELEVISION',
  'TRANSPORTATION',
  'VENTURE CAPITAL'
];

/** "FOOD & BEVERAGE" → "Food & beverage". The value sent to the API is unchanged. */
export const industryLabel = (v) => {
  if (!v) return '';
  const key = `app_enum_industry_${String(v)
    .toLowerCase()
    .replace(/[^a-z]+/g, '_')}`;
  const message = /** @type {Record<string, (() => string) | undefined>} */ (
    /** @type {unknown} */ (m)
  )[key];
  return message ? message() : v.charAt(0) + v.slice(1).toLowerCase();
};

export const PRIORITY_TONE = { Urgent: 'rust', High: 'clay', Normal: 'slate', Low: 'slate' };

/** cases.PRIORITY_CHOICE. Masculine in Russian, agreeing with «приоритет». */
export const CASE_PRIORITY_LABEL = labels({
  Low: () => m.app_enum_priority_low(),
  Normal: () => m.app_enum_priority_normal(),
  High: () => m.app_enum_priority_high(),
  Urgent: () => m.app_enum_priority_urgent()
});

/** cases.STATUS_CHOICE. Neuter in Russian, agreeing with «обращение». */
export const CASE_STATUS_LABEL = labels({
  New: () => m.app_status_ticket_new(),
  Assigned: () => m.app_status_ticket_assigned(),
  Pending: () => m.app_status_ticket_pending(),
  Closed: () => m.app_status_ticket_closed(),
  Rejected: () => m.app_status_ticket_rejected(),
  Duplicate: () => m.app_status_ticket_duplicate()
});

export const CASE_TYPE_LABEL = labels({
  Question: () => m.app_enum_case_type_question(),
  Incident: () => m.app_enum_case_type_incident(),
  Problem: () => m.app_enum_case_type_problem()
});

export const CASE_STATUS_TONE = {
  New: 'ink',
  Assigned: 'ink',
  Pending: 'clay',
  Closed: 'moss',
  Rejected: 'rust',
  Duplicate: 'slate'
};

/**
 * What a ticket the viewer may not open is called wherever it still appears.
 *
 * The API keeps such a ticket in place, by id, with `restricted: true` and no
 * name: a node in `/tree/`, or a ticket's `parent_summary`. Shared so the tree,
 * the close confirm step and the parent link all say the same thing.
 */
export const restrictedTicketName = () => m.app_restricted_ticket_name();

export const INVOICE_STATUS_TONE = {
  Draft: 'slate',
  Sent: 'ink',
  Viewed: 'ink',
  Paid: 'moss',
  Partially_Paid: 'clay',
  Overdue: 'rust',
  Pending: 'clay',
  Cancelled: 'slate'
};

/** invoices.INVOICE_STATUS. Masculine in Russian, agreeing with «счёт». */
export const INVOICE_STATUS_LABEL = labels({
  Draft: () => m.app_status_invoice_draft(),
  Sent: () => m.app_status_invoice_sent(),
  Viewed: () => m.app_status_invoice_viewed(),
  Paid: () => m.app_status_invoice_paid(),
  Partially_Paid: () => m.app_status_invoice_partially_paid(),
  Overdue: () => m.app_status_invoice_overdue(),
  Pending: () => m.app_status_invoice_pending(),
  Cancelled: () => m.app_status_invoice_cancelled()
});

/**
 * INVOICE_STATUS uses an underscore on the wire; never show it to a person.
 * A value outside the invoice set (FilterBar's default, payment terms) keeps
 * the plain underscore-to-space form.
 */
export const invoiceStatusLabel = (s) =>
  Object.hasOwn(INVOICE_STATUS_LABEL, s)
    ? INVOICE_STATUS_LABEL[/** @type {keyof typeof INVOICE_STATUS_LABEL} */ (s)]
    : String(s ?? '').replace(/_/g, ' ');

/**
 * tasks.Task.STATUS_CHOICES / PRIORITY_CHOICES.
 *
 * Note the trap: a Task's priority is Low/Medium/High, while a Case's is
 * Low/Normal/High/Urgent. They are different enums on different models and
 * "Medium" is not a valid case priority. Keeping them in separate maps means
 * a mismatch is a missing key you can see, not a silently unstyled pill.
 */
export const TASK_STATUS = ['New', 'In Progress', 'Completed'];
export const TASK_STATUS_TONE = { New: 'slate', 'In Progress': 'ink', Completed: 'moss' };
/** Feminine in Russian, agreeing with «задача». */
export const TASK_STATUS_LABEL = labels({
  New: () => m.app_status_task_new(),
  'In Progress': () => m.app_status_task_in_progress(),
  Completed: () => m.app_status_task_completed()
});

export const TASK_PRIORITY = ['Low', 'Medium', 'High'];
export const TASK_PRIORITY_TONE = { Low: 'slate', Medium: 'slate', High: 'clay' };
export const TASK_PRIORITY_LABEL = labels({
  Low: () => m.app_enum_priority_low(),
  Medium: () => m.app_enum_priority_medium(),
  High: () => m.app_enum_priority_high()
});

/**
 * cases.Solution.STATUS_CHOICES, plus the separate is_published flag.
 *
 * Status and published are two different facts: an article can be approved
 * and still unpublished. v1 showed only one of them, so "approved" articles
 * customers could not see looked live. Both are surfaced here.
 */
export const SOLUTION_STATUS = ['draft', 'reviewed', 'approved'];
export const SOLUTION_STATUS_LABEL = labels({
  draft: () => m.app_status_solution_draft(),
  reviewed: () => m.app_status_solution_reviewed(),
  approved: () => m.app_status_solution_approved()
});
export const SOLUTION_STATUS_TONE = { draft: 'slate', reviewed: 'clay', approved: 'moss' };

/**
 * opportunity.SalesGoal, GOAL_TYPES and PERIOD_TYPES from common/utils.py.
 *
 * The status values are the four SalesGoal.status returns, and the labels say
 * what they mean rather than repeating the wire value: "behind" alone does not
 * tell you behind on what. They are pace judgements, not percentages.
 */
export const GOAL_TYPE_LABEL = labels({
  REVENUE: () => m.app_enum_goal_type_revenue(),
  DEALS_CLOSED: () => m.app_enum_goal_type_deals_closed(),
  ACTIVITIES: () => m.app_enum_goal_type_activities()
});

/** Opportunity types, for the per-goal weighting on a revenue or deals goal. */
export const DEAL_TYPE_LABEL = labels({
  NEW_BUSINESS: () => m.app_enum_deal_type_new_business(),
  EXISTING_BUSINESS: () => m.app_enum_deal_type_existing_business(),
  RENEWAL: () => m.app_enum_deal_type_renewal(),
  UPSELL: () => m.app_enum_deal_type_upsell(),
  CROSS_SELL: () => m.app_enum_deal_type_cross_sell()
});

export const PERIOD_TYPE_LABEL = labels({
  MONTHLY: () => m.app_enum_monthly(),
  QUARTERLY: () => m.app_enum_quarterly(),
  YEARLY: () => m.app_enum_yearly(),
  CUSTOM: () => m.app_enum_period_custom()
});

export const GOAL_STATUS_LABEL = labels({
  completed: () => m.app_status_goal_completed(),
  on_track: () => m.app_status_goal_on_track(),
  at_risk: () => m.app_status_goal_at_risk(),
  behind: () => m.app_status_goal_behind()
});

export const GOAL_STATUS_TONE = {
  completed: 'moss',
  on_track: 'slate',
  at_risk: 'clay',
  behind: 'rust'
};

/** cases.approvals: APPROVAL_STATE_CHOICES. */
export const APPROVAL_STATE_LABEL = labels({
  pending: () => m.app_status_approval_pending(),
  approved: () => m.app_status_approval_approved(),
  rejected: () => m.app_status_approval_rejected(),
  cancelled: () => m.app_status_approval_cancelled()
});

export const APPROVAL_STATE_TONE = {
  pending: 'clay',
  approved: 'moss',
  rejected: 'rust',
  cancelled: 'slate'
};

/**
 * invoices.ESTIMATE_STATUS, its own enum, not the invoice one. There is no
 * Paid estimate and no Accepted invoice; keeping the maps apart makes a
 * mix-up show up as a missing key instead of an unstyled pill.
 *
 * Accepted is moss because the customer said yes. Whether it has been turned
 * into an invoice yet is a separate fact, and the list shows it separately.
 * A green pill on money nobody has billed is exactly the wrong reassurance.
 */
export const ESTIMATE_STATUS_TONE = {
  Draft: 'slate',
  Sent: 'ink',
  Viewed: 'ink',
  Accepted: 'moss',
  Declined: 'rust',
  Expired: 'clay'
};

/** Neuter in Russian, agreeing with «коммерческое предложение». */
export const ESTIMATE_STATUS_LABEL = labels({
  Draft: () => m.app_status_estimate_draft(),
  Sent: () => m.app_status_estimate_sent(),
  Viewed: () => m.app_status_estimate_viewed(),
  Accepted: () => m.app_status_estimate_accepted(),
  Declined: () => m.app_status_estimate_declined(),
  Expired: () => m.app_status_estimate_expired()
});

/** invoices.RECURRING_FREQUENCIES; CUSTOM carries its interval in custom_days. */
export const RECURRING_FREQUENCY_LABEL = labels({
  WEEKLY: () => m.app_enum_frequency_weekly(),
  BIWEEKLY: () => m.app_enum_frequency_biweekly(),
  MONTHLY: () => m.app_enum_monthly(),
  QUARTERLY: () => m.app_enum_quarterly(),
  SEMI_ANNUALLY: () => m.app_enum_frequency_semi_annually(),
  YEARLY: () => m.app_enum_yearly(),
  CUSTOM: () => m.app_enum_frequency_custom()
});

export const PAYMENT_TERMS_LABEL = labels({
  DUE_ON_RECEIPT: () => m.app_enum_terms_due_on_receipt(),
  NET_15: () => m.app_enum_terms_net_15(),
  NET_30: () => m.app_enum_terms_net_30(),
  NET_45: () => m.app_enum_terms_net_45(),
  NET_60: () => m.app_enum_terms_net_60(),
  CUSTOM: () => m.app_enum_terms_custom()
});

/**
 * common.Profile.role. Two values, and that is the whole set. ADMIN and USER.
 * Role is server-derived from the profile; nothing the browser sends decides
 * it. This map exists to label a value the API gave us, never to offer one.
 */
export const ROLE_LABEL = labels({
  ADMIN: () => m.app_enum_role_admin(),
  USER: () => m.app_enum_role_member()
});
export const ROLE_TONE = { ADMIN: 'clay', USER: 'slate' };

/* ── ticket handling configuration ──────────────────────────────────────── */

/**
 * cases.RoutingRule.STRATEGY_CHOICES. The model's own labels read like field
 * documentation ("Round-robin within target_assignees"); these read like the
 * sentence the rule performs, because they sit next to the target list that
 * completes them.
 */
export const ROUTING_STRATEGY_LABEL = labels({
  direct: () => m.app_enum_routing_direct_lead(),
  round_robin: () => m.app_enum_routing_round_robin_lead(),
  least_busy: () => m.app_enum_routing_least_busy_lead(),
  by_team: () => m.app_enum_routing_by_team_lead()
});

/** Standalone names for the strategy select. `ROUTING_STRATEGY_LABEL` above
 *  is a sentence fragment that runs into the target names on the rule card,
 *  so it cannot double as an option label. */
export const ROUTING_STRATEGY_NAME = labels({
  direct: () => m.app_enum_routing_direct(),
  round_robin: () => m.app_enum_routing_round_robin(),
  least_busy: () => m.app_enum_routing_least_busy(),
  by_team: () => m.app_enum_routing_by_team()
});

/** Fields a routing condition can test, in the words the rest of the app uses. */
export const CONDITION_FIELD_LABEL = labels({
  priority: () => m.common_priority(),
  case_type: () => m.app_enum_condition_type(),
  account: () => m.app_enum_condition_account(),
  tags: () => m.common_tags(),
  from_email_domain: () => m.app_enum_condition_sender_domain(),
  mailbox_id: () => m.app_enum_condition_mailbox()
});

export const CONDITION_OP_LABEL = labels({
  eq: () => m.app_enum_op_eq(),
  in: () => m.app_enum_op_in(),
  contains: () => m.app_enum_op_contains(),
  regex: () => m.app_enum_op_regex()
});

/** cases.EscalationPolicy.ACTION_CHOICES. */
export const ESCALATION_ACTION_LABEL = labels({
  notify: () => m.app_enum_escalation_notify(),
  reassign: () => m.app_enum_escalation_reassign(),
  notify_and_reassign: () => m.app_enum_escalation_notify_and_reassign()
});

/** cases.EscalationPolicy priorities, worst first. This is the display order
 *  the escalation page sorts by, not the model's `ordering = ("priority",)`,
 *  which sorts the CharField alphabetically and puts Low between High and
 *  Normal. Imported by both the page and `lib/server/v2/escalation.js`. */
export const ESCALATION_PRIORITIES = ['Urgent', 'High', 'Normal', 'Low'];

/** cases/workflow.py DEFAULT_FIRST_RESPONSE_SLA, DEFAULT_RESOLUTION_SLA and
 *  DEFAULT_NEXT_RESPONSE_SLA, in hours. What a case gets when its org has not
 *  set a target of its own, so the settings form shows these as the placeholder
 *  behind an empty input rather than leaving "blank" looking like "no SLA at
 *  all". */
export const DEFAULT_SLA_HOURS = {
  Urgent: { first_response: 1, resolution: 4, next_response: 1 },
  High: { first_response: 4, resolution: 24, next_response: 4 },
  Normal: { first_response: 8, resolution: 48, next_response: 8 },
  Low: { first_response: 24, resolution: 72, next_response: 24 }
};

/** cases.InboundMailbox.PROVIDER_CHOICES, only SES ships today. */
export const MAILBOX_PROVIDER_LABEL = {
  ses: 'Amazon SES',
  mailgun: 'Mailgun',
  postmark: 'Postmark',
  imap: 'IMAP'
};

/* ── vocabulary ─────────────────────────────────────────────────────────── */

/** common.CustomFieldDefinition.FIELD_TYPE_CHOICES. */
export const FIELD_TYPE_LABEL = labels({
  text: () => m.app_enum_field_text(),
  textarea: () => m.app_enum_field_textarea(),
  number: () => m.app_enum_field_number(),
  dropdown: () => m.app_enum_field_dropdown(),
  date: () => m.app_enum_field_date(),
  checkbox: () => m.app_enum_field_checkbox()
});

/** The statuses a reopened ticket may come back as.
 *
 * `ReopenPolicySerializer.NON_TERMINAL_STATUSES` in
 * `backend/cases/serializer.py` is the authority and rejects anything else.
 * Reopening into a terminal status would close the ticket again on arrival,
 * so the model's own choice list, which also carries Closed, Rejected and
 * Duplicate, is not the list to offer.
 */
export const REOPEN_TO_STATUSES = ['New', 'Assigned', 'Pending'];

/** Plural forms for the target model, for reading in a heading. */
export const TARGET_MODEL_LABEL = labels({
  Account: () => m.app_enum_target_accounts(),
  Case: () => m.app_enum_target_tickets(),
  Contact: () => m.app_enum_target_contacts(),
  Estimate: () => m.app_enum_target_estimates(),
  Invoice: () => m.app_enum_target_invoices(),
  Lead: () => m.app_enum_target_leads(),
  Opportunity: () => m.app_enum_target_deals(),
  RecurringInvoice: () => m.app_enum_target_recurring_invoices(),
  Task: () => m.app_enum_target_tasks()
});

export const MACRO_SCOPE_LABEL = labels({
  org: () => m.app_enum_macro_scope_org(),
  personal: () => m.app_enum_macro_scope_personal()
});

/* ── board ──────────────────────────────────────────────────────────────── */

/**
 * tasks.BoardTask.PRIORITY_CHOICES. Lowercase, and a different set from
 * TASK_PRIORITY (Low/Medium/High) and PRIORITY_TONE (Urgent/High/Normal/Low).
 * Three enums for one word across three models; keep them apart.
 */
export const BOARD_PRIORITY_LABEL = labels({
  low: () => m.app_enum_priority_low(),
  medium: () => m.app_enum_priority_medium(),
  high: () => m.app_enum_priority_high(),
  urgent: () => m.app_enum_priority_urgent()
});
export const BOARD_PRIORITY_TONE = {
  low: 'slate',
  medium: 'slate',
  high: 'clay',
  urgent: 'rust'
};

/** tasks.BoardMember.ROLE_CHOICES, board-local, unrelated to Profile.role. */
export const BOARD_ROLE_LABEL = labels({
  owner: () => m.common_owner(),
  admin: () => m.app_enum_role_admin(),
  member: () => m.app_enum_role_member()
});

/**
 * Option lists for the list-page filters. Values are what goes on the wire;
 * labels are derived where they differ.
 *
 * CASE_PRIORITIES is not TASK_PRIORITY. A Case is Low/Normal/High/Urgent and a
 * Task is Low/Medium/High: "Medium" is not a valid case priority and "Normal"
 * is not a valid task priority. See the note at TASK_STATUS above.
 */
export const CASE_PRIORITIES = ['Low', 'Normal', 'High', 'Urgent'];
export const CASE_TYPES = ['Question', 'Incident', 'Problem'];
export const CASE_STATUSES = ['New', 'Assigned', 'Pending', 'Closed', 'Rejected', 'Duplicate'];
export const INVOICE_STATUSES = [
  'Draft',
  'Sent',
  'Viewed',
  'Paid',
  'Partially_Paid',
  'Overdue',
  'Pending',
  'Cancelled'
];
export const ESTIMATE_STATUSES = ['Draft', 'Sent', 'Viewed', 'Accepted', 'Declined', 'Expired'];
export const DOCUMENT_STATUSES = ['active', 'inactive'];

// Kept until the ticket screens move to restrictedTicketName(); removed with Settings.
export const RESTRICTED_TICKET_NAME = 'A ticket you cannot open';
