<script>
  import { resolve } from '$app/paths';
  /**
   * Adding a lead.
   *
   * A brand-new org cannot add its first lead through the web UI without this
   * page. `/leads` has always rendered a "New lead" button; nothing was ever
   * behind it. See CLAUDE.md, "API Validation & Authorization": the checks
   * below are a courtesy that saves a round trip, not the rule. The
   * serializer runs again on everything that arrives, and a curl request or a
   * stale build reaches it without ever loading this file.
   *
   * Nothing here binds to `org`, `created_by`, or an assigned-by field. Those
   * are server-derived; `createLead` never reads them off the form, and the
   * action below only ever forwards keys named in `EDITABLE_FIELDS`.
   */
  import { tick, untrack } from 'svelte';
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import DuplicateNotice from '#lib/v2/components/DuplicateNotice.svelte';
  import {
    LEAD_STATUSES,
    LEAD_STATUS_LABEL,
    LEAD_SOURCES,
    LEAD_SOURCE_LABEL,
    INDUSTRIES,
    industryLabel
  } from '#lib/v2/enums.js';
  import { money } from '#lib/v2/format.js';
  import { TriangleAlert } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';

  /** @type {{ data: any, form: any }} */
  let { data, form: result } = $props();

  // Seeded from the load once, on purpose: a half-typed form must not be
  // wiped if the page data revalidates underneath it. untrack() says that
  // out loud rather than leaving it as an accident.
  let form = $state(
    untrack(() => ({
      first_name: '',
      last_name: '',
      company_name: '',
      email: '',
      assigned_to: data.defaults.assigned_to,
      job_title: '',
      phone: '',
      website: '',
      status: data.defaults.status,
      source: '',
      industry: '',
      opportunity_amount: '',
      description: '',
      // A rejected submit comes back with what was typed. Retyping a dozen
      // fields because one collided is how people learn to distrust a create
      // page.
      ...(untrack(() => result?.values) ?? {})
    }))
  );

  let touched = $state(/** @type {Record<string, boolean>} */ ({}));
  let submitted = $state(false);

  // Disables the submit button while the create action is in flight, so a
  // double-click cannot fire two creates.
  let busy = $state(false);

  let errors = $derived.by(() => {
    /** @type {Record<string, string>} */
    const e = {};
    // Mirrors the edit form's own rule: a lead needs a name to be findable,
    // but not both halves of one. Neither half is required by the API
    // itself (Lead.first_name/last_name are both nullable), so this is a UX
    // floor, not the boundary; an empty lead would otherwise save silently
    // and be unfindable in the list a moment later.
    if (!form.first_name.trim() && !form.last_name.trim()) e.last_name = m.leads_error_name();

    if (form.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email))
      e.email = m.leads_error_email_invalid();

    // The exact regex from `flexible_phone_validator`. Extensions like "x123"
    // are rejected by the model, so they are caught here rather than as an
    // opaque whole-form refusal after the save.
    if (form.phone && !/^[\d\s\-()+.]{7,25}$/.test(form.phone))
      e.phone = m.leads_error_phone_format();

    // `createLead` runs `Number(amount)` and the body is JSON-encoded, and
    // `JSON.stringify` turns `NaN` into `null`. Without this check, typing
    // "abc" would not error, it would silently save as no value at all.
    if (form.opportunity_amount !== '') {
      const n = Number(form.opportunity_amount);
      if (!Number.isFinite(n)) e.opportunity_amount = m.leads_error_amount_nan();
      else if (n < 0) e.opportunity_amount = m.leads_error_amount_negative();
    }

    return e;
  });

  let valid = $derived(Object.keys(errors).length === 0);
  const show = (/** @type {string} */ field) => (touched[field] || submitted) && errors[field];

  /**
   * On success the action redirects to the new lead, so there is no success
   * state to render here.
   *
   * @type {import('./$types').SubmitFunction}
   */
  const check = async ({ cancel }) => {
    submitted = true;
    if (!valid) {
      // Send focus to the first field that needs work rather than only
      // colouring it. await tick() matters: on the first submit the
      // aria-invalid attributes do not exist until Svelte flushes, so
      // querying now finds nothing.
      cancel();
      await tick();
      /** @type {HTMLElement | null} */
      const first = document.querySelector('[aria-invalid="true"]');
      first?.focus();
      return;
    }
    busy = true;
    return async (/** @type {any} */ { update }) => {
      await update();
      busy = false;
    };
  };
</script>

<PageHeader title={m.leads_new_title()} center>
  {#snippet crumb()}
    <a href={resolve('leads')}>{m.leads_term_plural()}</a> ›
  {/snippet}
  {#snippet sub()}
    {m.leads_new_sub()}
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
          <div style="font-weight:600">{m.leads_form_server_refused_lead()}</div>
          <div class="v2-sub" style="margin-top:2px">{result.error}</div>
        </div>
      </div>
    {/if}

    {#if submitted && !valid}
      <div
        class="v2-next"
        style="background:color-mix(in srgb, var(--v2-rust) 9%, transparent);border-color:color-mix(in srgb, var(--v2-rust) 28%, transparent);margin-bottom:18px"
        role="alert"
      >
        <TriangleAlert size={17} style="color:var(--v2-rust);flex:none" />
        <div class="v2-next-body">
          <div style="font-weight:600">
            {m.leads_form_fields_need_you({ count: Object.keys(errors).length })}
          </div>
          <div class="v2-sub" style="margin-top:2px">{m.leads_form_nothing_saved()}</div>
        </div>
      </div>
    {/if}

    <div class="v2-field">
      <label for="f-first">{m.leads_field_first_name()}</label>
      <input
        id="f-first"
        name="first_name"
        class="v2-input"
        bind:value={form.first_name}
        onblur={() => (touched.first_name = true)}
      />
    </div>
    <div class="v2-field">
      <label for="f-last">{m.leads_field_last_name()}</label>
      <input
        id="f-last"
        name="last_name"
        class="v2-input"
        bind:value={form.last_name}
        onblur={() => (touched.last_name = true)}
        aria-invalid={show('last_name') ? 'true' : undefined}
        aria-describedby={show('last_name') ? 'e-last' : undefined}
      />
      {#if show('last_name')}<p class="v2-error" id="e-last">{errors.last_name}</p>{/if}
    </div>
    <div class="v2-field">
      <label for="f-company">{m.leads_field_company()}</label>
      <input id="f-company" name="company_name" class="v2-input" bind:value={form.company_name} />
    </div>
    <div class="v2-field">
      <label for="f-email">{m.common_email()}</label>
      <input
        id="f-email"
        name="email"
        class="v2-input"
        type="email"
        bind:value={form.email}
        onblur={() => (touched.email = true)}
        aria-invalid={show('email') ? 'true' : undefined}
        aria-describedby={show('email') ? 'e-email' : undefined}
      />
      {#if show('email')}<p class="v2-error" id="e-email">{errors.email}</p>{/if}
    </div>
    <div class="v2-field">
      <label for="f-owner">{m.common_owner()}</label>
      <select id="f-owner" name="assigned_to" class="v2-input" bind:value={form.assigned_to}>
        <option value="">{m.leads_field_unassigned()}</option>
        {#each data.owners as o (o.id)}
          <option value={o.id}>{o.name}</option>
        {/each}
      </select>
    </div>
    <div class="v2-field">
      <label for="f-jobtitle">{m.leads_field_job_title()}</label>
      <input id="f-jobtitle" name="job_title" class="v2-input" bind:value={form.job_title} />
    </div>
    <div class="v2-field">
      <label for="f-phone">{m.common_phone()}</label>
      <input
        id="f-phone"
        name="phone"
        class="v2-input"
        bind:value={form.phone}
        onblur={() => (touched.phone = true)}
        aria-invalid={show('phone') ? 'true' : undefined}
        aria-describedby={show('phone') ? 'e-phone' : undefined}
      />
      {#if show('phone')}<p class="v2-error" id="e-phone">{errors.phone}</p>{/if}
    </div>
    <div class="v2-field">
      <label for="f-website">{m.leads_field_website()}</label>
      <input id="f-website" name="website" class="v2-input" bind:value={form.website} />
    </div>
    <div class="v2-field">
      <label for="f-status">{m.common_status()}</label>
      <select id="f-status" name="status" class="v2-input" bind:value={form.status}>
        {#each LEAD_STATUSES.filter((s) => s !== 'converted') as s (s)}
          <option value={s}>{LEAD_STATUS_LABEL[s]}</option>
        {/each}
      </select>
      <p class="v2-hint">
        {m.leads_new_status_hint()}
      </p>
    </div>
    <div class="v2-field">
      <label for="f-source">{m.leads_field_source()}</label>
      <select id="f-source" name="source" class="v2-input" bind:value={form.source}>
        <option value="">{m.leads_field_not_specified()}</option>
        {#each LEAD_SOURCES as s (s)}
          <option value={s}>{LEAD_SOURCE_LABEL[s]}</option>
        {/each}
      </select>
    </div>
    <div class="v2-field">
      <label for="f-industry">{m.leads_field_industry()}</label>
      <select id="f-industry" name="industry" class="v2-input" bind:value={form.industry}>
        <option value="">{m.leads_field_not_specified()}</option>
        {#each INDUSTRIES as ind (ind)}
          <option value={ind}>{industryLabel(ind)}</option>
        {/each}
      </select>
    </div>
    <div class="v2-field">
      <label for="f-amount">{m.leads_field_estimated_value()}</label>
      <input
        id="f-amount"
        name="opportunity_amount"
        class="v2-input v2-num"
        type="number"
        step="any"
        bind:value={form.opportunity_amount}
        onblur={() => (touched.opportunity_amount = true)}
        aria-invalid={show('opportunity_amount') ? 'true' : undefined}
        aria-describedby={show('opportunity_amount') ? 'e-amount' : 'h-amount'}
      />
      {#if show('opportunity_amount')}
        <p class="v2-error" id="e-amount">{errors.opportunity_amount}</p>
      {:else}
        <p class="v2-hint" id="h-amount">
          {Number(form.opportunity_amount) > 0
            ? money(Number(form.opportunity_amount), data.org.currency)
            : m.leads_field_value_hint()}
        </p>
      {/if}
    </div>
    <div class="v2-field">
      <label for="f-notes">{m.common_notes()}</label>
      <textarea
        id="f-notes"
        name="description"
        class="v2-input"
        rows="4"
        bind:value={form.description}></textarea>
    </div>

    <DuplicateNotice
      module="leads"
      values={{
        email: form.email,
        phone: form.phone,
        first_name: form.first_name,
        last_name: form.last_name,
        company_name: form.company_name
      }}
    />

    <div class="actions">
      <button class="v2-btn v2-btn-primary" type="submit" disabled={busy}
        >{m.leads_new_submit()}</button
      >
      <a class="v2-btn" href={resolve('leads')}>{m.common_cancel()}</a>
    </div>
  </form>
</div>

<style>
  .actions {
    display: flex;
    align-items: center;
    gap: 9px;
    margin-top: 22px;
    padding-bottom: 40px;
  }
</style>
