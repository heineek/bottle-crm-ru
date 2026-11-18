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

  let singular = $derived(t(data.org?.terminology, 'lead.singular', m.leads_term_singular()));
  let plural = $derived(t(data.org?.terminology, 'lead.plural', m.leads_term_plural()));
  let empty = $derived(data.rows.every((r) => !r.won && !r.lost && !r.new_leads));
  let measuringLater = $derived(
    !!data.since && !!data.measured_since && data.measured_since > data.since
  );

  const rate = (n: number | null) => (n === null ? '—' : `${n}%`);
  const span = (n: number | null) => (n === null ? '—' : spanText(n));
</script>

<PageHeader title={m.leads_outcomes_title()}>
  {#snippet crumb()}
    <a href={resolve('leads')}>{plural}</a>
    <ChevronRight size={12} />
    <span>{m.leads_outcomes_title()}</span>
  {/snippet}
  {#snippet sub()}
    {data.since
      ? m.leads_outcomes_sub_since({
          plural: plural.toLowerCase(),
          date: shortDate(data.since)
        })
      : m.leads_outcomes_sub({ plural: plural.toLowerCase() })}
    {#if measuringLater}
      <span class="measuring"
        >{m.leads_measuring_since({ date: shortDate(data.measured_since) })}</span
      >
    {/if}
  {/snippet}
  {#snippet actions()}
    <a class="v2-btn" href={resolve('leads/response-times')}
      ><Timer />{m.leads_response_time_title()}</a
    >
    <nav class="periods" aria-label={m.leads_period()}>
      {#each data.periods as n (n)}
        <a
          href={resolve(asInternalPath(`/leads/outcomes?days=${n}`))}
          aria-current={n === data.days ? 'page' : undefined}>{m.leads_period_days({ count: n })}</a
        >
      {/each}
    </nav>
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  {#if empty}
    <EmptyState title={m.leads_outcomes_empty_title()} body={m.leads_outcomes_empty_body()}>
      {#snippet icon()}<Trophy size={21} />{/snippet}
    </EmptyState>
  {:else}
    <div class="v2-table-wrap" style="margin-top:14px">
      <table class="v2-table">
        <thead>
          <tr>
            <th>{m.leads_col_person()}</th>
            <th class="v2-r">{m.leads_outcomes_col_won()}</th>
            <th class="v2-r">{m.leads_outcomes_col_lost()}</th>
            <th class="v2-r">{m.leads_outcomes_col_win_rate()}</th>
            <th class="v2-r">{m.leads_outcomes_col_median_win()}</th>
            <th class="v2-r">{m.leads_col_new_leads()}</th>
          </tr>
        </thead>
        <tbody>
          {#each data.rows as row (row.profile || row.name)}
            <tr>
              <td><div class="v2-table-primary">{row.name}</div></td>
              <td class="v2-r v2-num" data-l={m.leads_outcomes_col_won()}>{row.won}</td>
              <td class="v2-r v2-num" data-l={m.leads_outcomes_col_lost()}>{row.lost}</td>
              <td class="v2-r v2-num" data-l={m.leads_outcomes_col_win_rate()}
                >{rate(row.win_rate)}</td
              >
              <td class="v2-r v2-num" data-l={m.leads_outcomes_col_median_win()}>
                {span(row.median_seconds_to_win)}
              </td>
              <td class="v2-r v2-num" data-l={m.leads_col_new_leads()}>{row.new_leads}</td>
            </tr>
          {/each}
          {#if data.totals}
            <tr class="totals">
              <td><div class="v2-table-primary">{m.leads_row_everyone()}</div></td>
              <td class="v2-r v2-num" data-l={m.leads_outcomes_col_won()}>{data.totals.won}</td>
              <td class="v2-r v2-num" data-l={m.leads_outcomes_col_lost()}>{data.totals.lost}</td>
              <td class="v2-r v2-num" data-l={m.leads_outcomes_col_win_rate()}
                >{rate(data.totals.win_rate)}</td
              >
              <td class="v2-r v2-num" data-l={m.leads_outcomes_col_median_win()}>
                {span(data.totals.median_seconds_to_win)}
              </td>
              <td class="v2-r v2-num" data-l={m.leads_col_new_leads()}>{data.totals.new_leads}</td>
            </tr>
          {/if}
        </tbody>
      </table>
    </div>
  {/if}

  <div class="v2-pad notes">
    <p>
      {m.leads_outcomes_notes({ singular: singular.toLowerCase() })}
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
  .measuring {
    display: block;
    margin-top: 2px;
    color: var(--v2-slate);
  }
  .totals td {
    font-weight: 600;
    border-top: 1px solid var(--v2-line);
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
