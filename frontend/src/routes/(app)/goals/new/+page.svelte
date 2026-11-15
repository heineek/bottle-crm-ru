<script>
  import { resolve } from '$app/paths';
  import { untrack, tick } from 'svelte';
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import DealTypeWeights from '#lib/v2/components/DealTypeWeights.svelte';
  import { GOAL_TYPE_LABEL, PERIOD_TYPE_LABEL } from '#lib/v2/enums.js';
  import { money, count } from '#lib/v2/format.js';
  import { CURRENCY_CODES } from '#lib/constants/filters.js';
  import { TriangleAlert } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';

  /** @type {{ data: any, form: any }} */
  let { data, form: result } = $props();

  /**
   * A goal is a target and a period, aimed at someone. This asks for exactly
   * that and nothing more, v1's quota form asked for fields the model does not
   * even store.
   *
   * VALIDATION HERE IS A UX HINT, NOT A RULE. Everything below only decides what
   * this page shows. The serializer enforces the same constraints server-side:
   * a positive target, an end after the start, and (the one that matters) an
   * assignee or team that belongs to *this* org, because curl and the mobile
   * client reach the API without passing through this file. See CLAUDE.md,
   * "API Validation & Authorization".
   *
   * Note what is NOT on this form: org and created_by. Those are server-derived
   * from the session; if they ever appeared in a body the serializer would have
   * to reject them.
   */
  let form = $state(
    untrack(() => ({
      name: '',
      goal_type: 'REVENUE',
      target_value: '',
      currency: data.org.currency,
      period_type: 'MONTHLY',
      period_start: '',
      period_end: '',
      target: 'org',
      ...(untrack(() => result?.values) ?? {})
    }))
  );

  let touched = $state(/** @type {Record<string, boolean>} */ ({}));
  let submitted = $state(false);

  const REQUIRED = ['name', 'target_value', 'period_start', 'period_end'];

  let errors = $derived.by(() => {
    /** @type {Record<string, string>} */
    const e = {};
    if (!form.name.trim()) e.name = m.goals_form_name_error();

    const target = Number(form.target_value);
    if (form.target_value === '') e.target_value = m.goals_form_target_required();
    else if (!Number.isFinite(target) || target <= 0)
      e.target_value = m.goals_form_target_invalid();

    if (!form.period_start) e.period_start = m.goals_form_start_required();
    if (!form.period_end) e.period_end = m.goals_form_end_required();
    else if (form.period_start && form.period_end <= form.period_start)
      e.period_end = m.goals_form_end_before_start();

    return e;
  });

  let valid = $derived(Object.keys(errors).length === 0);
  const show = (field) => (touched[field] || submitted) && errors[field];

  const unit = (n) => (form.goal_type === 'REVENUE' ? money(n, form.currency) : count(n));

  // The empty "Select Currency" placeholder is dropped: a goal always has one.
  const currencyOptions = CURRENCY_CODES.filter((c) => c.value);

  /** @type {import('./$types').SubmitFunction} */
  const check = async ({ cancel }) => {
    submitted = true;
    if (!valid) {
      cancel();
      await tick();
      /** @type {HTMLElement | null} */
      const first = document.querySelector('[aria-invalid="true"]');
      first?.focus();
    }
  };
</script>

{#if !data.can_edit}
  <PageHeader title={m.goals_new_title()}>
    {#snippet crumb()}<a href={resolve('goals')}>{m.goals_title()}</a> ›{/snippet}
  </PageHeader>
  <div class="v2-pad" style="padding-top:40px">
    <NextAction label={m.common_admins_only()} text={m.goals_form_new_admins_text()} />
  </div>
{:else}
  <PageHeader title={m.goals_new_title()} center>
    {#snippet crumb()}<a href={resolve('goals')}>{m.goals_title()}</a> ›{/snippet}
    {#snippet sub()}
      {m.goals_form_new_sub()}
    {/snippet}
  </PageHeader>

  <div class="v2-scroll v2-pad" style="padding-top:18px">
    <form class="v2-form" method="POST" action="?/create" use:enhance={check} novalidate>
      {#if result?.error}
        <div
          class="v2-next"
          style="background:color-mix(in srgb, var(--v2-rust) 9%, transparent);border-color:color-mix(in srgb, var(--v2-rust) 28%, transparent);margin-bottom:18px"
          role="alert"
        >
          <TriangleAlert size={17} style="color:var(--v2-rust);flex:none" />
          <div class="v2-next-body">
            <div style="font-weight:600">{m.goals_form_new_refused()}</div>
            <div class="v2-sub" style="margin-top:2px">{result.error}</div>
          </div>
        </div>
      {/if}

      <div class="v2-field">
        <label for="f-name">{m.goals_form_name_label()}</label>
        <input
          id="f-name"
          name="name"
          class="v2-input"
          bind:value={form.name}
          onblur={() => (touched.name = true)}
          aria-invalid={show('name') ? 'true' : undefined}
          aria-describedby={show('name') ? 'e-name' : 'h-name'}
          placeholder={m.goals_form_name_placeholder()}
        />
        {#if show('name')}
          <p class="v2-error" id="e-name">{errors.name}</p>
        {:else}
          <p class="v2-hint" id="h-name">
            {m.goals_form_name_hint()}
          </p>
        {/if}
      </div>

      <div class="v2-pair">
        <div class="v2-field">
          <label for="f-type">{m.goals_form_type_label()}</label>
          <select id="f-type" name="goal_type" class="v2-input" bind:value={form.goal_type}>
            {#each Object.entries(GOAL_TYPE_LABEL) as [key, label] (key)}
              <option value={key}>{label}</option>
            {/each}
          </select>
          <p class="v2-hint">
            {m.goals_form_type_hint()}
          </p>
        </div>

        <div class="v2-field">
          <label for="f-target">{m.goals_form_target_label()}</label>
          <input
            id="f-target"
            name="target_value"
            class="v2-input v2-num"
            type="text"
            inputmode="decimal"
            bind:value={form.target_value}
            onblur={() => (touched.target_value = true)}
            aria-invalid={show('target_value') ? 'true' : undefined}
            aria-describedby={show('target_value') ? 'e-target' : 'h-target'}
            placeholder={form.goal_type === 'REVENUE' ? '450000' : '12'}
          />
          {#if show('target_value')}
            <p class="v2-error" id="e-target">{errors.target_value}</p>
          {:else}
            <p class="v2-hint" id="h-target">
              {Number(form.target_value) > 0 ? unit(Number(form.target_value)) : '—'}
            </p>
          {/if}
        </div>
      </div>

      <!-- Money goals only: a count of deals or activities has no currency.
           Left off the form for those, so the body omits it and the server
           keeps (or, on create, defaults) the org's currency. -->
      {#if form.goal_type === 'REVENUE'}
        <div class="v2-field">
          <label for="f-currency">{m.goals_form_currency_label()}</label>
          <select id="f-currency" name="currency" class="v2-input" bind:value={form.currency}>
            {#each currencyOptions as c (c.value)}
              <option value={c.value}>{c.label}</option>
            {/each}
          </select>
          <p class="v2-hint">
            {m.goals_form_currency_hint()}
          </p>
        </div>
      {/if}

      <div class="v2-field">
        <label for="f-period">{m.goals_form_period_label()}</label>
        <select id="f-period" name="period_type" class="v2-input" bind:value={form.period_type}>
          {#each Object.entries(PERIOD_TYPE_LABEL) as [key, label] (key)}
            <option value={key}>{label}</option>
          {/each}
        </select>
        <p class="v2-hint">{m.goals_form_period_hint()}</p>
      </div>

      <DealTypeWeights weights={{}} goalType={form.goal_type} />

      <div class="v2-pair">
        <div class="v2-field">
          <label for="f-start">{m.goals_form_start_label()}</label>
          <input
            id="f-start"
            name="period_start"
            class="v2-input"
            type="date"
            bind:value={form.period_start}
            onblur={() => (touched.period_start = true)}
            aria-invalid={show('period_start') ? 'true' : undefined}
            aria-describedby={show('period_start') ? 'e-start' : undefined}
          />
          {#if show('period_start')}<p class="v2-error" id="e-start">{errors.period_start}</p>{/if}
        </div>

        <div class="v2-field">
          <label for="f-end">{m.goals_form_end_label()}</label>
          <input
            id="f-end"
            name="period_end"
            class="v2-input"
            type="date"
            bind:value={form.period_end}
            onblur={() => (touched.period_end = true)}
            aria-invalid={show('period_end') ? 'true' : undefined}
            aria-describedby={show('period_end') ? 'e-end' : undefined}
          />
          {#if show('period_end')}<p class="v2-error" id="e-end">{errors.period_end}</p>{/if}
        </div>
      </div>

      <div class="v2-field">
        <label for="f-owner">{m.goals_form_owner_label()}</label>
        <select id="f-owner" name="target" class="v2-input" bind:value={form.target}>
          <option value="org">{m.goals_owner_whole_org()}</option>
          {#if data.people?.length}
            <optgroup label={m.goals_form_owner_person()}>
              {#each data.people as p (p.id)}
                <option value="profile:{p.id}">{p.name}</option>
              {/each}
            </optgroup>
          {/if}
          {#if data.teams?.length}
            <optgroup label={m.goals_form_owner_team()}>
              {#each data.teams as t (t.id)}
                <option value="team:{t.id}">{t.name}</option>
              {/each}
            </optgroup>
          {/if}
        </select>
        <p class="v2-hint">
          {m.goals_form_owner_hint()}
        </p>
      </div>

      <div style="display:flex;gap:8px;align-items:center;margin-top:22px">
        <button class="v2-btn v2-btn-primary" type="submit">{m.goals_form_create_button()}</button>
        <a class="v2-btn" href={resolve('goals')}>{m.common_cancel()}</a>
        <span class="v2-sub" style="margin-left:auto;font-size:12px">
          {#each messageParts(m.goals_form_required_done( { done: slot('done'), total: slot('total') } )) as p, i (i)}{#if p.key === 'done'}<span
                class="v2-num">{REQUIRED.filter((f) => !errors[f]).length}</span
              >{:else if p.key === 'total'}<span class="v2-num">{REQUIRED.length}</span
              >{:else}{p.text}{/if}{/each}
        </span>
      </div>
    </form>
  </div>
{/if}

<style>
  .v2-pair {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
  }
  @media (max-width: 720px) {
    .v2-pair {
      grid-template-columns: 1fr;
    }
  }
</style>
