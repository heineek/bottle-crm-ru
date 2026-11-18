<script lang="ts">
  /**
   * How did we do, one finished period at a time.
   *
   * The goals list answers "how are we doing"; nothing answered this. A closed
   * period cannot move any more, so the interesting number is not pace but
   * whether the number was made, and by how many people.
   *
   * Attainment is counted per goal, not on the pooled total: three reps, two of
   * whom missed while the third doubled up, is not the same story as "the team
   * made its number", and only the per-goal count tells them apart. Both are on
   * screen for that reason.
   *
   * Every figure here is the API's own rollup. Nothing is re-aggregated in the
   * browser.
   */
  import { resolve } from '$app/paths';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { money, count, shortDate } from '#lib/v2/format.js';
  import { GOAL_TYPE_LABEL, PERIOD_TYPE_LABEL } from '#lib/v2/enums.js';
  import { History } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data }: PageProps = $props();

  /**
   * Revenue is money, deals and activities are counts. A period row carries its
   * own `goal_type` for the same reason: the API groups history by period *and*
   * type, because pooling a currency target with a deals target produced a
   * single meaningless number, and formatting one as the other would put a
   * currency symbol in front of a count of deals.
   */
  /**
   * A revenue row is also one currency: the API splits a period by it, since a
   * USD target plus a EUR target is not a number. Takes a period row or a goal,
   * both of which carry `goal_type` and `currency`.
   */
  const unit = (row: { goal_type: string; currency?: string | null }, n: number) =>
    row.goal_type === 'REVENUE' ? money(n, row.currency || data.org.currency) : count(n);

  const met = (g: { target_value: number; progress_value: number }) =>
    g.target_value > 0 && g.progress_value >= g.target_value;

  const tone = (percent: number) => (percent >= 100 ? 'moss' : percent >= 80 ? 'clay' : 'rust');

  const barColor = (percent: number) =>
    percent >= 100 ? 'var(--v2-moss)' : percent >= 80 ? 'var(--v2-clay)' : 'var(--v2-rust)';

  /** The owner of a goal, in the words the list page uses. */
  const owner = (g: { assigned_to: { name: string } | null; team: { name: string } | null }) =>
    g.assigned_to
      ? g.assigned_to.name
      : g.team
        ? m.goals_owner_team({ team: g.team.name })
        : m.goals_owner_whole_org();
</script>

<PageHeader title={m.goals_history_title()}>
  {#snippet crumb()}<a href={resolve('goals')}>{m.goals_title()}</a> ›{/snippet}
  {#snippet sub()}
    {m.goals_history_sub()}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:16px;padding-bottom:32px">
    {#if data.history.length === 0}
      <!-- Says which set is empty. The endpoint narrows a member to their own
           goals and their teams', so "nothing has finished yet" would be a
           claim about the org that a member cannot actually see. -->
      <EmptyState title={m.goals_history_empty_title()} body={m.goals_history_empty_body()}>
        {#snippet icon()}<History size={21} />{/snippet}
        {#snippet actions()}
          <a class="v2-btn" href={resolve('goals')}>{m.goals_history_back()}</a>
        {/snippet}
      </EmptyState>
    {:else}
      <div class="periods">
        {#each data.history as period (period.period_start + period.period_end + period.goal_type + period.currency)}
          <section class="v2-card" style="padding:15px 17px">
            <header>
              <div style="flex:1;min-width:0">
                <div style="font-weight:600;font-size:13.5px">
                  {shortDate(period.period_start)} - {shortDate(period.period_end)}
                </div>
                <div class="v2-sub" style="font-size:11.5px;margin-top:2px">
                  {PERIOD_TYPE_LABEL[period.period_type]} · {GOAL_TYPE_LABEL[
                    period.goal_type
                  ]}{period.currency ? ` (${period.currency})` : ''} ·
                  {#each messageParts(m.goals_history_met_count( { attained: slot('attained'), count: period.goals_count, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'attained'}<span
                        class="v2-num">{period.attained_count}</span
                      >{:else if p.key === 'shown'}<span class="v2-num">{period.goals_count}</span
                      >{:else}{p.text}{/if}{/each}
                </div>
              </div>
              <Pill tone={tone(period.percent)}
                >{m.goals_history_percent_of_target({ percent: period.percent })}</Pill
              >
            </header>

            <div class="v2-bar" style="margin-top:11px">
              <!-- `percent` is uncapped so an over-attaining period reports
                   what it did, but the fill is a bar and a bar cannot be more
                   than full. The number above it carries the overshoot. -->
              <i
                style="width:{Math.min(period.percent, 100)}%;background:{barColor(period.percent)}"
              ></i>
            </div>
            <div class="v2-bar-legend">
              <span class="v2-num">{unit(period, period.achieved)}</span>
              <span
                >{#each messageParts(m.goals_card_of_target( { target: slot('target') } )) as p, i (i)}{#if p.key === 'target'}<span
                      class="v2-num">{unit(period, period.target)}</span
                    >{:else}{p.text}{/if}{/each}</span
              >
            </div>

            <ul class="goals">
              {#each period.goals as g (g.id)}
                <li>
                  <span class="name">{g.name}</span>
                  <span class="v2-sub who">{owner(g)} · {GOAL_TYPE_LABEL[g.goal_type]}</span>
                  <span class="v2-num figures">
                    {unit(g, g.progress_value)} / {unit(g, g.target_value)}
                  </span>
                  <Pill tone={met(g) ? 'moss' : 'slate'}
                    >{met(g) ? m.goals_history_met() : m.goals_status_missed()}</Pill
                  >
                </li>
              {/each}
            </ul>
          </section>
        {/each}
      </div>

      <p class="v2-sub" style="font-size:11.5px;margin-top:14px">
        {m.goals_history_note()}
      </p>
    {/if}
  </div>
</div>

<style>
  .periods {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  header {
    display: flex;
    gap: 10px;
    align-items: flex-start;
  }

  .goals {
    list-style: none;
    margin: 12px 0 0;
    padding: 12px 0 0;
    border-top: 1px solid var(--v2-line-soft);
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  /*
    Phone first: each goal stacks into a labelled block at 390px, so nothing is
    pushed off the right edge, and becomes one row from the 768px breakpoint
    v2.css already uses.
  */
  .goals li {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 2px 10px;
    align-items: center;
    font-size: 12.5px;
  }

  .name {
    font-weight: 550;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .who {
    font-size: 11.5px;
    grid-column: 1;
  }

  .figures {
    grid-column: 1;
    font-size: 12px;
  }

  @media (min-width: 768px) {
    .goals li {
      grid-template-columns: minmax(0, 1.4fr) minmax(0, 1fr) auto auto;
    }

    .who,
    .figures {
      grid-column: auto;
    }

    .figures {
      text-align: right;
    }
  }
</style>
