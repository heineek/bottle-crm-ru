<script>
  import { resolve } from '$app/paths';
  /**
   * What gates a ticket close, and who can clear it.
   *
   * The queue at /v2/tickets/approvals answers "what is waiting on me". This
   * answers "what will be gated next time, and by whom", the same rows, a
   * different question, which is why it is a settings page and not a tab.
   *
   * Three states the model permits and the form does not warn about, all
   * flagged on the row here. See `./matching.js`, which owns the rules:
   *
   * - approver_role MANAGER with no named approvers. Profile.role is only
   *   ADMIN or USER, so the rule matches nobody and what it gates can never be
   *   closed by anyone.
   * - Two active rules with identical conditions. Only one rule gates a given
   *   ticket, and among equals the newest takes every case, so the older is
   *   dead however live it looks.
   * - Named approvers read as a narrowing and are a widening: anyone holding
   *   the role clears the rule too.
   *
   * Separation of duties, an admin clearing their own requested close, is
   * NOT a gap to warn about: `ApprovalApproveView` rejects an approval whose
   * requester is the approver, unconditionally (no admin exception), so the API
   * enforces it however a rule is configured. An earlier version of this page
   * flagged "any admin, including the requester" as a hole; the view has since
   * closed it, so the warning is gone.
   */
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import SettingsFormPanel from '#lib/v2/components/SettingsFormPanel.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import { count } from '#lib/v2/format.js';
  import { ROLE_LABEL } from '#lib/v2/enums.js';
  import { missingOptions, missingOption, inactiveOptionLabel } from '#lib/v2/pickers.js';
  import {
    approverSentence,
    clearableByNobody,
    ruleMatchSentence,
    shadowedRuleIds,
    shadowedBy,
    priorityLabel,
    caseTypeLabel
  } from './matching.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { Plus, TriangleAlert, ChevronRight } from '@lucide/svelte';

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();

  // cases.approvals: PRIORITY_CHOICE and CASE_TYPE. Not in `#lib/v2/enums.js`
  // because there is no shared label map to derive from: value and label are
  // the same string for both, and no other v2 page reads either list.
  const MATCH_PRIORITIES = ['Low', 'Normal', 'High', 'Urgent'];
  const MATCH_CASE_TYPES = ['Question', 'Incident', 'Problem'];

  // `ROLE_LABEL` covers `Profile.role` (ADMIN/USER), not the approver-role
  // vocabulary this form offers (ADMIN/MANAGER). MANAGER is not a real
  // `Profile.role` value (see the module docstring), so it has no entry in
  // that map and would render as `undefined`. Labelled here instead.
  function approverRoleLabel(role) {
    return role === 'MANAGER' ? m.settings_approvals_role_manager() : (ROLE_LABEL[role] ?? role);
  }

  // `null` when the panel is closed, `'new'` when adding, or the rule object
  // when editing that row. One panel, two modes, so two rows can never be
  // open for edit at once.
  let editing = $state(/** @type {any} */ (null));

  function openCreate() {
    editing = 'new';
  }

  function openEdit(r) {
    editing = r;
  }

  let totals = $derived(data.totals);
  let rules = $derived(data.rules);

  // Named approvers the picker cannot offer, because the profile has been
  // deactivated since it was named. Without an option of their own the
  // multi-select submits nothing for them and an unrelated edit drops them,
  // which can widen a rule to "any admin" or, on a MANAGER rule, leave it
  // clearable by nobody.
  let missingApprovers = $derived(
    editing && editing !== 'new' ? missingOptions(data.people, editing.approvers) : []
  );

  // The same for the team. Teams have no active flag, so a stored team is
  // missing from the list only when the list failed to load. With no option to
  // match, the select falls back to "Any team" and saving clears the team.
  let missingTeam = $derived(
    editing && editing !== 'new' ? missingOption(data.teams, editing.match_team) : null
  );

  let shadowed = $derived(shadowedRuleIds(rules));

  let subParts = $derived(
    messageParts(m.settings_approvals_sub({ active: slot('active'), pending: slot('pending') }))
  );
</script>

<PageHeader title={m.settings_approvals_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#each subParts as p, i (i)}{#if p.key === 'active'}<span class="v2-num"
          >{count(totals.active)}</span
        >{:else if p.key === 'pending'}<span class="v2-num">{count(totals.pending)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    {#if data.can_edit && !editing}
      <button class="v2-btn v2-btn-primary" onclick={openCreate}
        ><Plus />{m.settings_approvals_new_rule()}</button
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    {#if editing}
      <SettingsFormPanel
        title={editing === 'new'
          ? m.settings_approvals_new_rule()
          : m.settings_approvals_edit_title({ name: editing.name })}
        action={editing === 'new' ? '?/create' : '?/update'}
        error={editing === 'new' ? form?.create?.error : form?.update?.error}
        submitLabel={editing === 'new'
          ? m.settings_approvals_add_rule()
          : m.settings_approvals_save_rule()}
        oncancel={() => (editing = null)}
        ondone={() => (editing = null)}
      >
        {#snippet fields()}
          {#if editing !== 'new'}
            <input type="hidden" name="id" value={editing.id} />
          {/if}

          <div class="v2-field">
            <label for="a-name">{m.settings_approvals_name_label()}</label>
            <input
              id="a-name"
              class="v2-input"
              name="name"
              maxlength="128"
              required
              value={editing === 'new' ? '' : editing.name}
            />
          </div>

          <div class="v2-field">
            <label for="a-role">{m.settings_approvals_role_label()}</label>
            <select id="a-role" class="v2-input" name="approver_role">
              {#each ['ADMIN', 'MANAGER'] as role (role)}
                <option
                  value={role}
                  selected={editing === 'new' ? role === 'ADMIN' : editing.approver_role === role}
                >
                  {approverRoleLabel(role)}
                </option>
              {/each}
            </select>
          </div>

          <div class="v2-field v2-sfp-wide">
            <label for="a-approvers">{m.settings_approvals_named_label()}</label>
            <select
              id="a-approvers"
              class="v2-input"
              name="approver_ids"
              multiple
              style="height:96px"
            >
              <!-- A named approver whose profile is no longer active is not in
                   `data.people`, so it gets an option of its own here. Without
                   one the browser submits nothing for it and saving an
                   unrelated field would drop the approver silently. -->
              {#each missingApprovers as a (a.id)}
                <option value={a.id} selected
                  >{data.options_failed ? a.email : inactiveOptionLabel(a.email)}</option
                >
              {/each}
              {#each data.people as p (p.id)}
                <option
                  value={p.id}
                  selected={editing !== 'new' && editing.approvers.some((a) => a.id === p.id)}
                >
                  {p.name}
                </option>
              {/each}
            </select>
            <p class="v2-hint">
              {m.settings_approvals_named_hint()}
            </p>
            {#if missingApprovers.length && !data.options_failed}
              <p class="v2-hint">
                {m.settings_approvals_inactive_approvers({ count: missingApprovers.length })}
              </p>
            {/if}
          </div>

          <div class="v2-field">
            <label for="a-priority">{m.settings_approvals_priority_label()}</label>
            <select id="a-priority" class="v2-input" name="match_priority">
              <option value="" selected={editing === 'new' || !editing.match_priority}
                >{m.settings_approvals_any()}</option
              >
              {#each MATCH_PRIORITIES as p (p)}
                <option value={p} selected={editing !== 'new' && editing.match_priority === p}>
                  {priorityLabel(p)}
                </option>
              {/each}
            </select>
          </div>

          <div class="v2-field">
            <label for="a-type">{m.settings_approvals_type_label()}</label>
            <select id="a-type" class="v2-input" name="match_case_type">
              <option value="" selected={editing === 'new' || !editing.match_case_type}>
                {m.settings_approvals_any()}
              </option>
              {#each MATCH_CASE_TYPES as t (t)}
                <option value={t} selected={editing !== 'new' && editing.match_case_type === t}>
                  {caseTypeLabel(t)}
                </option>
              {/each}
            </select>
          </div>

          <div class="v2-field">
            <label for="a-team">{m.settings_approvals_team_label()}</label>
            <select id="a-team" class="v2-input" name="match_team_id">
              <option value="" selected={editing === 'new' || !editing.match_team}
                >{m.settings_approvals_any_team()}</option
              >
              {#if missingTeam}
                <option value={missingTeam.id} selected>{missingTeam.name}</option>
              {/if}
              {#each data.teams as t (t.id)}
                <option
                  value={t.id}
                  selected={editing !== 'new' && editing.match_team?.id === t.id}
                >
                  {t.name}
                </option>
              {/each}
            </select>
            {#if data.options_failed}
              <p class="v2-hint" role="alert">
                {editing === 'new'
                  ? m.settings_approvals_options_failed_new()
                  : m.settings_approvals_options_failed_edit()}
              </p>
            {:else if !data.teams.length}
              <p class="v2-hint">{m.settings_approvals_no_teams()}</p>
            {/if}
          </div>

          {#if editing === 'new'}
            <div class="v2-field">
              <label for="a-active">{m.settings_approvals_active_label()}</label>
              <label style="display:flex;gap:8px;align-items:center;font-weight:400">
                <input id="a-active" type="checkbox" name="is_active" value="true" checked />
                {m.settings_approvals_active_hint()}
              </label>
            </div>
          {/if}
        {/snippet}
      </SettingsFormPanel>
    {/if}

    {#if form?.deactivate?.error}
      <p class="v2-error" style="margin-bottom:12px">{form.deactivate.error}</p>
    {/if}
    {#if form?.activate?.error}
      <p class="v2-error" style="margin-bottom:12px">{form.activate.error}</p>
    {/if}
    {#if form?.remove?.error}
      <p class="v2-error" style="margin-bottom:12px">{form.remove.error}</p>
    {/if}
    {#if form?.remove?.turned_off}
      <!-- What actually happened, not what the button said. The backend
           soft-disables a rule that has approval history rather than
           destroying it, so the row is still in the list below, off, and
           saying nothing here would read as a delete that failed silently. -->
      <div class="v2-rule-flag" style="margin-bottom:12px">
        <TriangleAlert size={14} style="color:var(--v2-clay);flex:none" />
        <span>
          {m.settings_approvals_turned_off_note()}
        </span>
      </div>
    {/if}

    <div class="v2-label" style="margin-bottom:4px">{m.settings_approvals_rules_heading()}</div>
    <!-- The list reads as cumulative and is not. Worth one line above it,
         since every row below describes a gate and only one of them is ever
         the gate for a given ticket. -->
    <p class="v2-sub" style="font-size:11.5px;margin:0 0 10px">
      {m.settings_approvals_rules_hint()}
    </p>
    <div style="display:flex;flex-direction:column;gap:9px">
      {#each rules as r (r.id)}
        {@const beatenBy = shadowed.has(r.id) ? shadowedBy(r, rules) : null}
        <div class="v2-card" style="padding:14px 16px;opacity:{r.is_active ? 1 : 0.62}">
          <div style="display:flex;gap:11px;align-items:flex-start">
            <div style="flex:1;min-width:0">
              <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
                <b style="font-size:13.5px">{r.name}</b>
                {#if !r.is_active}<Pill tone="slate">{m.settings_approvals_off()}</Pill>{/if}
                {#if clearableByNobody(r)}<Pill tone="rust"
                    >{m.settings_approvals_nobody_can_clear()}</Pill
                  >{/if}
                {#if beatenBy}<Pill tone="rust">{m.settings_approvals_never_runs()}</Pill>{/if}
              </div>

              <div class="v2-sub" style="font-size:12.5px;margin-top:5px;white-space:normal">
                <b style="font-weight:600;color:var(--v2-ink)">{m.settings_approvals_gates()}</b>
                {ruleMatchSentence(r)}
                <b style="font-weight:600;color:var(--v2-ink)">→</b>
                {m.settings_approvals_cleared_by({ approvers: approverSentence(r) })}
              </div>

              {#if clearableByNobody(r)}
                <div class="v2-rule-flag">
                  <TriangleAlert size={14} style="color:var(--v2-rust);flex:none" />
                  <span>
                    {m.settings_approvals_nobody_flag()}
                  </span>
                </div>
              {/if}

              {#if beatenBy}
                <div class="v2-rule-flag">
                  <TriangleAlert size={14} style="color:var(--v2-rust);flex:none" />
                  <span>
                    {#each messageParts(m.settings_approvals_shadowed_flag( { rule: slot('rule') } )) as p, i (i)}{#if p.key}<b
                          style="font-weight:600;color:var(--v2-ink)">{beatenBy.name}</b
                        >{:else}{p.text}{/if}{/each}
                  </span>
                </div>
              {/if}
            </div>

            <div style="flex:none;text-align:right">
              {#if r.pending_count}
                <a
                  href={resolve('tickets/approvals')}
                  class="v2-sub"
                  style="font-size:12px;display:inline-flex;align-items:center;gap:2px"
                >
                  <span
                    >{#each messageParts(m.settings_approvals_waiting( { count: r.pending_count, shown: slot('shown') } )) as p, i (i)}{#if p.key}<span
                          class="v2-num">{count(r.pending_count)}</span
                        >{:else}{p.text}{/if}{/each}</span
                  >
                  <ChevronRight size={13} />
                </a>
              {/if}
            </div>

            {#if data.can_edit}
              <div style="display:flex;gap:6px;align-items:center;flex:none">
                <button class="v2-btn v2-btn-sm" type="button" onclick={() => openEdit(r)}>
                  {m.settings_approvals_edit()}
                </button>
                {#if r.is_active}
                  <ConfirmAction
                    action="?/deactivate"
                    label={m.settings_approvals_turn_off()}
                    confirmLabel={m.settings_approvals_turn_off()}
                    explain={m.settings_approvals_turn_off_explain()}
                    hidden={{ id: r.id }}
                  />
                {:else}
                  <form method="POST" action="?/activate" use:enhance>
                    <input type="hidden" name="id" value={r.id} />
                    <button class="v2-btn v2-btn-sm" type="submit"
                      >{m.settings_approvals_turn_on()}</button
                    >
                  </form>
                {/if}
                <!-- Not "deleted permanently". The backend destroys a rule
                     only when it has never been used; one with any approval
                     history, in any state, is turned off instead, because the
                     approval rows have to keep pointing at it. `pending_count`
                     cannot predict which happens: it counts only the pending
                     state, and the backend's check counts every state. So the
                     line names both outcomes, and the page reports which one
                     actually happened afterwards. -->
                <ConfirmAction
                  action="?/remove"
                  label={m.settings_approvals_delete()}
                  confirmLabel={m.settings_approvals_delete()}
                  explain={r.pending_count > 0
                    ? m.settings_approvals_delete_explain_pending({ count: r.pending_count })
                    : m.settings_approvals_delete_explain()}
                  hidden={{ id: r.id }}
                />
              </div>
            {/if}
          </div>
        </div>
      {/each}
    </div>
  </div>
</div>

<style>
  .v2-rule-flag {
    display: flex;
    gap: 7px;
    align-items: flex-start;
    margin-top: 9px;
    font-size: 12px;
    color: var(--v2-slate);
    line-height: 1.45;
  }
</style>
