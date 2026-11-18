<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * Editing the organisation.
   *
   * Admin-only. A non-admin who reaches this URL directly gets an "Admins only"
   * state, not the form, but that is the courtesy, not the control: the save
   * posts to `PATCH /api/org/settings/`, which the backend refuses for anyone
   * whose role is not ADMIN. `result.error` reports that refusal.
   *
   * What this form owns is the org's own settings: the company profile printed
   * on invoices, the locale defaults, and the two org-wide case-handling
   * switches. What it deliberately does NOT own: the org API key (a credential,
   * rotated through its own audited action) and `is_active` (the org kill
   * switch). Neither is a field here, and the server would not accept them if
   * they were smuggled into the request.
   *
   * The two switches submit an explicit on/off, so turning one OFF is a real
   * choice the save records, not the "left blank, so unchanged" behaviour of
   * the text fields.
   *
   * Invoice numbering (#802) shows a live example of the format. The starting
   * number only applies to undated numbers, so with a date part chosen the
   * field is replaced by a hidden 1: the server refuses a start with a date,
   * including a start already stored when a date is added.
   */
  import { tick, untrack } from 'svelte';
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import { CURRENCY_CODES } from '#lib/constants/filters.js';
  import {
    exampleNumber,
    NUMBER_DATE_PARTS,
    NUMBER_PREFIX_PATTERN
  } from '#lib/v2/document-numbers.js';
  import { todayIn } from '#lib/v2/dates.js';
  import { sortedCountries } from '#lib/constants/countries.js';
  import { ChevronRight, TriangleAlert } from '@lucide/svelte';
  import { isOn } from '#lib/v2/modules.js';
  import { isLocale, locales } from '#lib/paraglide/runtime.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { components } from '#lib/api-schema.js';
  import {
    DOCS_LEAD_ALERTS,
    REMINDER_CHOICES,
    reminderExtra,
    reminderLabel
  } from '#lib/v2/lead-alerts.js';
  import type { PageProps, SubmitFunction } from './$types';

  let { data, form: result }: PageProps = $props();

  // A switched-off module's fields are left out, and the save sends only what
  // the form submits, so their stored values stay as they are.
  let invoicesOn = $derived(isOn(data.modules, 'invoices'));
  let ticketsOn = $derived(isOn(data.modules, 'tickets'));
  let leadsOn = $derived(isOn(data.modules, 'leads'));

  // A supported currency is required (the column is non-blank with a default),
  // so the empty "Select Currency" placeholder is dropped from the options.
  const currencyOptions = CURRENCY_CODES.filter((c) => c.value);

  // The full list the backend COUNTRIES accepts, so every stored code has an
  // option. A code missing here would leave the select on its first entry and
  // the next save would silently clear the org's country.
  const countryOptions = sortedCountries().map((c) => ({ value: c.code, label: c.name }));

  const org: Partial<components['schemas']['OrgSettings']> = untrack(() => data.org ?? {});
  // Always includes the org's current value, because the API builds the list
  // from the same database the value was validated against. A stored zone with
  // no matching option would make the select submit its first entry instead.
  const reminderOptions = [...REMINDER_CHOICES, ...reminderExtra(org.lead_reminder_minutes)].sort(
    (a, b) => a - b
  );
  const timezones = untrack(() => data.timezones ?? [{ name: 'UTC', label: 'UTC' }]);
  // A stored language this build has no messages for still needs an option,
  // or the select would submit another one in its place.
  const languageOptions = untrack(() =>
    isLocale(org.default_language) || !org.default_language
      ? [...locales]
      : [org.default_language, ...locales]
  );
  // For the numbering example only; the server dates a number on save.
  const today = untrack(() => todayIn(org.timezone || 'UTC'));

  let form = $state(
    untrack(() => ({
      name: org.name ?? '',
      company_name: org.company_name ?? '',
      address_line: org.address_line ?? '',
      city: org.city ?? '',
      state: org.state ?? '',
      postcode: org.postcode ?? '',
      country: org.country ?? '',
      phone: org.phone ?? '',
      email: org.email ?? '',
      website: org.website ?? '',
      tax_id: org.tax_id ?? '',
      default_currency: org.default_currency || 'USD',
      default_country: org.default_country ?? '',
      timezone: org.timezone || 'UTC',
      default_language: org.default_language ?? '',
      lead_reminder_minutes: String(org.lead_reminder_minutes ?? ''),
      // Booleans travel as strings so the select always submits an explicit value.
      csat_enabled: String(org.csat_enabled ?? true),
      auto_close_children_on_parent_close: String(org.auto_close_children_on_parent_close ?? false),
      invoice_number_prefix: org.invoice_number_prefix ?? 'INV-',
      estimate_number_prefix: org.estimate_number_prefix ?? 'EST-',
      number_date_part: org.number_date_part || 'DAY',
      number_padding: org.number_padding ?? 4,
      invoice_number_start: org.invoice_number_start ?? 1
    }))
  );

  let touched = $state<Record<string, boolean>>({});
  let submitted = $state(false);

  let errors = $derived.by(() => {
    const e: Record<string, string> = {};
    if (form.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(form.email))
      e.email = m.settings_org_edit_err_email();
    // The model stores this in a URLField, which wants a real URL. A light check
    // here saves a server round-trip; the serializer is the actual rule.
    if (form.website && !/^https?:\/\/.+\..+/.test(form.website))
      e.website = m.settings_org_edit_err_website();
    if (!invoicesOn) return e;
    const prefixFields: ('invoice_number_prefix' | 'estimate_number_prefix')[] = [
      'invoice_number_prefix',
      'estimate_number_prefix'
    ];
    for (const field of prefixFields) {
      if (!NUMBER_PREFIX_PATTERN.test(form[field].trim()))
        e[field] = m.settings_org_edit_err_prefix();
    }
    if (!wholeIn(form.number_padding, 1, 10)) e.number_padding = m.settings_org_edit_err_padding();
    if (form.number_date_part === 'NONE' && !wholeIn(form.invoice_number_start, 1, 999999999))
      e.invoice_number_start = m.settings_org_edit_err_start();
    return e;
  });

  function wholeIn(value: unknown, min: number, max: number) {
    const n = Number(value);
    return value !== '' && value !== null && Number.isInteger(n) && n >= min && n <= max;
  }

  let valid = $derived(Object.keys(errors).length === 0);
  const show = (field: string) => (touched[field] || submitted) && errors[field];

  /**
   * These checks are a UX hint. The serializer is the rule, and its 400 is what
   * `result.error` reports.
   */
  const check: SubmitFunction = async ({ cancel }) => {
    submitted = true;
    if (!valid) {
      cancel();
      await tick();
      const first: HTMLElement | null = document.querySelector('[aria-invalid="true"]');
      first?.focus();
      return;
    }
    return async ({ update }) => {
      // Keep the entered values on a server rejection so nothing is retyped.
      await update({ reset: false });
    };
  };
</script>

{#if data.forbidden}
  <PageHeader title={m.settings_hub_org_title()}>
    {#snippet crumb()}<SettingsCrumb />{/snippet}
  </PageHeader>
  <div class="v2-pad" style="padding-top:40px">
    <NextAction label={m.common_admins_only()} text={m.settings_org_edit_forbidden()} />
  </div>
{:else}
  <PageHeader title={m.settings_org_edit_title()} center>
    {#snippet crumb()}
      <a href={resolve('settings')}>{m.common_settings()}</a>
      <ChevronRight size={12} />
      <a href={resolve('settings/organization')}>{m.settings_hub_org_title()}</a>
    {/snippet}
  </PageHeader>

  <div class="v2-scroll v2-pad" style="padding-top:18px">
    <form class="v2-form" method="POST" action="?/save" use:enhance={check} novalidate>
      {#if result?.error}
        <div
          class="v2-next"
          style="background:color-mix(in srgb, var(--v2-rust) 9%, transparent);border-color:color-mix(in srgb, var(--v2-rust) 28%, transparent);margin-bottom:18px"
          role="alert"
        >
          <TriangleAlert size={17} style="color:var(--v2-rust);flex:none" />
          <div class="v2-next-body">
            <div style="font-weight:600">{m.settings_org_edit_refused()}</div>
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
            <!-- Counted, not assumed: one field failing on its own is the
                 common case. -->
            <div style="font-weight:600">
              {Object.keys(errors).length === 1
                ? m.settings_org_edit_one_field()
                : m.settings_org_edit_fields({ count: Object.keys(errors).length })}
            </div>
            <div class="v2-sub" style="margin-top:2px">{m.settings_org_edit_nothing_saved()}</div>
          </div>
        </div>
      {/if}

      <div class="v2-label" style="margin-bottom:12px">{m.settings_org_customers_see()}</div>
      {#if invoicesOn}
        <p class="v2-hint" style="margin-top:-4px;margin-bottom:14px">
          {m.settings_org_edit_printed_hint()}
        </p>
      {/if}

      <div class="v2-field">
        <label for="f-company">{m.settings_org_legal_name()}</label>
        <input
          id="f-company"
          name="company_name"
          class="v2-input"
          maxlength="255"
          bind:value={form.company_name}
        />
        <p class="v2-hint">{m.settings_org_edit_legal_hint()}</p>
      </div>

      <div class="v2-field">
        <label for="f-name">{m.settings_org_edit_trading_name()}</label>
        <input id="f-name" name="name" class="v2-input" maxlength="100" bind:value={form.name} />
        <p class="v2-hint">{m.settings_org_edit_trading_hint()}</p>
      </div>

      <div class="pair">
        <div class="v2-field">
          <label for="f-tax">{m.settings_org_tax_id()}</label>
          <input
            id="f-tax"
            name="tax_id"
            class="v2-input"
            maxlength="50"
            bind:value={form.tax_id}
          />
        </div>
        <div class="v2-field">
          <label for="f-phone">{m.common_phone()}</label>
          <input
            id="f-phone"
            name="phone"
            class="v2-input"
            maxlength="25"
            bind:value={form.phone}
          />
        </div>
      </div>

      <div class="pair">
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
          />
          {#if show('email')}<p class="v2-error">{errors.email}</p>{/if}
        </div>
        <div class="v2-field">
          <label for="f-website">{m.settings_org_website()}</label>
          <input
            id="f-website"
            name="website"
            class="v2-input"
            type="url"
            bind:value={form.website}
            onblur={() => (touched.website = true)}
            aria-invalid={show('website') ? 'true' : undefined}
          />
          {#if show('website')}<p class="v2-error">{errors.website}</p>{/if}
        </div>
      </div>

      <div class="v2-field">
        <label for="f-address">{m.settings_org_address()}</label>
        <input
          id="f-address"
          name="address_line"
          class="v2-input"
          maxlength="255"
          bind:value={form.address_line}
        />
      </div>

      <div class="triple">
        <div class="v2-field">
          <label for="f-city">{m.settings_org_edit_city()}</label>
          <input id="f-city" name="city" class="v2-input" maxlength="100" bind:value={form.city} />
        </div>
        <div class="v2-field">
          <label for="f-state">{m.settings_org_edit_state()}</label>
          <input
            id="f-state"
            name="state"
            class="v2-input"
            maxlength="100"
            bind:value={form.state}
          />
        </div>
        <div class="v2-field">
          <label for="f-postcode">{m.settings_org_edit_postcode()}</label>
          <input
            id="f-postcode"
            name="postcode"
            class="v2-input"
            maxlength="20"
            bind:value={form.postcode}
          />
        </div>
      </div>

      <div class="v2-field">
        <label for="f-country">{m.settings_org_country()}</label>
        <select id="f-country" name="country" class="v2-input" bind:value={form.country}>
          <option value="">{m.settings_org_edit_not_recorded()}</option>
          {#each countryOptions as c (c.value)}
            <option value={c.value}>{c.label}</option>
          {/each}
        </select>
      </div>

      <div class="v2-label" style="margin:24px 0 12px">{m.settings_org_defaults()}</div>
      <div class="pair">
        <div class="v2-field">
          <label for="f-currency">{m.settings_org_currency()}</label>
          <select
            id="f-currency"
            name="default_currency"
            class="v2-input"
            bind:value={form.default_currency}
          >
            {#each currencyOptions as c (c.value)}
              <option value={c.value}>{c.label}</option>
            {/each}
          </select>
          <p class="v2-hint">
            {invoicesOn ? m.settings_org_currency_hint_invoices() : m.settings_org_currency_hint()}
          </p>
        </div>
        <div class="v2-field">
          <label for="f-defcountry">{m.settings_org_edit_country_default()}</label>
          <select
            id="f-defcountry"
            name="default_country"
            class="v2-input"
            bind:value={form.default_country}
          >
            <option value="">{m.settings_org_edit_not_set()}</option>
            {#each countryOptions as c (c.value)}
              <option value={c.value}>{c.label}</option>
            {/each}
          </select>
          <p class="v2-hint">{m.settings_org_edit_country_default_hint()}</p>
        </div>
      </div>

      <div class="v2-field">
        <label for="f-timezone">{m.settings_org_timezone()}</label>
        <select id="f-timezone" name="timezone" class="v2-input" bind:value={form.timezone}>
          {#each timezones as zone (zone.name)}
            <option value={zone.name}>{zone.label}</option>
          {/each}
        </select>
        <p class="v2-hint">
          {m.settings_org_edit_timezone_hint()}
        </p>
      </div>

      <div class="v2-field">
        <label for="f-default-language">{m.org_language_label()}</label>
        <select
          id="f-default-language"
          name="default_language"
          class="v2-input"
          bind:value={form.default_language}
        >
          {#each languageOptions as code (code)}
            <option value={code} lang={code}>
              {isLocale(code) ? m.language_name({}, { locale: code }) : code}
            </option>
          {/each}
        </select>
        <p class="v2-hint">{m.org_language_hint()}</p>
      </div>
      {#if leadsOn}
        <div class="v2-label" style="margin:24px 0 12px">{m.settings_org_leads_section()}</div>
        <div class="v2-field">
          <label for="f-reminder">{m.settings_org_reminder_label()}</label>
          <select
            id="f-reminder"
            name="lead_reminder_minutes"
            class="v2-input"
            bind:value={form.lead_reminder_minutes}
          >
            <option value="">{m.settings_org_reminder_off()}</option>
            {#each reminderOptions as mins (mins)}
              <option value={String(mins)}>{reminderLabel(mins)}</option>
            {/each}
          </select>
          <p class="v2-hint">
            {m.settings_org_reminder_hint()}
            <a href={DOCS_LEAD_ALERTS} target="_blank" rel="noopener noreferrer"
              >{m.settings_org_read_more()}</a
            >
          </p>
        </div>
      {/if}

      {#if invoicesOn}
        <div class="v2-label" style="margin:24px 0 12px">{m.settings_org_invoice_numbers()}</div>
        <p class="v2-hint" style="margin-top:-4px;margin-bottom:14px">
          {m.settings_org_edit_numbers_hint()}
        </p>

        <div class="pair">
          <div class="v2-field">
            <label for="f-inv-prefix">{m.settings_org_edit_invoice_prefix()}</label>
            <input
              id="f-inv-prefix"
              name="invoice_number_prefix"
              class="v2-input"
              maxlength="20"
              autocapitalize="characters"
              autocomplete="off"
              spellcheck="false"
              bind:value={form.invoice_number_prefix}
              onblur={() => (touched.invoice_number_prefix = true)}
              aria-invalid={show('invoice_number_prefix') ? 'true' : undefined}
            />
            {#if show('invoice_number_prefix')}
              <p class="v2-error">{errors.invoice_number_prefix}</p>
            {/if}
          </div>
          <div class="v2-field">
            <label for="f-est-prefix">{m.settings_org_edit_estimate_prefix()}</label>
            <input
              id="f-est-prefix"
              name="estimate_number_prefix"
              class="v2-input"
              maxlength="20"
              autocapitalize="characters"
              autocomplete="off"
              spellcheck="false"
              bind:value={form.estimate_number_prefix}
              onblur={() => (touched.estimate_number_prefix = true)}
              aria-invalid={show('estimate_number_prefix') ? 'true' : undefined}
            />
            {#if show('estimate_number_prefix')}
              <p class="v2-error">{errors.estimate_number_prefix}</p>
            {/if}
          </div>
        </div>

        <div class="pair">
          <div class="v2-field">
            <label for="f-date-part">{m.settings_org_edit_date_part()}</label>
            <select
              id="f-date-part"
              name="number_date_part"
              class="v2-input"
              bind:value={form.number_date_part}
            >
              {#each NUMBER_DATE_PARTS as part (part.value)}
                <option value={part.value}>{part.label}</option>
              {/each}
            </select>
          </div>
          <div class="v2-field">
            <label for="f-padding">{m.settings_org_edit_padding()}</label>
            <input
              id="f-padding"
              name="number_padding"
              class="v2-input"
              type="number"
              inputmode="numeric"
              min="1"
              max="10"
              bind:value={form.number_padding}
              onblur={() => (touched.number_padding = true)}
              aria-invalid={show('number_padding') ? 'true' : undefined}
            />
            {#if show('number_padding')}<p class="v2-error">{errors.number_padding}</p>{/if}
          </div>
        </div>

        {#if form.number_date_part === 'NONE'}
          <div class="v2-field">
            <label for="f-start">{m.settings_org_edit_start()}</label>
            <input
              id="f-start"
              name="invoice_number_start"
              class="v2-input"
              type="number"
              inputmode="numeric"
              min="1"
              max="999999999"
              bind:value={form.invoice_number_start}
              onblur={() => (touched.invoice_number_start = true)}
              aria-invalid={show('invoice_number_start') ? 'true' : undefined}
            />
            {#if show('invoice_number_start')}
              <p class="v2-error">{errors.invoice_number_start}</p>
            {:else}
              <p class="v2-hint">
                {m.settings_org_edit_start_hint()}
              </p>
            {/if}
          </div>
        {:else}
          <input type="hidden" name="invoice_number_start" value="1" />
        {/if}

        <p class="v2-hint" style="margin-top:-4px">
          {#each messageParts(m.settings_org_edit_example( { invoice: slot('invoice'), estimate: slot('estimate') } )) as p, i (i)}{#if p.key === 'invoice'}<b
                class="v2-num example">{exampleNumber(form, 'invoice', today)}</b
              >{:else if p.key === 'estimate'}<b class="v2-num example"
                >{exampleNumber(form, 'estimate', today)}</b
              >{:else}{p.text}{/if}{/each}
        </p>
      {/if}

      {#if ticketsOn}
        <div class="v2-label" style="margin:24px 0 12px">{m.settings_org_behaviour()}</div>

        <div class="v2-field">
          <label for="f-csat">{m.settings_org_csat()}</label>
          <select id="f-csat" name="csat_enabled" class="v2-input" bind:value={form.csat_enabled}>
            <option value="true">{m.settings_org_edit_csat_on()}</option>
            <option value="false">{m.settings_org_edit_csat_off()}</option>
          </select>
          <p class="v2-hint">
            {m.settings_org_edit_csat_hint()}
          </p>
        </div>

        <div class="v2-field">
          <label for="f-cascade">{m.settings_org_cascade()}</label>
          <select
            id="f-cascade"
            name="auto_close_children_on_parent_close"
            class="v2-input"
            bind:value={form.auto_close_children_on_parent_close}
          >
            <option value="true">{m.settings_org_edit_cascade_on()}</option>
            <option value="false">{m.settings_org_edit_cascade_off()}</option>
          </select>
          <p class="v2-hint">
            {m.settings_org_edit_cascade_hint()}
          </p>
        </div>
      {/if}

      <div class="actions">
        <button class="v2-btn v2-btn-primary" type="submit">{m.settings_org_edit_save()}</button>
        <a class="v2-btn" href={resolve('settings/organization')}>{m.common_cancel()}</a>
      </div>
    </form>
  </div>
{/if}

<style>
  .pair {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
  }
  .triple {
    display: grid;
    grid-template-columns: 2fr 1fr 1fr;
    gap: 14px;
  }
  /* A number broken at its hyphen reads as two. */
  .example {
    white-space: nowrap;
  }
  .actions {
    display: flex;
    align-items: center;
    gap: 9px;
    margin-top: 22px;
    padding-bottom: 40px;
  }
  @media (max-width: 720px) {
    .pair,
    .triple {
      grid-template-columns: 1fr;
    }
  }
</style>
