<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * The account is a workspace, not a form.
   *
   * v1 rendered an account as ~28 stacked label/value rows, so answering
   * "what is going on with Northwind?" meant visiting four other pages. Here
   * the deals, people, tickets and invoices are on the page, and the next
   * action names the problem that spans them.
   *
   * All four panels come from the single detail response, the API already
   * returned them, so this costs no extra round trips.
   */
  import CustomFieldsCard from '#lib/v2/components/CustomFieldsCard.svelte';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import Avatar from '#lib/v2/components/Avatar.svelte';
  import DuplicatesPanel from '#lib/v2/components/DuplicatesPanel.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import { money, moneyEach, shortDate, longDate } from '#lib/v2/format.js';
  import { isOrgAdmin } from '#lib/admin.js';
  import {
    CASE_PRIORITY_LABEL,
    CASE_STATUS_LABEL,
    CLOSED_KINDS,
    INVOICE_STATUS_TONE,
    PRIORITY_TONE,
    invoiceStatusLabel
  } from '#lib/v2/enums.js';
  import { ChevronRight, Mail, Phone } from '@lucide/svelte';
  import RelatedRecords from '#lib/v2/components/RelatedRecords.svelte';
  import { relatedView } from '#lib/v2/custom-objects.js';
  import { isOn } from '#lib/v2/modules.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();
  let related = $derived(relatedView(data.related));
  let dealsOn = $derived(isOn(data.modules, 'deals'));
  let ticketsOn = $derived(isOn(data.modules, 'tickets'));
  let invoicesOn = $derived(isOn(data.modules, 'invoices'));

  let { account, deals, contacts, tickets, invoices, owners } = $derived(data);

  let openDeals = $derived(deals.filter((d) => !CLOSED_KINDS.includes(d.stage_kind ?? '')));
  let stalled = $derived(dealsOn ? openDeals.filter((d) => d.aging_status === 'red') : []);
  // `past_due` is decided by the same rule as the header figure. See
  // `isPastDue` in the data layer. The invoice's own `is_overdue` flag counts
  // drafts, and a rail that disagrees with its header discredits both.
  let pastDue = $derived(invoicesOn ? invoices.filter((i) => i.past_due) : []);

  /** One sentence that connects problems across objects. Every clause is a
      fact on this page: a stalled deal, or an invoice past its due date. */
  let headline = $derived(
    stalled.length && pastDue.length
      ? m.accounts_detail_headline_both({
          deal: stalled[0].name,
          invoice: pastDue[0].invoice_number
        })
      : stalled.length
        ? m.accounts_detail_headline_stalled({
            deal: stalled[0].name,
            days: stalled[0].days_in_current_stage
          })
        : pastDue.length
          ? m.accounts_detail_headline_past_due({
              invoice: pastDue[0].invoice_number,
              amount: money(pastDue[0].amount_due, pastDue[0].currency)
            })
          : null
  );
</script>

<PageHeader title={account.name} record>
  {#snippet crumb()}
    <a href={resolve('accounts')}>{m.accounts_list_title()}</a>
    <ChevronRight size={12} />
    <span>{account.industry || m.accounts_detail_no_industry()}</span>
  {/snippet}
  {#snippet sub()}
    {[
      account.industry,
      account.number_of_employees
        ? m.accounts_detail_staff({ count: account.number_of_employees })
        : null,
      /* Derived: the close date of the first deal won here. There is no
         contract model, so this is what "customer since" can honestly mean. */
      !dealsOn
        ? null
        : account.first_won_on
          ? m.accounts_detail_customer_since({ date: longDate(account.first_won_on) })
          : m.accounts_detail_no_deals_won(),
      owners.length ? m.accounts_detail_owned_by({ owner: owners[0] }) : null
    ]
      .filter(Boolean)
      .join(' · ')}
  {/snippet}
  {#snippet actions()}
    {#if invoicesOn && isOrgAdmin(data)}
      <!-- Statements are admin-only on the API; a member would only be told so. -->
      <a class="v2-btn" href={resolve(`accounts/${account.id}/statement`)}
        >{m.accounts_detail_statement_button()}</a
      >
    {/if}
    <a class="v2-btn" href={resolve(`accounts/${account.id}/edit`)}>{m.common_edit()}</a>
    {#if data.canDelete}
      <!-- Offered only when the API's delete rule admits this caller; the
           DELETE asks the same rule again. -->
      <ConfirmAction
        action="?/delete"
        label={m.common_delete()}
        confirmLabel={m.accounts_detail_delete_confirm()}
        explain={m.accounts_detail_delete_explain({ name: account.name })}
      />
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-bottom:32px">
    <div class="v2-stats" style="margin-bottom:16px">
      {#if dealsOn}
        <StatCard
          label={m.accounts_detail_stat_revenue_won()}
          value={account.won_by_currency?.length ? moneyEach(account.won_by_currency) : '—'}
          tone={account.won_by_currency?.length ? 'moss' : 'slate'}
          detail={account.won_count
            ? m.accounts_detail_stat_deals_won({ count: account.won_count })
            : m.accounts_detail_stat_nothing_won()}
        />
        <StatCard
          label={m.accounts_detail_stat_open_pipeline()}
          value={account.pipeline_by_currency?.length
            ? moneyEach(account.pipeline_by_currency)
            : '—'}
          detail={account.open_deal_count
            ? m.accounts_detail_stat_open_deals({ count: account.open_deal_count })
            : m.accounts_detail_stat_no_open_deals()}
        />
      {/if}
      {#if invoicesOn}
        <StatCard
          label={m.accounts_detail_stat_past_due()}
          value={account.overdue_by_currency?.length ? moneyEach(account.overdue_by_currency) : '—'}
          tone={account.overdue_by_currency?.length ? 'rust' : 'slate'}
          detail={pastDue.length
            ? pastDue.map((i) => i.invoice_number).join(', ')
            : m.accounts_detail_stat_nothing_past_due()}
        />
      {/if}
      {#if ticketsOn}
        <StatCard
          label={m.accounts_detail_stat_open_tickets()}
          value={String(account.open_tickets ?? 0)}
          tone={tickets.some((t) => t.priority === 'Urgent') ? 'rust' : 'slate'}
          detail={tickets.length
            ? `${tickets[0].name} · ${tickets[0].priority}`
            : m.accounts_detail_stat_none_open()}
        />
      {/if}
    </div>

    {#if headline}
      <div style="margin-bottom:16px">
        <!--
          The invoice half of this had an `href` it should not have had: it
          pointed at `/invoices/<uuid>` while invoices is still fixtures
          keyed by slugs, so the one button on the page labelled "the thing
          that needs you" answered 404. Found by following the page's own
          outbound links rather than by reading it.

          Without an `href` the action stays a button that does nothing, which
          is the same wrong answer more quietly, so when the target is not
          wired the action is dropped entirely and the sentence stands on its
          own. It comes back when invoices is.
        -->
        <NextAction
          label={m.accounts_detail_needs_you()}
          text={headline}
          action={stalled.length ? m.accounts_detail_open_deal() : null}
          href={stalled.length ? `/pipeline/${stalled[0].id}` : null}
          tone="rust"
        />
      </div>
    {/if}

    {#if form?.deleteError}
      <p class="v2-error" role="alert" style="margin:0 0 14px">{form.deleteError}</p>
    {/if}
    <DuplicatesPanel
      module="accounts"
      id={account.id}
      canDelete={data.duplicates.can_delete}
      duplicates={data.duplicates.duplicates}
    />

    {#if data.customFields?.length}
      <div style="margin-bottom:16px">
        <CustomFieldsCard fields={data.customFields} flush />
      </div>
    {/if}

    <!-- align-items:start so each card is its own height. Stretched to match
         its neighbour, a one-row panel ends in a tall blank area that reads as
         content that failed to load. -->
    <div
      style="display:grid;grid-template-columns:1fr 1fr;gap:14px;align-items:start"
      class="v2-account-grid"
    >
      <!-- Deals -->
      {#if dealsOn}
        <section class="v2-card" style="overflow:hidden">
          <div class="v2-card-head">
            <span class="v2-label">{m.accounts_detail_deals_title()}</span>
            <a href={resolve('pipeline')}>{m.common_view_all()}</a>
          </div>
          {#each deals as d (d.id)}
            <a
              href={resolve(`pipeline/${d.id}`)}
              style="display:flex;gap:12px;align-items:center;padding:11px 15px;border-bottom:1px solid var(--v2-line-soft);color:inherit;text-decoration:none"
            >
              <div style="flex:1;min-width:0">
                <div style="font-weight:550;font-size:13px">{d.name}</div>
                <!-- `closed_on` is labelled "Expected Close Date" on the model
                   and means two different things depending on the stage. Bare,
                   it reads as though an open deal already closed. -->
                <div class="v2-sub" style="font-size:11.5px">
                  {d.stage_label}{d.closed_on
                    ? CLOSED_KINDS.includes(d.stage_kind ?? '')
                      ? ` · ${m.accounts_detail_deal_closed_on({ date: shortDate(d.closed_on) })}`
                      : ` · ${m.accounts_detail_deal_due_on({ date: shortDate(d.closed_on) })}`
                    : ''}
                </div>
              </div>
              {#if d.aging_status === 'red' && !CLOSED_KINDS.includes(d.stage_kind ?? '')}
                <Pill tone="rust"
                  >{m.accounts_detail_deal_days({ days: d.days_in_current_stage })}</Pill
                >
              {/if}
              <span class="v2-num" style="font-weight:600;font-size:13px"
                >{money(d.amount, d.currency)}</span
              >
            </a>
          {:else}
            <p class="v2-sub" style="padding:14px 15px;font-size:12.5px">
              {m.accounts_detail_deals_empty()}
            </p>
          {/each}
        </section>
      {/if}

      <!-- People -->
      <section class="v2-card" style="overflow:hidden">
        <div class="v2-card-head">
          <span class="v2-label">{m.accounts_detail_people_title()}</span>
          <a href={resolve('contacts')}>{m.common_view_all()}</a>
        </div>
        {#each contacts as c (c.id)}
          <div
            style="display:flex;gap:11px;align-items:center;padding:10px 15px;border-bottom:1px solid var(--v2-line-soft)"
          >
            <Avatar name="{c.first_name} {c.last_name}" size={29} />
            <!-- A link now. This was deliberately dead text while
                 `/contacts/<uuid>` answered 404, which is the reason
                 contacts was the module to wire next. -->
            <a
              href={resolve(`contacts/${c.id}`)}
              style="flex:1;min-width:0;color:inherit;text-decoration:none"
            >
              <div style="font-weight:550;font-size:13px">{c.first_name} {c.last_name}</div>
              <!-- title and department. The mock showed a "relationship"
                   (Champion / Blocker); Contact has no such field. -->
              <div class="v2-sub" style="font-size:11.5px">
                {[c.title, c.department].filter(Boolean).join(' · ') ||
                  m.accounts_detail_no_title()}
              </div>
            </a>
            {#if c.email}
              <a
                class="v2-btn v2-btn-sm"
                href="mailto:{c.email}"
                aria-label={m.accounts_detail_email_person({ name: c.first_name })}
              >
                <Mail size={13} />
              </a>
            {/if}
            {#if c.phone && !c.do_not_call}
              <a
                class="v2-btn v2-btn-sm"
                href="tel:{c.phone}"
                aria-label={m.accounts_detail_call_person({ name: c.first_name })}
              >
                <Phone size={13} />
              </a>
            {/if}
          </div>
        {:else}
          <p class="v2-sub" style="padding:14px 15px;font-size:12.5px">
            {m.accounts_detail_people_empty_before()}
            <a href={resolve(`contacts/new?account=${account.id}`)}
              >{m.accounts_detail_people_empty_link()}</a
            >{m.accounts_detail_people_empty_after()}
          </p>
        {/each}
      </section>

      <!-- Tickets -->
      {#if ticketsOn}
        <section class="v2-card" style="overflow:hidden">
          <div class="v2-card-head">
            <span class="v2-label">{m.accounts_detail_tickets_title()}</span>
            <a href={resolve('tickets')}>{m.common_view_all()}</a>
          </div>
          {#each tickets as t (t.id)}
            <!-- A link again: tickets is wired, so a real id sent to
               `/tickets/<uuid>` opens the ticket. -->
            <a
              href={resolve(`tickets/${t.id}`)}
              style="display:flex;gap:12px;align-items:center;padding:11px 15px;border-bottom:1px solid var(--v2-line-soft);color:inherit;text-decoration:none"
            >
              <span style="flex:1;font-size:13px;min-width:0">{t.name}</span>
              <span class="v2-sub" style="font-size:11.5px"
                >{CASE_STATUS_LABEL[t.status] ?? t.status}</span
              >
              <Pill tone={PRIORITY_TONE[t.priority]}
                >{CASE_PRIORITY_LABEL[t.priority] ?? t.priority}</Pill
              >
            </a>
          {:else}
            <p class="v2-sub" style="padding:14px 15px;font-size:12.5px">
              {m.accounts_detail_tickets_empty_before()}
              <a href={resolve(`tickets/new?account=${account.id}`)}
                >{m.accounts_detail_tickets_empty_link()}</a
              >{m.accounts_detail_tickets_empty_after()}
            </p>
          {/each}
        </section>
      {/if}

      <!-- Invoices -->
      {#if invoicesOn}
        <section class="v2-card" style="overflow:hidden">
          <div class="v2-card-head">
            <span class="v2-label">{m.accounts_detail_invoices_title()}</span>
            <a href={resolve('invoices')}>{m.common_view_all()}</a>
          </div>
          {#each invoices as inv (inv.id)}
            <!-- A link now: invoices is wired, so a real id sent to
               `/invoices/<uuid>` opens the invoice. -->
            <a
              href={resolve(`invoices/${inv.id}`)}
              style="display:flex;gap:12px;align-items:center;padding:11px 15px;border-bottom:1px solid var(--v2-line-soft);color:inherit;text-decoration:none"
            >
              <span class="v2-num" style="font-size:12.5px">{inv.invoice_number}</span>
              <Pill tone={inv.past_due ? 'rust' : INVOICE_STATUS_TONE[inv.status]}>
                {inv.past_due
                  ? m.accounts_detail_invoice_past_due()
                  : invoiceStatusLabel(inv.status)}
              </Pill>
              <span class="v2-num" style="margin-left:auto;font-weight:600;font-size:13px">
                {money(inv.past_due ? inv.amount_due : inv.total_amount, inv.currency)}
              </span>
            </a>
          {:else}
            <p class="v2-sub" style="padding:14px 15px;font-size:12.5px">
              {m.accounts_detail_invoices_empty()}
            </p>
          {/each}
        </section>
      {/if}
      <RelatedRecords {related} error={form?.related?.error} flush />
    </div>
  </div>
</div>

<style>
  @media (max-width: 1080px) {
    .v2-account-grid {
      grid-template-columns: 1fr !important;
    }
  }
</style>
