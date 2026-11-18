<script lang="ts">
  import { resolve } from '$app/paths';
  import { asInternalPath } from '#lib/utils/paths.js';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { shortDate } from '#lib/v2/format.js';
  import { spanText } from '#lib/v2/interactions.js';
  import { t } from '#lib/terminology.js';
  import { ChevronRight, Timer, Trophy } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data }: PageProps = $props();

  let plural = $derived(t(data.org?.terminology, 'lead.plural', m.leads_term_plural()));

  const share = (row: { answered: number }, n: number) => (row.answered ? `${n}%` : '—');
</script>

<PageHeader title={m.leads_response_time_title()}>
  {#snippet crumb()}
    <a href={resolve('leads')}>{plural}</a>
    <ChevronRight size={12} />
    <span>{m.leads_response_time_title()}</span>
  {/snippet}
  {#snippet sub()}
    {data.since
      ? m.leads_response_sub_since({
          plural: plural.toLowerCase(),
          date: shortDate(data.since)
        })
      : m.leads_response_sub({ plural: plural.toLowerCase() })}
  {/snippet}
  {#snippet actions()}
    <a class="v2-btn" href={resolve('leads/outcomes')}><Trophy />{m.leads_outcomes_title()}</a>
    <nav class="periods" aria-label={m.leads_period()}>
      {#each data.periods as n (n)}
        <a
          href={resolve(asInternalPath(`/leads/response-times?days=${n}`))}
          aria-current={n === data.days ? 'page' : undefined}>{m.leads_period_days({ count: n })}</a
        >
      {/each}
    </nav>
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  {#if data.rows.length === 0}
    <EmptyState title={m.leads_response_empty_title()} body={m.leads_response_empty_body()}>
      {#snippet icon()}<Timer size={21} />{/snippet}
    </EmptyState>
  {:else}
    <div class="v2-table-wrap" style="margin-top:14px">
      <table class="v2-table">
        <thead>
          <tr>
            <th>{m.leads_col_person()}</th>
            <th class="v2-r">{m.leads_response_col_answered()}</th>
            <th class="v2-r">{m.leads_response_col_median()}</th>
            <th class="v2-r">{m.leads_response_col_5min()}</th>
            <th class="v2-r">{m.leads_response_col_hour()}</th>
            <th class="v2-r">{m.leads_response_col_waiting()}</th>
          </tr>
        </thead>
        <tbody>
          {#each data.rows as row (row.profile || row.name)}
            <tr>
              <td><div class="v2-table-primary">{row.name}</div></td>
              <td class="v2-r v2-num" data-l={m.leads_response_col_answered()}>{row.answered}</td>
              <td class="v2-r v2-num" data-l={m.leads_response_col_median()}>
                {row.median_seconds === null ? '—' : spanText(row.median_seconds)}
              </td>
              <td class="v2-r v2-num" data-l={m.leads_response_col_5min()}
                >{share(row, row.within_5_minutes)}</td
              >
              <td class="v2-r v2-num" data-l={m.leads_response_col_hour()}
                >{share(row, row.within_1_hour)}</td
              >
              <td class="v2-r v2-num" data-l={m.leads_response_col_waiting()}>
                {#if row.unanswered_now && row.profile}
                  <a
                    class="waiting"
                    href={resolve(
                      asInternalPath(
                        `/leads?unanswered=true&assigned_to=${encodeURIComponent(row.profile)}`
                      )
                    )}>{row.unanswered_now}</a
                  >
                {:else}
                  {row.unanswered_now}
                {/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}

  <div class="v2-pad notes">
    <p>
      {m.leads_response_notes()}
    </p>
    <p>
      {m.leads_response_notes_waiting({ plural: plural.toLowerCase() })}
      {data.isAdmin ? '' : m.leads_own_row_only()}
    </p>
  </div>
</div>

<style>
  .periods {
    display: inline-flex;
    border: 1px solid var(--v2-line);
    border-radius: 7px;
    overflow: hidden;
  }
  .periods a {
    display: inline-flex;
    align-items: center;
    padding: 6px 12px;
    font-size: 12.5px;
    color: var(--v2-slate);
    background: var(--v2-card);
    text-decoration: none;
  }
  .periods a + a {
    border-left: 1px solid var(--v2-line);
  }
  .periods a[aria-current='page'] {
    color: var(--v2-ink);
    background: var(--v2-hover);
    font-weight: 600;
  }
  .waiting {
    color: var(--v2-rust);
    font-weight: 600;
  }
  .notes {
    padding-top: 14px;
    padding-bottom: 28px;
    max-width: 680px;
  }
  .notes p {
    margin: 0 0 8px;
    font-size: 12px;
    line-height: 1.55;
    color: var(--v2-slate);
  }
  @media (max-width: 767px) {
    .periods a {
      min-height: 44px;
      padding: 8px 14px;
    }
  }
</style>
