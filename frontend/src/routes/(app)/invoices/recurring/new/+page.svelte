<script>
  import { resolve } from '$app/paths';
  /**
   * New recurring schedule.
   *
   * Same shape as the one-off invoice builder (`invoices/new`): three FK
   * pickers, an optional line-item list, and the whole form serialised into one
   * hidden `payload` field so the dynamic list survives the POST intact. Reused
   * directly: the account/contact filtering rule, the line-item card
   * (`LineItemsEditor`) and the totals ladder and payload (`#lib/v2/line-items.js`),
   * so a schedule's lines are counted and sent exactly as an invoice's are.
   *
   * WHAT IS DIFFERENT FROM THE INVOICE BUILDER
   * A schedule has no line-item requirement: `RecurringInvoiceCreateSerializer`
   * lists `line_items` as optional, because a schedule can exist before anyone
   * has priced it out. The one exception is auto-send: the API refuses a
   * schedule that would mail the client a blank invoice, and `ready` below
   * asks for a line only then.
   *
   * `org`, `created_by`, `subtotal`, `total_amount` and `invoices_generated` are
   * absent for the same reason they are absent from the invoice builder: they
   * are server-derived, and a form that collects them is a form that can be
   * edited to claim them.
   *
   * NO ROLE GATE
   * `POST /invoices/recurring/` has `permission_classes = (IsAuthenticated,
   * HasOrgContext)`, no admin check, unlike invoice templates. Nothing on this
   * page is conditioned on `role`.
   *
   * THE ONE GUARD THE SERVER DOES NOT HAVE
   * `RecurringInvoiceCreateSerializer` never cross-validates `frequency` against
   * `custom_days`; a CUSTOM schedule with no interval is accepted and then
   * silently generates monthly. `ready` below requires `customDays` whenever
   * CUSTOM is chosen so the form does not walk into that gap, but this is a UX
   * guard over a real backend gap, not a mirror of a server rule.
   */
  import { enhance } from '$app/forms';
  import { untrack } from 'svelte';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SectionTabs from '#lib/v2/components/SectionTabs.svelte';
  import PortalLineItems from '#lib/v2/components/PortalLineItems.svelte';
  import LineItemsEditor from '#lib/v2/components/LineItemsEditor.svelte';
  import { RECURRING_FREQUENCY_LABEL, PAYMENT_TERMS_LABEL } from '#lib/v2/enums.js';
  import {
    blankLine,
    documentDiscountError,
    documentTotals,
    lineTotals,
    linePayload,
    num,
    taxRateError
  } from '#lib/v2/line-items.js';
  import { todayIn } from '#lib/v2/dates.js';
  import { CURRENCY_CODES } from '#lib/constants/filters.js';
  import { m } from '#lib/paraglide/messages.js';

  /** @type {{ data: { products: any[], accounts: any[], contacts: any[], org: { timezone: string } }, form: any }} */
  let { data, form } = $props();

  // The org's day: a UTC date is yesterday for a morning east of UTC.
  const today = untrack(() => todayIn(data.org.timezone));

  // Every code the backend accepts (`CURRENCY_CODES` in `common/utils.py`),
  // not a subset. Offering fewer would leave an org that bills in one of the
  // missing ones unable to create a schedule at all, for no reason.
  const CURRENCIES = CURRENCY_CODES.filter((c) => c.value).map((c) => c.value);

  let accountId = $state('');
  let contactId = $state('');
  let title = $state('');
  let frequency = $state('MONTHLY');
  let customDays = $state('');
  let paymentTerms = $state('NET_30');
  let currency = $state('USD');
  let startDate = $state(today);
  let endDate = $state('');
  let nextGenerationDate = $state(today);
  // The first run follows the start date until someone picks it themselves;
  // the server refuses a first run before the start.
  let nextPicked = $state(false);
  let autoSend = $state(false);
  let discountType = $state('');
  let discountValue = $state(0);
  let taxRate = $state(0);
  let notes = $state('');
  let terms = $state('');

  let items = $state([blankLine()]);

  /**
   * Contacts whose primary account is this account, plus contacts with no
   * account (they attach to anyone).
   *
   * `c.account_id` (set in `+page.server.js` from `contacts.js`'s
   * `accountLink`) is the primary FK when the contact has one, and the first
   * M2M membership otherwise. The server's cross-check,
   * `RecurringInvoiceCreateSerializer.validate` (`invoices/serializer.py:
   * 1182-1193`), looks only at the real primary FK, `contact.account_id`, and
   * only rejects when that FK is set and differs from the chosen account: a
   * contact with no primary FK passes there for any account. So this filter
   * is deliberately stricter than the server, not a mirror of it: it can hide
   * a pairing the API would accept for a contact whose primary FK is unset
   * and whose first M2M membership is some other account. That is the safer
   * direction to be wrong in for a picker: under-offer rather than walk
   * someone into a 400.
   */
  let contactOptions = $derived(
    data.contacts.filter((c) => !c.account_id || c.account_id === accountId)
  );

  /* The invoice builder's lines and ladder, the same one the serializer's
     _recalculate_totals runs. There is no shipping on a recurring schedule,
     unlike the one-off invoice. */
  let usableLines = $derived(lineTotals(items).usable);
  let totals = $derived(
    documentTotals({ lines: usableLines, discountType, discountValue, taxRate })
  );

  /* The API's discount bounds, checked before it is asked (it refuses them too). */
  let discountError = $derived(documentDiscountError(discountType, discountValue, totals.subtotal));
  let taxError = $derived(taxRateError(taxRate));

  /* Lines are optional, except on a schedule that mails what it raises. */
  let needsLine = $derived(autoSend && !usableLines.length);

  let ready = $derived(
    Boolean(accountId) &&
      Boolean(contactId) &&
      Boolean(title.trim()) &&
      (frequency !== 'CUSTOM' || Boolean(customDays)) &&
      !needsLine &&
      !discountError &&
      !taxError
  );

  /* True from submit until the response lands. The button lives outside the
     form and stays live otherwise, so a second press during a slow save
     posts the schedule twice and creates two of them. */
  let saving = $state(false);

  /**
   * The whole builder as the API body, carried in one hidden field so the
   * dynamic line-item list survives the form post intact. Only what the server
   * accepts is sent; org/created_by/subtotal/total_amount/invoices_generated
   * are its to derive, so none are here.
   */
  let payload = $derived.by(() => {
    /** @type {Record<string, any>} */
    const body = {
      account_id: accountId,
      contact_id: contactId,
      title: title.trim(),
      frequency,
      payment_terms: paymentTerms,
      currency,
      start_date: startDate,
      next_generation_date: nextGenerationDate,
      auto_send: autoSend
    };
    if (frequency === 'CUSTOM' && customDays) body.custom_days = num(customDays);
    if (endDate) body.end_date = endDate;
    if (discountType) {
      body.discount_type = discountType;
      body.discount_value = num(discountValue);
    }
    if (num(taxRate)) body.tax_rate = num(taxRate);
    if (notes.trim()) body.notes = notes.trim();
    if (terms.trim()) body.terms = terms.trim();
    if (usableLines.length) body.line_items = linePayload(usableLines);
    return body;
  });
</script>

<PageHeader title={m.invoices_recurring_new_title()}>
  {#snippet sub()}
    {m.invoices_recurring_new_sub()}
  {/snippet}
  {#snippet actions()}
    <a class="v2-btn" href={resolve('invoices/recurring')}>{m.common_cancel()}</a>
    <button
      type="submit"
      form="recurring-form"
      class="v2-btn v2-btn-primary"
      disabled={!ready || saving}
    >
      {saving ? m.invoices_form_saving() : m.invoices_recurring_save()}
    </button>
  {/snippet}
</PageHeader>

<SectionTabs set="invoices" />

{#if form?.error}
  <div class="v2-pad" style="padding-top:12px">
    <p class="new-error" role="alert">{form.error}</p>
  </div>
{/if}

<!-- The builder posts as one JSON field so the dynamic line list travels whole.
     The submit button lives in the header and is wired to this form by id. -->
<form
  id="recurring-form"
  method="POST"
  action="?/create"
  use:enhance={({ cancel }) => {
    if (saving) return cancel();
    saving = true;
    return async ({ update }) => {
      await update();
      saving = false;
    };
  }}
>
  <input type="hidden" name="payload" value={JSON.stringify(payload)} />
</form>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    <div class="v2-split">
      <!-- the form -->
      <div>
        <div class="v2-card" style="padding:16px 18px">
          <div class="v2-label" style="margin-bottom:12px">{m.invoices_recurring_who_what()}</div>

          <div class="grid2">
            <label class="f">
              <span>{m.invoices_col_account()}</span>
              <select bind:value={accountId} onchange={() => (contactId = '')}>
                <option value="">{m.invoices_form_choose_account()}</option>
                {#each data.accounts as a (a.id)}
                  <option value={a.id}>{a.name}</option>
                {/each}
              </select>
            </label>

            <label class="f">
              <span>{m.invoices_form_contact()}</span>
              <select bind:value={contactId} disabled={!accountId}>
                <option value=""
                  >{accountId
                    ? m.invoices_form_choose_contact()
                    : m.invoices_form_pick_account_first()}</option
                >
                {#each contactOptions as c (c.id)}
                  <option value={c.id}
                    >{c.name}{c.account_name ? ` · ${c.account_name}` : ''}</option
                  >
                {/each}
              </select>
            </label>

            <label class="f" style="grid-column:1/-1">
              <span>{m.invoices_form_title()}</span>
              <input
                bind:value={title}
                placeholder={m.invoices_recurring_title_placeholder()}
                required
              />
            </label>
          </div>
        </div>

        <div class="v2-card" style="padding:16px 18px;margin-top:14px">
          <div class="v2-label" style="margin-bottom:12px">{m.invoices_recurring_cadence()}</div>

          <div class="grid2">
            <label class="f">
              <span>{m.invoices_recurring_frequency()}</span>
              <select bind:value={frequency}>
                {#each Object.entries(RECURRING_FREQUENCY_LABEL) as [value, label] (value)}
                  <option {value}>{label}</option>
                {/each}
              </select>
            </label>

            {#if frequency === 'CUSTOM'}
              <label class="f">
                <span>{m.invoices_recurring_every_n_days()}</span>
                <input type="number" min="1" step="1" bind:value={customDays} required />
              </label>
            {/if}

            <label class="f">
              <span>{m.invoices_recurring_start_date()}</span>
              <input
                type="date"
                bind:value={startDate}
                onchange={() => {
                  if (!nextPicked) nextGenerationDate = startDate;
                }}
              />
            </label>

            <label class="f">
              <span>{m.invoices_recurring_next_date()}</span>
              <input
                type="date"
                min={startDate}
                bind:value={nextGenerationDate}
                oninput={() => (nextPicked = true)}
              />
            </label>

            <label class="f">
              <span
                >{m.invoices_recurring_end_date()}
                <span class="opt">{m.invoices_form_optional()}</span></span
              >
              <input type="date" bind:value={endDate} />
            </label>

            <label class="f">
              <span>{m.invoices_form_payment_terms()}</span>
              <select bind:value={paymentTerms}>
                {#each Object.entries(PAYMENT_TERMS_LABEL) as [value, label] (value)}
                  <option {value}>{label}</option>
                {/each}
              </select>
            </label>

            <label class="f">
              <span>{m.invoices_currency()}</span>
              <select bind:value={currency}>
                {#each CURRENCIES as c (c)}
                  <option value={c}>{c}</option>
                {/each}
              </select>
            </label>
          </div>

          <label class="check">
            <input type="checkbox" bind:checked={autoSend} />
            <span>
              {m.invoices_recurring_auto_send()}
              <span class="hint-inline">{m.invoices_recurring_auto_send_hint()}</span>
            </span>
          </label>
          {#if needsLine}
            <p class="field-err" role="alert">{m.invoices_recurring_auto_send_needs_line()}</p>
          {/if}
        </div>

        <!-- Lines are optional unless auto-send is on: an empty or half-typed line is not sent. -->
        <LineItemsEditor bind:items products={data.products} {currency} />

        <div class="v2-card" style="padding:16px 18px;margin-top:14px">
          <div class="v2-label" style="margin-bottom:12px">{m.invoices_form_adjustments()}</div>
          <div class="grid2">
            <label class="f">
              <span>{m.invoices_discount()}</span>
              <select bind:value={discountType}>
                <option value="">{m.invoices_form_discount_none()}</option>
                <option value="PERCENTAGE">{m.invoices_form_discount_percentage()}</option>
                <option value="FIXED">{m.invoices_form_discount_fixed()}</option>
              </select>
            </label>
            {#if discountType}
              <label class="f">
                <span
                  >{discountType === 'PERCENTAGE'
                    ? m.invoices_form_percent_off()
                    : m.invoices_form_amount_off()}</span
                >
                <input
                  type="number"
                  min="0"
                  max={discountType === 'PERCENTAGE' ? 100 : undefined}
                  step="0.01"
                  bind:value={discountValue}
                  aria-invalid={Boolean(discountError)}
                />
                {#if discountError}
                  <small class="field-err" role="alert">{discountError}</small>
                {/if}
              </label>
            {/if}
            <label class="f">
              <span>{m.invoices_form_tax_rate()}</span>
              <input
                type="number"
                min="0"
                max="100"
                step="0.01"
                bind:value={taxRate}
                aria-invalid={Boolean(taxError)}
              />
              {#if taxError}
                <small class="field-err" role="alert">{taxError}</small>
              {/if}
            </label>
          </div>
          <p class="hint">
            {m.invoices_recurring_tax_hint()}
          </p>
        </div>

        <div class="v2-card" style="padding:16px 18px;margin-top:14px">
          <div class="v2-label" style="margin-bottom:8px">{m.invoices_form_notes()}</div>
          <textarea
            rows="3"
            bind:value={notes}
            placeholder={m.invoices_recurring_notes_placeholder()}></textarea>
          <div class="v2-label" style="margin:14px 0 8px">{m.invoices_form_terms()}</div>
          <textarea
            rows="3"
            bind:value={terms}
            placeholder={m.invoices_recurring_terms_placeholder()}></textarea>
        </div>
      </div>

      <!-- what each generated invoice will total, from the lines priced in so far -->
      <div>
        <div class="v2-card preview">
          <div class="v2-card-head">
            <span class="v2-label">{m.invoices_recurring_preview_title()}</span>
          </div>
          <div style="padding:14px 16px 16px">
            {#if usableLines.length}
              <PortalLineItems
                items={usableLines}
                {currency}
                subtotal={totals.subtotal}
                discountAmount={totals.discountAmount}
                {discountType}
                {discountValue}
                {taxRate}
                taxAmount={totals.taxAmount}
                total={totals.total}
              />
            {:else}
              <p class="empty">
                {m.invoices_recurring_preview_empty()}
              </p>
            {/if}
          </div>
        </div>

        <div class="v2-card" style="padding:15px 16px;margin-top:14px">
          <div class="v2-label" style="margin-bottom:9px">{m.invoices_recurring_on_save()}</div>
          <dl class="derived">
            <dt>{m.invoices_recurring_subtotal_total()}</dt>
            <dd>{m.invoices_recurring_subtotal_total_hint()}</dd>
            <dt>{m.invoices_recurring_visibility()}</dt>
            <dd>
              {m.invoices_recurring_visibility_hint()}
            </dd>
          </dl>
        </div>
      </div>
    </div>
  </div>
</div>

<style>
  .grid2 {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px 14px;
  }
  .f {
    display: block;
    min-width: 0;
  }
  .f > span {
    display: block;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    color: var(--v2-slate);
    margin-bottom: 4px;
  }
  .opt {
    text-transform: none;
    font-weight: 500;
    letter-spacing: 0;
    color: var(--v2-slate);
  }
  input,
  select,
  textarea {
    width: 100%;
    padding: 7px 9px;
    font: inherit;
    font-size: 13px;
    color: var(--v2-ink);
    background: var(--v2-card);
    border: 1px solid var(--v2-line);
    border-radius: 6px;
  }
  textarea {
    resize: vertical;
    line-height: 1.5;
  }
  input:focus,
  select:focus,
  textarea:focus {
    outline: 2px solid var(--v2-ember);
    outline-offset: -1px;
  }
  input[type='number'] {
    font-family: var(--v2-mono);
    font-size: 12.5px;
  }

  .check {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin-top: 14px;
    font-size: 13px;
    cursor: pointer;
  }
  .check input {
    width: auto;
    margin-top: 3px;
  }
  .hint-inline {
    display: block;
    font-size: 11.5px;
    color: var(--v2-slate);
  }

  .field-err {
    display: block;
    margin-top: 4px;
    font-size: 12px;
    color: var(--v2-clay);
  }
  .hint {
    margin: 10px 0 0;
    font-size: 11.5px;
    color: var(--v2-slate);
    line-height: 1.5;
  }
  #recurring-form {
    display: contents;
  }
  .new-error {
    margin: 0;
    padding: 9px 12px;
    font-size: 12.5px;
    color: var(--v2-clay);
    background: color-mix(in srgb, var(--v2-clay) 8%, transparent);
    border: 1px solid color-mix(in srgb, var(--v2-clay) 25%, transparent);
    border-radius: 7px;
  }

  .preview {
    position: sticky;
    top: 0;
  }
  .empty {
    margin: 0;
    font-size: 12.5px;
    color: var(--v2-slate);
    line-height: 1.5;
  }
  .derived {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 5px 14px;
    margin: 0;
    font-size: 12.5px;
  }
  .derived dt {
    color: var(--v2-slate);
  }
  .derived dd {
    margin: 0;
  }

  @media (max-width: 560px) {
    .grid2 {
      grid-template-columns: 1fr;
    }
  }
</style>
