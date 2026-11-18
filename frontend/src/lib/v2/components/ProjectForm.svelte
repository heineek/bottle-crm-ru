<script lang="ts">
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';
  import { untrack } from 'svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { asInternalPath } from '#lib/utils/paths.js';
  import RecordFieldInputs from '#lib/v2/components/RecordFieldInputs.svelte';
  import { CURRENCY_CODES } from '#lib/constants/filters.js';
  import { missingOption, missingOptions, inactiveOptionLabel } from '#lib/v2/pickers.js';
  import {
    PROJECT_STATUSES,
    PROJECT_STATUS_LABEL,
    BILLING_TYPES,
    BILLING_TYPE_LABEL,
    hoursText,
    statusLocked,
    type ProjectFormValues,
    type ProjectValues
  } from '#lib/v2/projects.js';
  import { money } from '#lib/v2/format.js';
  import { Plus, X } from '@lucide/svelte';
  import type { pairForEdit } from '#lib/server/v2/record-fields.js';

  /**
   * The new and edit project form. Values are what the record holds (or the
   * draft from a deal); `typed` is what a refused save sent back, which wins.
   * A stored account, deal, person or currency the pickers cannot offer is
   * kept as its own option, so saving something else never clears it.
   *
   * The people and rates lists post a `__rendered` marker only when the
   * people loaded: without it the action sends neither list, and a page that
   * could not load the team cannot empty the project of it.
   *
   * The money fields (billing type, currency, budgets, rates) are an admin's:
   * a member's form shows them read-only on edit, hides them on create, and
   * sends none of them. The account is set by anyone on create, then only by
   * an admin. The API ignores what a member sends for any of these anyway.
   */
  let {
    action,
    submitLabel,
    values,
    typed = null,
    error = null,
    accounts,
    deals = null,
    people,
    peopleFailed = false,
    stored = {},
    customFields = [],
    fieldErrors = null,
    edit = false,
    isAdmin = false,
    cancelHref
  }: {
    action: string;
    submitLabel: string;
    values: ProjectFormValues;
    typed?: ProjectValues | null;
    error?: string | null;
    accounts: { id: string; name: string }[];
    deals?: { id: string; name: string }[] | null;
    people: { id: string; name: string }[];
    peopleFailed?: boolean;
    stored?: {
      account?: { id: string; name: string } | null;
      deal?: { id: string; name: string } | null;
      people?: { id: string; name: string }[];
    };
    customFields?: ReturnType<typeof pairForEdit>;
    fieldErrors?: Record<string, string> | null;
    edit?: boolean;
    isAdmin?: boolean;
    cancelHref: string;
  } = $props();

  let v = $derived({ ...values, ...(typed ?? {}) });

  let billingType = $state(
    untrack(() => typed?.billing_type || values.billing_type || 'time_and_materials')
  );
  let lockStatus = $derived(statusLocked(edit, isAdmin, values.billing_type));
  let rollover = $state(
    untrack(() => typed?.retainer_rollover ?? values.retainer_rollover ?? false)
  );
  let rates: { key: number; profile: string; hourly_rate: string }[] = $state(
    untrack(() =>
      (typed?.rates ?? values.rates ?? []).map((r, i) => ({
        key: i,
        profile: r.profile ?? '',
        hourly_rate: r.hourly_rate == null ? '' : String(r.hourly_rate)
      }))
    )
  );
  let nextKey = $state(untrack(() => rates.length + 1));
  let busy = $state(false);

  let extraAccount = $derived(missingOption(accounts, stored.account));
  let extraDeal = $derived(deals ? missingOption(deals, stored.deal) : null);
  let extraPeople = $derived(missingOptions(people, stored.people ?? []));
  let allPeople = $derived([
    ...people,
    ...extraPeople.map((p) => ({ id: p.id, name: inactiveOptionLabel(p.name) }))
  ]);
  let currencies = $derived(
    CURRENCY_CODES.filter((c) => c.value).some((c) => c.value === v.currency) || !v.currency
      ? CURRENCY_CODES.filter((c) => c.value)
      : [{ value: v.currency, label: v.currency }, ...CURRENCY_CODES.filter((c) => c.value)]
  );
  let assigned = $derived(new Set(v.assigned_to ?? []));
  let accountName = $derived(
    [...accounts, stored.account].find((a) => a?.id === v.account)?.name ?? ''
  );
  let personName = $derived(
    (id: string) => allPeople.find((p) => p.id === id)?.name ?? m.projects_someone()
  );
  const isSet = (value: unknown) => value !== null && value !== undefined && value !== '';

  function addRate() {
    rates.push({ key: nextKey, profile: '', hourly_rate: '' });
    nextKey += 1;
  }
  function dropRate(key: number) {
    rates = rates.filter((r) => r.key !== key);
  }
</script>

<form
  method="POST"
  {action}
  class="pf"
  use:enhance={() => {
    busy = true;
    return async ({ update }) => {
      busy = false;
      await update({ reset: false });
    };
  }}
>
  {#if error}
    <p class="pf-error" role="alert">{error}</p>
  {/if}

  <label class="v2-field">
    <span class="v2-label">{m.projects_col_project()}</span>
    <input
      class="v2-input"
      name="name"
      required
      maxlength="255"
      value={v.name ?? ''}
      placeholder={m.app_project_form_name_placeholder()}
    />
  </label>

  {#if isAdmin || !edit}
    <label class="v2-field">
      <span class="v2-label">{m.projects_account()}</span>
      <select class="v2-input" name="account" required value={v.account ?? ''}>
        <option value="">{m.app_project_form_choose_client()}</option>
        {#if extraAccount}
          <option value={extraAccount.id}>{extraAccount.name}</option>
        {/if}
        {#each accounts as a (a.id)}
          <option value={a.id}>{a.name}</option>
        {/each}
      </select>
    </label>
  {:else}
    <div class="v2-field">
      <span class="v2-label">{m.projects_account()}</span>
      <p class="pf-static">{accountName || m.projects_not_set()}</p>
    </div>
  {/if}

  {#if deals}
    <label class="v2-field">
      <span class="v2-label">{m.app_project_form_from_deal()}</span>
      <select class="v2-input" name="deal" value={v.deal ?? ''}>
        <option value="">{m.app_project_form_no_deal()}</option>
        {#if extraDeal}
          <option value={extraDeal.id}>{extraDeal.name}</option>
        {/if}
        {#each deals as d (d.id)}
          <option value={d.id}>{d.name}</option>
        {/each}
      </select>
    </label>
  {/if}

  <div class="pf-row">
    {#if lockStatus}
      <div class="v2-field">
        <span class="v2-label">{m.app_project_form_status_admin()}</span>
        <p class="pf-static">{PROJECT_STATUS_LABEL[v.status ?? ''] ?? ''}</p>
      </div>
    {:else}
      <label class="v2-field">
        <span class="v2-label">{m.common_status()}</span>
        <select class="v2-input" name="status" value={v.status || 'active'}>
          {#each PROJECT_STATUSES as s (s)}
            <option value={s}>{PROJECT_STATUS_LABEL[s]}</option>
          {/each}
        </select>
      </label>
    {/if}
    {#if isAdmin}
      <label class="v2-field">
        <span class="v2-label">{m.projects_col_billing()}</span>
        <select class="v2-input" name="billing_type" bind:value={billingType}>
          {#each BILLING_TYPES as b (b)}
            <option value={b}>{BILLING_TYPE_LABEL[b]}</option>
          {/each}
        </select>
      </label>
      <label class="v2-field">
        <span class="v2-label">{m.app_project_form_currency()}</span>
        <select class="v2-input" name="currency" value={v.currency ?? ''}>
          {#each currencies as c (c.value)}
            <option value={c.value}>{c.value}</option>
          {/each}
        </select>
      </label>
    {/if}
  </div>

  {#if isAdmin}
    <div class="pf-row">
      <label class="v2-field">
        <span class="v2-label">{m.projects_field_budget_hours()}</span>
        <input
          class="v2-input"
          name="budget_hours"
          type="number"
          inputmode="decimal"
          min="0"
          step="0.01"
          value={v.budget_hours ?? ''}
          placeholder={m.common_optional()}
        />
      </label>
      <label class="v2-field">
        <span class="v2-label"
          >{billingType === 'fixed_fee'
            ? m.projects_billing_fixed_fee()
            : m.projects_field_budget_amount()}</span
        >
        <input
          class="v2-input"
          name="budget_amount"
          type="number"
          inputmode="decimal"
          min="0"
          step="0.01"
          value={v.budget_amount ?? ''}
          placeholder={m.common_optional()}
        />
      </label>
      <label class="v2-field">
        <span class="v2-label">{m.projects_field_hourly_rate()}</span>
        <input
          class="v2-input"
          name="hourly_rate"
          type="number"
          inputmode="decimal"
          min="0"
          step="0.01"
          value={v.hourly_rate ?? ''}
          placeholder={m.common_optional()}
        />
      </label>
    </div>
    {#if billingType === 'retainer'}
      <input type="hidden" name="retainer__rendered" value="1" />
      <div class="pf-row">
        <label class="v2-field">
          <span class="v2-label">{m.projects_field_monthly_fee()}</span>
          <input
            class="v2-input"
            name="retainer_fee"
            type="number"
            inputmode="decimal"
            min="0.01"
            step="0.01"
            required
            value={v.retainer_fee ?? ''}
          />
        </label>
        <label class="v2-field">
          <span class="v2-label">{m.projects_field_included_hours()}</span>
          <input
            class="v2-input"
            name="retainer_hours"
            type="number"
            inputmode="decimal"
            min="0"
            step="0.01"
            value={v.retainer_hours ?? ''}
            placeholder={m.common_optional()}
          />
        </label>
      </div>
      <div class="pf-row">
        <label class="v2-field">
          <span class="v2-label">{m.projects_field_overage_rate()}</span>
          <input
            class="v2-input"
            name="retainer_overage_rate"
            type="number"
            inputmode="decimal"
            min="0"
            step="0.01"
            value={v.retainer_overage_rate ?? ''}
            placeholder={m.app_project_form_overage_placeholder()}
          />
        </label>
        {#if edit}
          <label class="v2-field">
            <span class="v2-label">{m.projects_field_carried_hours()}</span>
            <input
              class="v2-input"
              name="retainer_carried_hours"
              type="number"
              inputmode="decimal"
              min="0"
              step="0.01"
              value={v.retainer_carried_hours ?? ''}
              placeholder="0"
            />
            <input
              type="hidden"
              name="retainer_carried_hours__loaded"
              value={values.retainer_carried_hours ?? ''}
            />
          </label>
        {/if}
      </div>
      <label class="pf-check">
        <input type="checkbox" name="retainer_rollover" bind:checked={rollover} />
        <span>{m.app_project_form_rollover()}</span>
      </label>
      <p class="v2-sub pf-hint">
        {m.app_project_form_retainer_hint()}
      </p>
    {/if}
    <p class="v2-sub pf-hint">
      {m.app_project_form_rates_hint()}
    </p>
  {:else if edit}
    <div class="v2-field">
      <span class="v2-label">{m.app_project_form_billing_admin()}</span>
      <dl class="v2-kv pf-kv">
        <dt>{m.projects_col_billing()}</dt>
        <dd>{BILLING_TYPE_LABEL[v.billing_type ?? ''] ?? ''}</dd>
        <dt>{m.app_project_form_currency()}</dt>
        <dd>{v.currency ?? ''}</dd>
        <dt>{m.projects_field_budget_hours()}</dt>
        <dd>{isSet(v.budget_hours) ? hoursText(v.budget_hours) : m.projects_not_set()}</dd>
        <dt>
          {v.billing_type === 'fixed_fee'
            ? m.projects_billing_fixed_fee()
            : m.projects_field_budget_amount()}
        </dt>
        <dd>
          {isSet(v.budget_amount) ? money(v.budget_amount, v.currency) : m.projects_not_set()}
        </dd>
        <dt>{m.projects_field_hourly_rate()}</dt>
        <dd>
          {isSet(v.hourly_rate)
            ? m.projects_per_hour({ amount: money(v.hourly_rate, v.currency) })
            : m.projects_not_set()}
        </dd>
        {#if v.billing_type === 'retainer'}
          <dt>{m.projects_field_monthly_fee()}</dt>
          <dd>
            {isSet(v.retainer_fee) ? money(v.retainer_fee, v.currency) : m.projects_not_set()}
          </dd>
          <dt>{m.projects_field_included_hours()}</dt>
          <dd>{isSet(v.retainer_hours) ? hoursText(v.retainer_hours) : m.projects_not_set()}</dd>
          <dt>{m.app_project_form_rollover()}</dt>
          <dd>{v.retainer_rollover ? m.common_yes() : m.common_no()}</dd>
          <dt>{m.projects_field_overage_rate()}</dt>
          <dd>
            {isSet(v.retainer_overage_rate)
              ? m.projects_per_hour({ amount: money(v.retainer_overage_rate, v.currency) })
              : m.projects_not_set()}
          </dd>
        {/if}
        {#each rates as r (r.key)}
          <dt>{personName(r.profile)}</dt>
          <dd>
            {isSet(r.hourly_rate)
              ? m.projects_per_hour({ amount: money(r.hourly_rate, v.currency) })
              : m.projects_not_set()}
          </dd>
        {/each}
      </dl>
    </div>
  {:else}
    <p class="v2-sub pf-hint">
      {m.app_project_form_member_hint()}
    </p>
  {/if}

  <div class="pf-row">
    <label class="v2-field">
      <span class="v2-label">{m.projects_start()}</span>
      <input class="v2-input" type="date" name="start_date" value={v.start_date ?? ''} />
    </label>
    <label class="v2-field">
      <span class="v2-label">{m.projects_col_due()}</span>
      <input class="v2-input" type="date" name="due_date" value={v.due_date ?? ''} />
    </label>
  </div>

  <fieldset class="v2-field pf-set">
    <legend class="v2-label">{m.projects_people()}</legend>
    {#if peopleFailed}
      <p class="v2-sub pf-hint">
        {m.app_project_form_people_failed()}
      </p>
    {:else}
      <input type="hidden" name="assigned__rendered" value="1" />
      <div class="pf-people">
        {#each allPeople as p (p.id)}
          <label class="pf-check">
            <input type="checkbox" name="assigned_to" value={p.id} checked={assigned.has(p.id)} />
            <span>{p.name}</span>
          </label>
        {:else}
          <p class="v2-sub pf-hint">{m.app_project_form_nobody()}</p>
        {/each}
      </div>
    {/if}
  </fieldset>

  {#if isAdmin && !peopleFailed}
    <fieldset class="v2-field pf-set">
      <legend class="v2-label">{m.app_project_form_rates_per_person()}</legend>
      <input type="hidden" name="rates__rendered" value="1" />
      {#each rates as r (r.key)}
        <div class="pf-rate">
          <select
            class="v2-input"
            name="rate_profile"
            bind:value={r.profile}
            aria-label={m.app_list_filters_person()}
          >
            <option value="">{m.app_project_form_choose_person()}</option>
            {#each allPeople as p (p.id)}
              <option value={p.id}>{p.name}</option>
            {/each}
          </select>
          <input
            class="v2-input"
            name="rate_amount"
            type="number"
            inputmode="decimal"
            min="0"
            step="0.01"
            bind:value={r.hourly_rate}
            placeholder={m.app_project_form_rate_per_hour()}
            aria-label={m.app_project_form_rate_per_hour()}
          />
          <button
            type="button"
            class="v2-btn pf-drop"
            onclick={() => dropRate(r.key)}
            aria-label={m.app_project_form_remove_rate()}
            title={m.app_project_form_remove_rate()}
          >
            <X size={13} />
          </button>
        </div>
      {/each}
      <button type="button" class="v2-btn" onclick={addRate}
        ><Plus size={13} />{m.app_project_form_add_rate()}</button
      >
    </fieldset>
  {/if}

  <label class="v2-field">
    <span class="v2-label">{m.common_description()}</span>
    <textarea class="v2-input" name="description" rows="4" value={v.description ?? ''}></textarea>
  </label>

  <RecordFieldInputs
    fields={customFields}
    typed={typed?.custom_fields}
    errors={fieldErrors}
    {edit}
    heading={m.common_details()}
  />

  <div class="pf-actions">
    <button class="v2-btn v2-btn-primary" type="submit" disabled={busy}>{submitLabel}</button>
    <a class="v2-btn" href={resolve(asInternalPath(cancelHref))}>{m.common_cancel()}</a>
  </div>
</form>

<style>
  .pf {
    padding-top: 18px;
    padding-bottom: 36px;
    max-width: 62ch;
    margin-left: auto;
    margin-right: auto;
  }
  .pf-error {
    color: var(--v2-rust);
    font-size: 12.5px;
    margin: 0 0 14px;
  }
  .pf-row {
    display: flex;
    gap: 12px;
    flex-wrap: wrap;
  }
  .pf-row > .v2-field {
    flex: 1 1 150px;
    min-width: 0;
  }
  .pf-hint {
    font-size: 11.5px;
    margin: -6px 0 16px;
  }
  .pf-set {
    border: 0;
    padding: 0;
    margin: 0 0 16px;
    min-width: 0;
  }
  .pf-set legend {
    margin-bottom: 6px;
  }
  .pf-people {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
    gap: 2px 12px;
    max-height: 240px;
    overflow-y: auto;
  }
  .pf-check {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 36px;
    font-size: 13px;
    cursor: pointer;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .pf-rate {
    display: grid;
    grid-template-columns: minmax(0, 2fr) minmax(0, 1fr) auto;
    gap: 8px;
    margin-bottom: 8px;
  }
  .pf-static {
    margin: 0;
    font-size: 13px;
    font-weight: 500;
    overflow-wrap: anywhere;
  }
  .pf-kv {
    margin-top: 4px;
  }
  .pf-actions {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    margin-top: 8px;
  }
  @media (max-width: 768px) {
    .pf-check,
    .pf-actions .v2-btn,
    .pf-set .v2-btn,
    .pf .v2-input {
      min-height: 44px;
    }
  }
</style>
