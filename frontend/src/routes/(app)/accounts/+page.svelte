<script lang="ts">
  import { resolve } from '$app/paths';
  import { page } from '$app/state';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import FilterBar from '#lib/v2/components/FilterBar.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { moneyEach, count } from '#lib/v2/format.js';
  import { activeChips, activePresetKey } from '#lib/v2/filters.js';
  import { Download, Plus, Building2 } from '@lucide/svelte';
  import { isOn } from '#lib/v2/modules.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data }: PageProps = $props();

  let accounts = $derived(data.accounts);
  let totals = $derived(data.totals);
  let dealsOn = $derived(isOn(data.modules, 'deals'));
  let invoicesOn = $derived(isOn(data.modules, 'invoices'));
  let ticketsOn = $derived(isOn(data.modules, 'tickets'));
  let leadsOn = $derived(isOn(data.modules, 'leads'));

  /**
   * Whether the view is actually narrowed, rather than merely carrying a query
   * string. `page.url.search` alone is the wrong test: it fires on any param,
   * including ones that are not filters at all. `'all'` is this page's
   * empty-params preset, its declared default, so any other preset counts as
   * filtered even when it sets no field a chip would show.
   */
  let isFiltered = $derived(
    activeChips('accounts', page.url, { people: data.people, tags: data.tags }).length > 0 ||
      activePresetKey('accounts', page.url, data.meId) !== 'all'
  );
</script>

<PageHeader title={m.accounts_list_title()}>
  {#snippet sub()}
    <!-- The count is the size of the whole result set, not of this page. -->
    <span class="v2-num">{count(totals.count)}</span>
    {m.accounts_list_count_noun({ count: totals.count ?? 0 })}
    <!-- `customers` is counted from the rows actually loaded, because the
         accounts endpoint returns no aggregate for it (see the note in
         `lib/server/v2/accounts.js`). Printing it beside a whole-set count
         when only one page is loaded states a smaller number as though it
         covered everything, so it is shown only when this page IS the whole
         set. A figure that disappears beats a figure that is wrong. -->
    {#if dealsOn && (totals.shown ?? 0) >= (totals.count ?? 0)}
      · <span class="v2-num">{count(totals.customers)}</span>
      {m.accounts_list_with_deal_won()}
    {/if}
  {/snippet}
  {#snippet actions()}
    <!-- The page's own query string: the export rebuilds the same API query
         from it, so the file holds every row this list would page through. -->
    <a
      class="v2-btn"
      href="{resolve('api/accounts/export')}?{page.url.searchParams}"
      data-sveltekit-reload
    >
      <Download />{m.common_export()}
    </a>
    <a class="v2-btn v2-btn-primary" href={resolve('accounts/new')}
      ><Plus />{m.accounts_list_new_button()}</a
    >
  {/snippet}
</PageHeader>

{#if isFiltered}
  <p class="v2-sub" style="font-size:11.5px;margin:8px 0 0">
    {m.accounts_list_filtered_note()}
  </p>
{/if}

<FilterBar
  page="accounts"
  url={page.url}
  people={data.people}
  tags={data.tags}
  meId={data.meId}
  saved={data.savedViews}
  meta={dealsOn ? m.accounts_list_sorted_meta() : null}
/>

<div class="v2-scroll">
  {#if accounts.length === 0}
    <EmptyState
      title={m.accounts_list_empty_title()}
      body={leadsOn ? m.accounts_list_empty_body_leads() : m.accounts_list_empty_body()}
    >
      {#snippet icon()}<Building2 size={21} />{/snippet}
      {#snippet actions()}
        <a class="v2-btn v2-btn-primary" href={resolve('accounts/new')}
          >{m.accounts_list_new_button()}</a
        >
        {#if leadsOn}
          <a class="v2-btn" href={resolve('leads')}>{m.accounts_list_go_to_leads()}</a>
        {/if}
      {/snippet}
    </EmptyState>
  {:else}
    <div class="v2-table-wrap">
      <table class="v2-table">
        <thead>
          <tr>
            <th>{m.accounts_list_col_account()}</th>
            <th>{m.accounts_list_col_industry()}</th>
            {#if dealsOn}
              <th class="v2-r">{m.accounts_list_col_won()}</th>
              <th class="v2-r">{m.accounts_list_col_open_pipeline()}</th>
            {/if}
            {#if invoicesOn}<th class="v2-r">{m.accounts_list_col_past_due()}</th>{/if}
            {#if ticketsOn}<th>{m.accounts_list_col_tickets()}</th>{/if}
          </tr>
        </thead>
        <tbody>
          {#each accounts as a (a.id)}
            <tr>
              <td>
                <a class="v2-row-link" href={resolve(`accounts/${a.id}`)}>
                  <div class="v2-table-primary">{a.name}</div>
                  <div class="v2-table-secondary">
                    {[a.city, a.country_display].filter(Boolean).join(', ') ||
                      m.accounts_list_no_address()}
                  </div>
                </a>
              </td>
              <td class="v2-muted" data-m="hide" style="font-size:12.5px">
                {a.industry || '—'}
              </td>
              <!-- All four figures are computed by the API over the whole
                   related set, never derived from the rows on screen. Money is
                   one amount per currency, never added across currencies. -->
              {#if dealsOn}
                <td class="v2-r v2-num" data-m="hide">
                  {a.won_by_currency?.length ? moneyEach(a.won_by_currency) : '—'}
                </td>
                <!-- Labelled on a phone: without the header row, two money
                   columns side by side are two unattributed numbers. -->
                <td class="v2-r v2-num" data-l={m.accounts_list_cell_pipeline()}>
                  {a.pipeline_by_currency?.length ? moneyEach(a.pipeline_by_currency) : '—'}
                </td>
              {/if}
              {#if invoicesOn}
                <td
                  class="v2-r v2-num"
                  data-l={m.accounts_list_col_past_due()}
                  style={a.overdue_by_currency?.length
                    ? 'color:var(--v2-rust);font-weight:600'
                    : ''}
                >
                  {a.overdue_by_currency?.length ? moneyEach(a.overdue_by_currency) : '—'}
                </td>
              {/if}
              {#if ticketsOn}
                <td>
                  {#if a.open_tickets}
                    <Pill tone="slate"
                      >{m.accounts_list_open_tickets({ count: a.open_tickets })}</Pill
                    >
                  {:else}
                    <span class="v2-muted">—</span>
                  {/if}
                </td>
              {/if}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <p class="v2-sub v2-pad" style="font-size:12px;padding-bottom:24px">
      {#if totals.shown < totals.count}
        {#each messageParts(m.accounts_list_showing_some( { shown: slot('shown'), total: slot('total') } )) as p, i (i)}{#if p.key === 'shown'}<span
              class="v2-num">{totals.shown}</span
            >{:else if p.key === 'total'}<span class="v2-num">{count(totals.count)}</span
            >{:else}{p.text}{/if}{/each}
      {:else}
        {#each messageParts(m.accounts_list_showing_all( { total: slot('total') } )) as p, i (i)}{#if p.key === 'total'}<span
              class="v2-num">{count(totals.count)}</span
            >{:else}{p.text}{/if}{/each}
      {/if}
      {#if totals.inactive}
        · {#each messageParts(m.accounts_list_inactive_hidden( { count: slot('count') } )) as p, i (i)}{#if p.key === 'count'}<span
              class="v2-num">{totals.inactive}</span
            >{:else}{p.text}{/if}{/each}
      {/if}
    </p>
  {/if}
</div>
