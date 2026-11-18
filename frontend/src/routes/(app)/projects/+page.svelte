<script lang="ts">
  import { resolve } from '$app/paths';
  import { page } from '$app/state';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import FilterBar from '#lib/v2/components/FilterBar.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { count, shortDate } from '#lib/v2/format.js';
  import {
    PROJECT_STATUS_LABEL,
    PROJECT_STATUS_TONE,
    BILLING_TYPE_LABEL,
    hoursText,
    rowBurn
  } from '#lib/v2/projects.js';
  import { Briefcase, Plus, Search } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data }: PageProps = $props();

  let projects = $derived(data.projects);

  /** The filters in the URL, kept by the search form so a search narrows them. */
  let kept = $derived(
    [...page.url.searchParams.entries()].filter(([key]) => key !== 'q' && key !== 'offset')
  );
</script>

<PageHeader title={m.projects_title()}>
  {#snippet sub()}
    {#each messageParts(m.projects_list_count({ count: data.totals.count, shown: slot('shown') })) as p, i (i)}{#if p.key === 'shown'}<span
          class="v2-num">{count(data.totals.count)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    <a class="v2-btn v2-btn-primary" href={resolve('projects/new')}><Plus />{m.projects_new_button()}</a>
  {/snippet}
</PageHeader>

<FilterBar
  page="projects"
  url={page.url}
  people={data.people}
  accounts={data.accounts}
  meId={data.meId}
  meta={m.projects_list_meta()}
/>

<div class="v2-pad" style="padding-top:10px;flex:none">
  <form method="GET" class="search" role="search">
    {#each kept as [key, value], i (`${key}-${i}`)}
      <input type="hidden" name={key} {value} />
    {/each}
    <input
      class="v2-input"
      type="search"
      name="q"
      value={data.q}
      placeholder={m.projects_search_placeholder()}
      aria-label={m.projects_search_label()}
    />
    <button class="v2-btn" type="submit"><Search size={13} />{m.common_search()}</button>
  </form>
</div>

{#if projects.length === 0}
  <div class="v2-scroll">
    <EmptyState
      title={data.q || page.url.search ? m.projects_empty_match_title() : m.projects_empty_title()}
      body={data.q || page.url.search ? m.projects_empty_match_body() : m.projects_empty_body()}
    >
      {#snippet icon()}<Briefcase size={21} />{/snippet}
      {#snippet actions()}
        <a class="v2-btn v2-btn-primary" href={resolve('projects/new')}>{m.projects_new_button()}</a>
      {/snippet}
    </EmptyState>
  </div>
{:else}
  <div class="v2-scroll">
    <div class="v2-table-wrap">
      <table class="v2-table">
        <thead>
          <tr>
            <th>{m.projects_col_project()}</th>
            <th>{m.common_status()}</th>
            <th>{m.projects_col_budget_used()}</th>
            <th class="v2-r">{m.projects_col_logged()}</th>
            <th>{m.projects_col_due()}</th>
            <th>{m.projects_col_billing()}</th>
          </tr>
        </thead>
        <tbody>
          {#each projects as p (p.id)}
            {@const burn = rowBurn(p.burn)}
            <tr>
              <td data-m="title">
                <a class="v2-row-link" href={resolve(`projects/${p.id}`)}>
                  <div class="v2-table-primary">{p.name}</div>
                  <div class="v2-table-secondary">{p.account.name}</div>
                </a>
              </td>
              <td data-m="tag">
                <Pill tone={PROJECT_STATUS_TONE[p.status] ?? 'slate'}>
                  {PROJECT_STATUS_LABEL[p.status] ?? p.status}
                </Pill>
              </td>
              <td data-m="bar" class="burn-cell">
                {#if burn}
                  <div class="v2-bar" role="img" aria-label={burn.label}>
                    <i style="width:{burn.width}%;background:var(--v2-{burn.tone})"></i>
                  </div>
                  <div class="burn-label" style="color:var(--v2-{burn.tone})">{burn.label}</div>
                {:else}
                  <span class="v2-sub burn-label">{m.projects_no_budget()}</span>
                {/if}
              </td>
              <td class="v2-r v2-num" data-m="meta" data-l="logged">
                {hoursText(p.burn.logged_hours)}
              </td>
              <td data-m="meta">{p.due_date ? m.projects_due_on({ date: shortDate(p.due_date) }) : ''}</td>
              <td data-m="hide" class="v2-sub">{BILLING_TYPE_LABEL[p.billing_type] ?? ''}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <p class="v2-sub v2-pad" style="font-size:12px;padding-bottom:24px">
      {#each messageParts(m.projects_showing_of({ shown: slot('shown'), total: slot('total') })) as p, i (i)}{#if p.key === 'shown'}<span
            class="v2-num">{projects.length}</span
          >{:else if p.key === 'total'}<span class="v2-num">{count(data.totals.count)}</span
          >{:else}{p.text}{/if}{/each}
    </p>
  </div>
{/if}

<style>
  .search {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }
  .search .v2-input {
    flex: 1 1 14rem;
    min-width: 0;
    max-width: 28rem;
  }
  .burn-cell {
    min-width: 140px;
  }
  .burn-label {
    font-size: 11.5px;
    margin-top: 4px;
  }
  @media (max-width: 768px) {
    .search .v2-input,
    .search .v2-btn {
      min-height: 44px;
    }
    .search .v2-input {
      max-width: none;
    }
  }
</style>
