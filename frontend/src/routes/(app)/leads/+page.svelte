<script lang="ts">
  import { resolve } from '$app/paths';
  import { page } from '$app/state';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import FilterBar from '#lib/v2/components/FilterBar.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import Avatar from '#lib/v2/components/Avatar.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import LeadImportDrawer from '#lib/components/leads/LeadImportDrawer.svelte';
  import { money, count, relativeDays, daysSince } from '#lib/v2/format.js';
  import { LEAD_STATUS_LABEL, LEAD_STATUS_TONE, industryLabel } from '#lib/v2/enums.js';
  import { sourceFilterOptions, sourceLabel } from '#lib/v2/lead-sources.js';
  import { secondsSince, spanText } from '#lib/v2/interactions.js';
  import { Download, Plus, Upload, Target, Timer, Trophy } from '@lucide/svelte';
  import { t } from '#lib/terminology.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data }: PageProps = $props();

  let leads = $derived(data.leads);
  let importOpen = $state(false);
  let totals = $derived(data.totals);

  /* A vertical pack renames this module in the sidebar. Reading the same map
     here keeps the two agreeing, a nav item saying "Enquiries" that opens a
     page headed "Leads" reads as a bug, not as configuration. `t()` falls back
     to the literal, so an org with no terminology sees exactly what it saw
     before. The values are tenant text and render as plain text. */
  let terms = $derived(data.org?.terminology);
  let plural = $derived(t(terms, 'lead.plural', m.leads_term_plural()));
  let singular = $derived(t(terms, 'lead.singular', m.leads_term_singular()));

  /**
   * The same rule the API counts with, so the highlighted rows and the
   * "unworked for more than a week" figure in the header agree. If one moves,
   * move the other, `LeadListView.UNWORKED_AFTER_DAYS`.
   */
  const stale = (lead: { last_contacted: string | null; created_at: string }) =>
    (daysSince(lead.last_contacted ?? lead.created_at) ?? 0) > 7;

  // An API without response tracking ignores `?unanswered=true` and lists every
  // open lead, so the view is only claimed when the rows prove it was applied.
  let asked = $derived(page.url.searchParams.get('unanswered') === 'true');
  let responseOff = $derived(data.responseLive === false);
  let unanswered = $derived(asked && !responseOff);

  const waitFor = (lead: { is_unanswered: boolean; waiting_since: string | null }) =>
    lead.is_unanswered && lead.waiting_since ? spanText(secondsSince(lead.waiting_since)) : '';
</script>

<PageHeader title={plural}>
  {#snippet sub()}
    {#if unanswered}
      <span class="v2-num">{count(totals.count)}</span>
      {m.leads_list_waiting({ count: totals.count })}
    {:else}
      <span class="v2-num">{count(totals.count)}</span>
      {m.leads_list_open({ count: totals.count })} ·
      <span class="v2-num">{totals.unworked_over_a_week}</span>
      {m.leads_list_unworked()}
    {/if}
  {/snippet}
  {#snippet actions()}
    <a class="v2-btn" href={resolve('leads/board')}>{m.leads_view_board()}</a>
    {#if !responseOff}
      <a class="v2-btn" href={resolve('leads/response-times')}
        ><Timer />{m.leads_response_time_title()}</a
      >
      <a class="v2-btn" href={resolve('leads/outcomes')}><Trophy />{m.leads_outcomes_title()}</a>
    {/if}
    <button class="v2-btn" onclick={() => (importOpen = true)}><Upload />{m.common_import()}</button
    >
    <!-- The page's own query string: the export rebuilds the same API query
         from it, so the file holds every row this list would page through. -->
    <a
      class="v2-btn"
      href="{resolve('api/leads/export')}?{page.url.searchParams}"
      data-sveltekit-reload
    >
      <Download />{m.common_export()}
    </a>
    <a class="v2-btn v2-btn-primary" href={resolve('leads/new')}
      ><Plus />{m.leads_list_new({ singular })}</a
    >
  {/snippet}
</PageHeader>

<FilterBar
  page="leads"
  url={page.url}
  people={data.people}
  tags={data.tags}
  sources={sourceFilterOptions(data.sources)}
  meId={data.meId}
  saved={data.savedViews}
  onlyPresets={responseOff ? ['open', 'mine'] : undefined}
  meta={unanswered ? m.leads_list_filter_meta_waiting() : m.leads_list_filter_meta()}
/>

{#if asked && responseOff}
  <p class="v2-sub v2-pad" style="font-size:12.5px;margin:10px 0 0">
    {m.leads_list_unanswered_off()}
  </p>
{/if}

<LeadImportDrawer
  bind:open={importOpen}
  singular={singular.toLowerCase()}
  plural={plural.toLowerCase()}
/>

<div class="v2-scroll">
  {#if leads.length === 0 && unanswered}
    <EmptyState title={m.leads_list_waiting_empty_title()} body={m.leads_list_waiting_empty_body()}>
      {#snippet icon()}<Timer size={21} />{/snippet}
    </EmptyState>
  {:else if leads.length === 0}
    <EmptyState
      title={m.leads_list_empty_title({ plural: plural.toLowerCase() })}
      body={m.leads_list_empty_body()}
    >
      {#snippet icon()}<Target size={21} />{/snippet}
      {#snippet actions()}
        <a class="v2-btn v2-btn-primary" href={resolve('leads/new')}
          >{m.leads_list_new({ singular })}</a
        >
        <button class="v2-btn" onclick={() => (importOpen = true)}>{m.common_import()}</button>
      {/snippet}
    </EmptyState>
  {:else}
    <div class="v2-table-wrap">
      <table class="v2-table">
        <thead>
          <tr>
            <th>{m.leads_list_col_lead()}</th>
            <th>{m.leads_list_col_company()}</th>
            <th>{m.common_status()}</th>
            <th>{m.leads_list_col_source()}</th>
            <th class="v2-r">{m.leads_list_col_value()}</th>
            <th>{unanswered ? m.leads_list_col_waiting() : m.leads_list_col_last_touch()}</th>
            <th>{m.common_owner()}</th>
          </tr>
        </thead>
        <tbody>
          {#each leads as l (l.id)}
            <tr>
              <td>
                <a class="v2-row-link" href={resolve(`leads/${l.id}`)}>
                  <div class="v2-table-primary">{l.first_name} {l.last_name}</div>
                  <div class="v2-table-secondary">{l.job_title}</div>
                </a>
              </td>
              <td>
                <div>{l.company_name}</div>
                <div class="v2-table-secondary" data-m="hide">
                  {l.industry ? industryLabel(l.industry) : ''}
                </div>
              </td>
              <td data-m="tag"
                ><Pill tone={LEAD_STATUS_TONE[l.status]}
                  >{LEAD_STATUS_LABEL[l.status] ?? l.status}</Pill
                ></td
              >
              <td class="v2-muted" data-m="hide" style="font-size:12.5px">
                {sourceLabel(data.sources, l.source)}
              </td>
              <td class="v2-r v2-num"
                >{l.opportunity_amount ? money(l.opportunity_amount, l.currency) : '—'}</td
              >
              <!--
              `last_contacted` is the only touch the model records. Lead has
              no aging chain: rotting days live on a deal's DealStage, and
              get_aging_status() is Opportunity-only. Where it is null the
              cell says so and falls back to how long the lead has been
              sitting, rather than substituting `updated_at`: an edit is not a
              conversation, and a column that quietly counts them stops being
              worth reading.
            -->
              <td class:v2-muted={!stale(l) && !waitFor(l)} class:overdue={stale(l) || waitFor(l)}>
                {#if waitFor(l)}
                  {m.leads_list_waiting_for({ span: waitFor(l) })}
                {:else if l.last_contacted}
                  {relativeDays(l.last_contacted)}
                {:else}
                  <div>{m.leads_list_not_contacted()}</div>
                  <!-- Stacked, matching the Company cell. Inline, these two ran
                       together into "Not contactedadded 64 days ago". -->
                  <div class="v2-table-secondary" data-m="hide">
                    {m.leads_list_added({ when: relativeDays(l.created_at) })}
                  </div>
                {/if}
              </td>
              <td data-m="hide"><Avatar name={l.assigned_to} size={22} /></td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <p class="v2-sub v2-pad" style="font-size:12px;padding-bottom:24px">
      {#each messageParts(m.leads_list_showing( { shown: slot('shown'), total: slot('total') } )) as p, i (i)}{#if p.key === 'shown'}<span
            class="v2-num">{leads.length}</span
          >{:else if p.key === 'total'}<span class="v2-num">{count(totals.count)}</span
          >{:else}{p.text}{/if}{/each}
    </p>
  {/if}
</div>

<style>
  /* A colour and a weight, not an inline style. The cell already carries a
     class for the ordinary case and the two should be stated the same way. */
  .overdue {
    color: var(--v2-rust);
    font-weight: 600;
  }
</style>
