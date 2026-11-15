<script>
  import { resolve } from '$app/paths';
  /**
   * The organisation itself (read view).
   *
   * Most of this is the company profile, and the thing worth saying about it
   * is where it ends up: these fields are printed on every invoice and
   * estimate a customer receives. v1 presents them as a generic settings form,
   * so a wrong VAT number looks like a wrong preference rather than a wrong
   * document. The page groups them under that heading instead.
   *
   * Two behaviour switches sit at the bottom. They are not preferences either
   *: one stops customer surveys org-wide, the other changes what a close
   * button offers to do, so each says what turning it off actually causes.
   * They are real `Org` columns and, until this page was wired, had no way to
   * be edited at all.
   *
   * The org API key is NOT here, in any form. It is a credential that
   * authenticates as the org's first admin, so the API never serialises it onto
   * this payload. Rotating it belongs behind an explicit, audited action
   * (`OrgApiKeyView`), not on a page reachable by browsing.
   *
   * Editing is admin-only. `can_edit` (from the JWT role claim) decides whether
   * the "Edit details" link shows; the edit route and the backend PATCH are what
   * enforce it. A member sees this page read-only.
   *
   * VERTICAL PACK SECTION
   * `can_edit`: the same admin-derived flag the rest of this page already
   * uses to gate the "Edit details" link: also gates the pack list and its
   * actions here, because `PackApplyView`/`PackSampleDataView` are ADMIN-only
   * for the identical reason: this is org-wide configuration, not a personal
   * setting. A member sees only which pack (if any) is currently applied,
   * with no buttons, matching the 403 the backend would return if the UI
   * offered one anyway.
   *
   * Applying is additive-only and idempotent, so the currently-applied pack
   * stays clickable. Re-applying it is expected to report everything
   * skipped, not to be disallowed.
   *
   * The report after an apply shows created AND skipped, by name, because a
   * pack applied to an org that already has some of this configured is the
   * normal case, not a partial failure. A plain success toast would say
   * less than what actually happened. "Clear sample data" needs an in-page
   * confirm step (never the native `confirm()`, which blocks the browser
   * automation this app is smoke-tested with) before it deletes anything.
   */
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import { count, shortDate } from '#lib/v2/format.js';
  import { exampleNumber, NUMBER_DATE_PARTS } from '#lib/v2/document-numbers.js';
  import { todayIn } from '#lib/v2/dates.js';
  import { FileText, ShieldAlert, Pencil, Trash2 } from '@lucide/svelte';
  import { enhance } from '$app/forms';
  import { isOn, productsOn, wordsOn } from '#lib/v2/modules.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { locales } from '#lib/paraglide/runtime.js';

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();

  let org = $derived(data.org);
  let invoicesOn = $derived(isOn(data.modules, 'invoices'));
  let ticketsOn = $derived(isOn(data.modules, 'tickets'));
  // A pack skips what belongs to a switched-off module, so the sentence does too.
  let packSamples = $derived(
    wordsOn(
      data.modules,
      [
        [null, m.settings_org_pack_sample_accounts()],
        [null, m.settings_org_pack_sample_contacts()],
        ['deals', m.settings_org_pack_sample_deals()],
        ['tickets', m.settings_org_pack_sample_tickets()],
        ['tasks', m.settings_org_pack_sample_tasks()],
        ['leads', m.settings_org_pack_sample_leads()]
      ],
      m.settings_hub_word_and()
    )
  );
  let packAdds = $derived(
    wordsOn(
      data.modules,
      [
        [null, m.settings_org_pack_word_pipelines()],
        [null, m.settings_org_pack_word_tags()],
        [null, m.settings_org_pack_word_fields()],
        ...(productsOn(data.modules)
          ? /** @type {[null, string][]} */ ([[null, m.settings_org_pack_word_products()]])
          : []),
        [null, m.settings_org_pack_word_samples({ list: packSamples })]
      ],
      m.settings_hub_word_and()
    )
  );
  let packs = $derived(data.packs ?? []);
  /** The registry entry matching `org.vertical`, or null if unapplied / unknown. */
  let appliedPack = $derived(packs.find((/** @type {any} */ p) => p.id === org.vertical) ?? null);

  let today = $derived(todayIn(org.timezone || 'UTC'));
  /** "Year, count restarts each year" for the stored date part. */
  let numbering = $derived(
    NUMBER_DATE_PARTS.find((part) => part.value === org.number_date_part)?.label ?? ''
  );

  let address = $derived(
    [org.address_line, org.city, org.state, org.postcode, org.country].filter(Boolean).join(', ')
  );

  /** Disables every Apply / Clear button while any one of them is in flight. */
  let busy = $state(false);
  let confirmingClear = $state(false);

  /** Shared submit handler for the per-pack Apply forms. */
  const applySubmit = () => {
    busy = true;
    return async (/** @type {any} */ { update }) => {
      await update();
      busy = false;
    };
  };

  /** Clearing also drops back out of the confirm step on a successful run. */
  const clearSubmit = () => {
    busy = true;
    return async (/** @type {any} */ { update, result }) => {
      await update();
      busy = false;
      if (result?.type === 'success') confirmingClear = false;
    };
  };

  /**
   * "Created 18 items, skipped 3 you already had". The exact wording this
   * section exists to show instead of a success toast.
   * @param {{ created?: any[], skipped?: any[] }} report
   */
  function reportSummary(report) {
    const created = report?.created?.length ?? 0;
    const skipped = report?.skipped?.length ?? 0;
    if (!created && !skipped) return m.settings_org_report_nothing();
    if (!skipped) return m.settings_org_report_created({ count: created });
    if (!created) return m.settings_org_report_skipped({ count: skipped });
    return m.settings_org_report_both({ created, skipped });
  }
</script>

<PageHeader title={m.settings_hub_org_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#each messageParts(m.settings_org_sub( { count: org.member_count, shown: slot('shown'), date: shortDate(org.created_at) } )) as p, i (i)}{#if p.key === 'shown'}<span
          class="v2-num">{count(org.member_count)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    {#if data.can_edit}
      <a class="v2-btn v2-btn-primary" href={resolve('settings/organization/edit')}>
        <Pencil size={13} />{m.settings_org_edit_details()}
      </a>
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    <div class="v2-split">
      <div>
        <div class="v2-label" style="margin-bottom:10px">{m.settings_org_customers_see()}</div>
        <div class="v2-card" style="padding:16px 18px;margin-bottom:12px">
          <dl class="v2-kv">
            <dt>{m.settings_org_legal_name()}</dt>
            <dd>{org.company_name || '—'}</dd>
            <dt>{m.settings_org_trading_as()}</dt>
            <dd>{org.name}</dd>
            <dt>{m.settings_org_address()}</dt>
            <dd>{address || '—'}</dd>
            <dt>{m.settings_org_tax_id()}</dt>
            <dd class="v2-num" style="font-size:12px">{org.tax_id || '—'}</dd>
            <dt>{m.common_email()}</dt>
            <dd>{org.email || '—'}</dd>
            <dt>{m.common_phone()}</dt>
            <dd class="v2-num" style="font-size:12px">{org.phone || '—'}</dd>
            <dt>{m.settings_org_website()}</dt>
            <dd>{org.website || '—'}</dd>
            <dt>{m.settings_org_logo()}</dt>
            <dd>{org.logo_url ? m.settings_org_logo_set() : m.settings_org_logo_not_set()}</dd>
          </dl>
        </div>

        {#if invoicesOn}
          <div class="v2-card" style="padding:14px 16px">
            <div style="display:flex;gap:10px;align-items:flex-start">
              <FileText size={16} style="color:var(--v2-slate);flex:none;margin-top:2px" />
              <p class="v2-sub" style="font-size:12.5px;margin:0;line-height:1.5">
                {m.settings_org_printed_note()}
                <a href={resolve('invoices/templates')} style="color:inherit"
                  >{m.settings_org_printed_note_link()}</a
                >.
              </p>
            </div>
          </div>
        {/if}
      </div>

      <div>
        <div class="v2-label" style="margin-bottom:10px">{m.settings_org_defaults()}</div>
        <div class="v2-card" style="overflow:hidden;margin-bottom:20px">
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.settings_org_currency()}</b>
              <span class="v2-sub" style="font-size:11.5px">
                {invoicesOn
                  ? m.settings_org_currency_hint_invoices()
                  : m.settings_org_currency_hint()}
              </span>
            </div>
            <span class="v2-num" style="font-size:13px">{org.default_currency || '—'}</span>
          </div>
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.settings_org_country()}</b>
              <span class="v2-sub" style="font-size:11.5px">{m.settings_org_country_hint()}</span>
            </div>
            <span style="font-size:13px">{org.default_country || '—'}</span>
          </div>
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.settings_org_timezone()}</b>
              <span class="v2-sub" style="font-size:11.5px">{m.settings_org_timezone_hint()}</span>
            </div>
            <span style="font-size:13px">{(org.timezone || 'UTC').replace(/_/g, ' ')}</span>
          </div>
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.org_language_label()}</b>
              <span class="v2-sub" style="font-size:11.5px">{m.org_language_hint()}</span>
            </div>
            <span style="font-size:13px">
              {locales.includes(org.default_language)
                ? m.language_name({}, { locale: org.default_language })
                : org.default_language || '—'}
            </span>
          </div>
        </div>

        {#if invoicesOn}
          <div class="v2-label" style="margin-bottom:10px">{m.settings_org_invoice_numbers()}</div>
          <div class="v2-card" style="overflow:hidden;margin-bottom:20px">
            <div class="v2-setting">
              <div class="v2-setting-body">
                <b>{m.settings_org_new_invoices()}</b>
                <span class="v2-sub" style="font-size:11.5px">
                  {m.settings_org_numbering_hint({ numbering })}
                </span>
              </div>
              <span class="v2-num" style="font-size:13px"
                >{exampleNumber(org, 'invoice', today)}</span
              >
            </div>
            <div class="v2-setting">
              <div class="v2-setting-body">
                <b>{m.settings_org_new_estimates()}</b>
                <span class="v2-sub" style="font-size:11.5px"
                  >{m.settings_org_estimates_hint()}</span
                >
              </div>
              <span class="v2-num" style="font-size:13px"
                >{exampleNumber(org, 'estimate', today)}</span
              >
            </div>
          </div>
        {/if}

        {#if ticketsOn}
          <div class="v2-label" style="margin-bottom:10px">{m.settings_org_behaviour()}</div>
          <div class="v2-card" style="overflow:hidden">
            <div class="v2-setting">
              <div class="v2-setting-body">
                <b>{m.settings_org_csat()}</b>
                <!-- Org-level kill switch: the post-close signal short-circuits
                     before any email is sent. Off is silent, everywhere. -->
                <span class="v2-sub" style="font-size:11.5px">
                  {m.settings_org_csat_hint()}
                </span>
              </div>
              <Pill tone={org.csat_enabled ? 'moss' : 'slate'}>
                {org.csat_enabled ? m.settings_org_csat_sending() : m.settings_org_csat_off()}
              </Pill>
            </div>
            <div class="v2-setting">
              <div class="v2-setting-body">
                <b>{m.settings_org_cascade()}</b>
                <!-- Only the DEFAULT state of the prompt; the person closing the
                     ticket still confirms. This used to claim the prompt without
                     saying where it is, and there is no such prompt on the web:
                     `close-with-children` has no caller in `frontend/src`, so
                     closing a parent here leaves its children open. The phone is
                     the client that asks, and the one this setting reaches. -->
                <span class="v2-sub" style="font-size:11.5px">
                  {m.settings_org_cascade_hint()}
                </span>
              </div>
              <Pill tone={org.auto_close_children_on_parent_close ? 'clay' : 'slate'}>
                {org.auto_close_children_on_parent_close
                  ? m.settings_org_cascade_on()
                  : m.settings_org_cascade_off()}
              </Pill>
            </div>
          </div>
        {/if}

        <div class="v2-card" style="padding:14px 16px;margin-top:20px">
          <div style="display:flex;gap:10px;align-items:flex-start">
            <ShieldAlert size={16} style="color:var(--v2-slate);flex:none;margin-top:2px" />
            <div>
              <div style="font-weight:600;font-size:13px">{m.settings_org_api_key_title()}</div>
              <p class="v2-sub" style="font-size:12.5px;margin:5px 0 0;line-height:1.5">
                {m.settings_org_api_key_body()}
                <a href={resolve('settings/api-tokens')} style="color:inherit"
                  >{m.settings_org_api_key_link()}</a
                >{m.settings_org_api_key_after()}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div style="margin-top:24px">
      <div class="v2-label" style="margin-bottom:10px">{m.settings_org_pack_title()}</div>
      <div class="v2-card" style="padding:16px 18px">
        <p class="v2-sub" style="font-size:12.5px;margin:0 0 14px;line-height:1.5">
          {m.settings_org_pack_intro({ adds: packAdds })}
        </p>

        <div style="display:flex;align-items:center;gap:10px;margin-bottom:16px">
          <span class="v2-sub" style="font-size:11.5px">{m.settings_org_pack_first_applied()}</span>
          {#if appliedPack}
            <Pill tone="moss">{appliedPack.name}</Pill>
          {:else if org.vertical}
            <Pill tone="slate">{org.vertical}</Pill>
          {:else}
            <span class="v2-sub" style="font-size:12.5px">{m.settings_org_pack_none_yet()}</span>
          {/if}
        </div>

        {#if !data.can_edit}
          <p class="v2-sub" style="font-size:12px;margin:0">
            {m.settings_org_pack_admins_only()}
          </p>
        {:else}
          {#if form?.error}
            <div style="margin-bottom:14px">
              <NextAction
                label={m.settings_org_pack_failed_label()}
                text={form.error}
                tone="rust"
              />
            </div>
          {/if}

          {#if form?.report}
            {@const created = form.report.created ?? []}
            {@const skipped = form.report.skipped ?? []}
            {@const appliedName =
              packs.find((/** @type {any} */ p) => p.id === form.appliedPackId)?.name ??
              form.appliedPackId}
            <div
              class="v2-card"
              style="padding:14px 16px;margin-bottom:16px;border-color:color-mix(in srgb, var(--v2-moss) 40%, var(--v2-line))"
            >
              <div style="font-weight:650;font-size:13px">
                {m.settings_org_pack_applied_title({ name: appliedName })}
              </div>
              <p class="v2-sub" style="font-size:12.5px;margin:4px 0 10px">
                {reportSummary(form.report)}
              </p>
              {#if skipped.length}
                <div class="v2-label" style="margin-bottom:4px">
                  {m.settings_org_pack_skipped_label()}
                </div>
                <ul style="margin:0 0 10px;padding-left:18px;font-size:12.5px;line-height:1.7">
                  {#each skipped as item (item.type + ':' + item.name)}
                    <li>
                      {item.name}
                      <span class="v2-sub" style="font-size:11px">
                        ({item.type.replaceAll('_', ' ')}, {item.reason})
                      </span>
                    </li>
                  {/each}
                </ul>
              {/if}
              {#if created.length}
                <div class="v2-label" style="margin-bottom:4px">
                  {m.settings_org_pack_created_label()}
                </div>
                <ul style="margin:0;padding-left:18px;font-size:12.5px;line-height:1.7">
                  {#each created as item (item.type + ':' + item.name)}
                    <li>
                      {item.name}
                      <span class="v2-sub" style="font-size:11px">
                        ({item.type.replaceAll('_', ' ')})
                      </span>
                    </li>
                  {/each}
                </ul>
              {/if}
            </div>
          {/if}

          <div class="v2-card" style="overflow:hidden;margin-bottom:20px">
            {#each packs as pack (pack.id)}
              <div class="v2-setting">
                <div class="v2-setting-body">
                  <b>{pack.name}</b>
                  <span class="v2-sub" style="font-size:11.5px">
                    {pack.description}
                    {#if pack.version}· v{pack.version}{/if}
                  </span>
                </div>
                {#if pack.id === org.vertical}
                  <Pill tone="moss">{m.settings_org_pack_applied()}</Pill>
                {/if}
                <form method="POST" action="?/apply" use:enhance={applySubmit}>
                  <input type="hidden" name="pack_id" value={pack.id} />
                  <button class="v2-btn v2-btn-sm" disabled={busy}>{m.common_apply()}</button>
                </form>
              </div>
            {/each}
            {#if !packs.length}
              <div class="v2-setting">
                <span class="v2-sub" style="font-size:12.5px"
                  >{m.settings_org_pack_none_available()}</span
                >
              </div>
            {/if}
          </div>

          <div class="danger">
            {#if confirmingClear}
              <form
                method="POST"
                action="?/clearSampleData"
                use:enhance={clearSubmit}
                style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"
              >
                <span class="v2-sub" style="font-size:12px">
                  {m.settings_org_clear_confirm()}
                </span>
                <button class="v2-btn danger-btn" type="submit" disabled={busy}>
                  <Trash2 size={14} />
                  {m.settings_org_clear_button()}
                </button>
                <button
                  class="v2-btn"
                  type="button"
                  disabled={busy}
                  onclick={() => (confirmingClear = false)}
                >
                  {m.common_cancel()}
                </button>
              </form>
            {:else if form?.cleared !== undefined}
              <span class="v2-sub" style="font-size:12.5px">
                {form.cleared
                  ? m.settings_org_cleared({ count: form.cleared })
                  : m.settings_org_cleared_none()}
                {#if form.retained}
                  {m.settings_org_cleared_kept({ count: form.retained })}
                {/if}
              </span>
            {:else}
              <button
                class="v2-btn danger-btn"
                type="button"
                onclick={() => (confirmingClear = true)}
              >
                <Trash2 size={14} />
                {m.settings_org_clear_button()}
              </button>
              <span class="v2-sub" style="font-size:11.5px">{m.settings_org_clear_hint()}</span>
            {/if}
          </div>
        {/if}
      </div>
    </div>
  </div>
</div>

<style>
  /* Mirrors the destructive-action pattern used on the product-edit page
     (frontend/src/routes/(app)/invoices/products/[id]/edit/+page.svelte):
     same class names, same look, so "delete something" reads the same way
     everywhere in the app. */
  .danger {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
    border-top: 1px solid var(--v2-line-soft);
    padding-top: 16px;
  }
  .danger-btn {
    color: var(--v2-rust);
    border-color: color-mix(in srgb, var(--v2-rust) 32%, transparent);
  }
  .danger-btn:hover {
    background: color-mix(in srgb, var(--v2-rust) 9%, transparent);
  }
</style>
