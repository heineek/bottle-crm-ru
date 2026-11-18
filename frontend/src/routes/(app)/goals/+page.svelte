<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * Quota, read against the calendar.
   *
   * A percentage of target is meaningless on its own: 59% is excellent in week
   * two of a quarter and dire in week eleven. SalesGoal.status already knows
   * this. It compares progress against expected pace and returns on_track /
   * at_risk / behind, but v1 rendered only the raw percentage, so the model's
   * one interesting judgement never reached the screen. Here every bar carries
   * a pace marker showing how far through the period we are, and the gap
   * between fill and marker is the whole story.
   *
   * The elapsed-time figure is computed here from period_start and period_end,
   * which is date arithmetic on two fields already in the payload, not an
   * aggregate. Everything that counts records (progress_value,
   * progress_percent, status) stays server-side.
   */
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import Avatar from '#lib/v2/components/Avatar.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { money, moneyEach, count, shortDate, daysSince } from '#lib/v2/format.js';
  import {
    GOAL_TYPE_LABEL,
    GOAL_STATUS_LABEL,
    GOAL_STATUS_TONE,
    PERIOD_TYPE_LABEL
  } from '#lib/v2/enums.js';
  import { Plus, Target, Trophy, History } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data }: PageProps = $props();

  let totals = $derived(data.totals);

  /**
   * The filter bar submits as a plain GET form, so the state lives in the URL:
   * a filtered view is linkable, survives a reload, and re-runs the server load
   * that applies it. The backend does the filtering (`period_type`, `search`,
   * `current`, `active` on the list endpoint); nothing here narrows an array
   * that was already fetched in full.
   */
  let filters = $derived(data.filters ?? { period_type: '', q: '', window: '' });
  let filtered = $derived(Boolean(filters.period_type || filters.q || filters.window));

  type Goal = {
    period_start: string;
    period_end: string;
    progress_percent: number;
    status: string;
    type_weights?: Record<string, number>;
  };

  /** How many deal types this goal re-weighs, for the badge on its card. */
  const weightedTypes = (g: Goal) =>
    Object.entries(g.type_weights ?? {}).filter(([, w]) => Number(w) !== 1).length;

  /** How far through the period we are, 0-100. */
  function elapsedPercent(g: Goal) {
    const start = new Date(g.period_start).getTime();
    const end = new Date(g.period_end).getTime();
    if (!(end > start)) return 100;
    return Math.min(100, Math.max(0, Math.round(((Date.now() - start) / (end - start)) * 100)));
  }

  const isOver = (g: Goal) => (daysSince(g.period_end) ?? -1) > 0;

  /**
   * SalesGoal.status has no terminal "missed": once period_end passes,
   * expected_pace is pinned at 100, so a goal that ended weeks short keeps
   * reporting "behind" as though you could still do something about it. A
   * finished period is reported as met or missed instead.
   */
  const statusLabel = (g: Goal) =>
    isOver(g)
      ? g.progress_percent >= 100
        ? m.goals_status_target_met()
        : m.goals_status_missed()
      : GOAL_STATUS_LABEL[g.status];

  const statusTone = (g: Goal) =>
    isOver(g) ? (g.progress_percent >= 100 ? 'moss' : 'slate') : GOAL_STATUS_TONE[g.status];

  const barColor = (g: Goal) => {
    const tone = statusTone(g);
    return tone === 'moss'
      ? 'var(--v2-moss)'
      : tone === 'rust'
        ? 'var(--v2-rust)'
        : tone === 'clay'
          ? 'var(--v2-clay)'
          : 'var(--v2-slate)';
  };

  /**
   * Revenue goals are money in the goal's own currency (only won deals in that
   * currency count toward it); deals and activities goals are plain counts.
   * Takes anything with `goal_type` and `currency`, so the leaderboard rows use
   * it too: the board ranks every type together.
   */
  const value = (g: { goal_type: string; currency?: string | null }, n: number) =>
    g.goal_type === 'REVENUE' ? money(n, g.currency || data.org.currency) : count(n);

  /** A per-currency total, or a dash when no revenue goal is active. */
  const moneyTotal = (list: { currency: string; amount: number }[]) => moneyEach(list) || '—';
</script>

<PageHeader title={m.goals_title()}>
  {#snippet sub()}
    {#if totals.revenue}
      {#each messageParts(m.goals_header_summary_revenue( { achieved: slot('achieved'), target: slot('target'), count: totals.active, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'achieved'}<span
            class="v2-num">{moneyTotal(totals.achieved)}</span
          >{:else if p.key === 'target'}<span class="v2-num">{moneyTotal(totals.target)}</span
          >{:else if p.key === 'shown'}<span class="v2-num">{count(totals.active)}</span
          >{:else}{p.text}{/if}{/each}
    {:else}
      {#each messageParts(m.goals_header_summary( { count: totals.active, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
            class="v2-num">{count(totals.active)}</span
          >{:else}{p.text}{/if}{/each}
    {/if}
  {/snippet}
  {#snippet actions()}
    <a class="v2-btn" href={resolve('goals/history')}><History />{m.goals_history_link()}</a>
    {#if data.can_edit}
      <a class="v2-btn v2-btn-primary" href={resolve('goals/new')}><Plus />{m.goals_new_button()}</a
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-pad" style="padding-top:16px;flex:none">
  <div class="v2-stats">
    <!-- Money only, so revenue goals only, one figure per currency: a deals
         target is not an amount, and there are no exchange rates. -->
    <StatCard
      label={m.goals_stat_committed()}
      value={moneyTotal(totals.target)}
      tone="ink"
      detail={m.goals_stat_committed_detail()}
    />
    <StatCard
      label={m.goals_stat_booked()}
      value={moneyTotal(totals.achieved)}
      tone="moss"
      detail={m.goals_stat_booked_detail()}
    />
    <StatCard
      label={m.goals_stat_behind()}
      value={count(totals.behind)}
      tone={totals.behind ? 'rust' : 'slate'}
      detail={totals.behind ? m.goals_stat_behind_detail() : m.goals_stat_behind_none()}
    />
    <StatCard label={m.goals_stat_active()} value={count(totals.active)} tone="slate" />
  </div>

  <form class="filters" method="GET" data-sveltekit-reset="false" data-sveltekit-replacestate>
    <input
      class="v2-input"
      type="search"
      name="q"
      value={filters.q}
      placeholder={m.goals_filter_search()}
      aria-label={m.goals_filter_search()}
    />
    <select class="v2-input" name="period_type" aria-label={m.goals_filter_period_label()}>
      <option value="">{m.goals_filter_period_any()}</option>
      {#each Object.entries(PERIOD_TYPE_LABEL) as [key, label] (key)}
        <option value={key} selected={filters.period_type === key}>{label}</option>
      {/each}
    </select>
    <select class="v2-input" name="window" aria-label={m.goals_filter_window_label()}>
      <option value="">{m.goals_filter_window_all()}</option>
      <option value="current" selected={filters.window === 'current'}
        >{m.goals_filter_window_current()}</option
      >
      <option value="active" selected={filters.window === 'active'}
        >{m.goals_filter_window_active()}</option
      >
    </select>
    <button class="v2-btn" type="submit">{m.common_filter()}</button>
    {#if filtered}
      <a class="v2-btn" href={resolve('goals')}>{m.goals_filter_clear()}</a>
    {/if}
  </form>
</div>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-bottom:32px">
    {#if data.goals.length === 0}
      <!-- Three messages. The list is narrowed server-side to the goals a
           non-admin may see (their own and their teams'), so "No goals set" is
           a claim about the org that a member may be reading in front of an org
           full of goals that are simply not theirs. And with a filter applied
           neither claim is true: the goals exist, this view just excluded them,
           so saying "no goals set" would send someone off to create a duplicate
           of one they already have. -->
      {#if filtered}
        <EmptyState title={m.goals_empty_filtered_title()} body={m.goals_empty_filtered_body()}>
          {#snippet icon()}<Target size={21} />{/snippet}
          {#snippet actions()}
            <a class="v2-btn" href={resolve('goals')}>{m.goals_filter_clear_filter()}</a>
          {/snippet}
        </EmptyState>
      {:else}
        <EmptyState
          title={data.can_edit ? m.goals_empty_admin_title() : m.goals_empty_member_title()}
          body={data.can_edit ? m.goals_empty_admin_body() : m.goals_empty_member_body()}
        >
          {#snippet icon()}<Target size={21} />{/snippet}
          {#snippet actions()}
            {#if data.can_edit}
              <a class="v2-btn v2-btn-primary" href={resolve('goals/new')}>{m.goals_new_button()}</a
              >
            {/if}
          {/snippet}
        </EmptyState>
      {/if}
    {:else}
      <div class="v2-split v2-split-wide">
        <div>
          <div class="v2-label" style="margin-bottom:10px">{m.goals_list_this_period()}</div>
          <div style="display:flex;flex-direction:column;gap:10px">
            {#each data.goals as g (g.id)}
              {@const elapsed = elapsedPercent(g)}
              {@const over = isOver(g)}
              <div class="v2-card" style="padding:15px 17px;opacity:{g.is_active ? 1 : 0.65}">
                <div style="display:flex;gap:10px;align-items:flex-start;margin-bottom:11px">
                  <div style="flex:1;min-width:0">
                    <div style="font-weight:600;font-size:13.5px">{g.name}</div>
                    <div class="v2-sub" style="font-size:11.5px;margin-top:2px">
                      {GOAL_TYPE_LABEL[g.goal_type]} · {PERIOD_TYPE_LABEL[g.period_type]} ·
                      {shortDate(g.period_start)} - {shortDate(g.period_end)}
                      <!-- Named on the card because a weighted goal's progress
                           does not add up to the deals behind it, and someone
                           checking the arithmetic against the pipeline needs to
                           know that before they file a bug. -->
                      {#if weightedTypes(g)}
                        · <span title={m.goals_card_weighted_title()}
                          >{m.goals_card_weighted({ count: weightedTypes(g) })}</span
                        >
                      {/if}
                    </div>
                  </div>
                  <div style="display:flex;flex-direction:column;align-items:flex-end;gap:5px">
                    <Pill tone={statusTone(g)}>{statusLabel(g)}</Pill>
                    {#if data.can_edit}
                      <a
                        href={resolve(`goals/${g.id}/edit`)}
                        style="font-size:11px;color:var(--v2-slate);text-decoration:none"
                        >{m.common_edit()}</a
                      >
                    {/if}
                  </div>
                </div>

                <div style="display:flex;align-items:baseline;gap:8px;margin-bottom:6px">
                  <span class="v2-num" style="font-weight:650;font-size:15px">
                    {value(g, g.progress_value)}
                  </span>
                  <span class="v2-sub" style="font-size:12px">
                    {m.goals_card_of_target({ target: value(g, g.target_value) })}
                  </span>
                  <!-- The server's progress_percent, not a division done here.
                       SalesGoal floors it (int()) and caps it at 100, so
                       recomputing gives 60% where the model says 59% and a
                       reader has no way to tell which is real. Over-target is
                       readable from the two figures to the left. -->
                  <span
                    class="v2-num"
                    style="margin-left:auto;font-weight:600;font-size:12.5px;color:{barColor(g)}"
                  >
                    {g.progress_percent}%
                  </span>
                </div>

                <!-- Fill is attainment; the hairline is where the calendar
                     says you should be. Behind means the fill is left of the
                     line, and you can see that without reading a number. -->
                <div class="v2-bar">
                  <i style="width:{g.progress_percent}%;background:{barColor(g)}"></i>
                  {#if !over}
                    <span
                      class="v2-bar-pace"
                      style="left:calc({elapsed}% - 1px)"
                      title={m.goals_card_elapsed({ percent: `${elapsed}%` })}
                    ></span>
                  {/if}
                </div>
                <div class="v2-bar-legend">
                  <span>
                    {#if g.assigned_to}
                      {g.assigned_to.name}
                    {:else if g.team}
                      {m.goals_owner_team({ team: g.team.name })}
                    {:else}
                      {m.goals_owner_whole_org()}
                    {/if}
                  </span>
                  <span>
                    {#if over}
                      {m.goals_card_period_ended({ date: shortDate(g.period_end) })}
                    {:else}
                      {#each messageParts(m.goals_card_elapsed( { percent: slot('percent') } )) as p, i (i)}{#if p.key === 'percent'}<span
                            class="v2-num">{elapsed}%</span
                          >{:else}{p.text}{/if}{/each}
                    {/if}
                  </span>
                </div>
              </div>
            {/each}
          </div>
        </div>

        <div>
          <div class="v2-label" style="margin-bottom:10px">
            <Trophy size={12} style="vertical-align:-1px;margin-right:4px" />
            {m.goals_leaderboard_title()}
          </div>
          <div class="v2-card" style="overflow:hidden">
            {#each data.leaderboard as row (row.goal_id)}
              <div
                style="display:flex;gap:11px;align-items:center;padding:11px 14px;border-bottom:1px solid var(--v2-line-soft)"
              >
                <span
                  class="v2-num v2-muted"
                  style="width:15px;text-align:right;font-size:12px;flex:none">{row.rank}</span
                >
                <Avatar name={row.user} size={26} />
                <div style="flex:1;min-width:0">
                  <div style="font-size:12.5px;font-weight:550">{row.user}</div>
                  <div class="v2-sub v2-num" style="font-size:11px">
                    {m.goals_leaderboard_figures({
                      achieved: value(row, row.achieved),
                      target: value(row, row.target)
                    })}
                  </div>
                </div>
                <!-- Uncapped on purpose: 104% is the interesting number, and
                     the model caps progress_percent at 100, so the leaderboard
                     carries its own. -->
                <span
                  class="v2-num"
                  style="font-weight:650;font-size:13px;color:{row.percent >= 100
                    ? 'var(--v2-moss)'
                    : 'var(--v2-ink)'}"
                >
                  {row.percent}%
                </span>
              </div>
            {:else}
              <!-- Newly reachable: the board is now scoped the way the list
                   is, so somebody with no current monthly goal of their own
                   sees nothing here rather than the whole org. An empty card
                   under a heading reads as a failure, so it says why. -->
              <p class="v2-sub" style="padding:14px;margin:0;font-size:12px">
                {m.goals_leaderboard_empty()}
              </p>
            {/each}
          </div>

          {#if data.leaderboard.length}
            <p class="v2-sub" style="font-size:11.5px;margin-top:11px">
              {m.goals_leaderboard_note()}
            </p>
          {/if}
        </div>
      </div>
    {/if}
  </div>
</div>

<style>
  /*
    Phone first: one control per row at 390px, where a four-across bar would
    squeeze the search box to nothing. It widens into a single row from the
    768px breakpoint v2.css already uses.
  */
  .filters {
    display: grid;
    grid-template-columns: 1fr;
    gap: 8px;
    margin-top: 12px;
  }

  .filters :global(.v2-btn) {
    min-height: 44px;
    justify-content: center;
  }

  .filters :global(.v2-input) {
    min-height: 44px;
  }

  @media (min-width: 768px) {
    .filters {
      grid-template-columns: minmax(0, 1fr) auto auto auto auto;
      align-items: center;
    }
  }
</style>
