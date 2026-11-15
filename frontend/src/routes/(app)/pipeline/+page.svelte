<script>
  import { SvelteURLSearchParams } from 'svelte/reactivity';
  import { resolve } from '$app/paths';
  import { asInternalPath } from '#lib/utils/paths.js';
  import { page } from '$app/state';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import FilterBar from '#lib/v2/components/FilterBar.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import Avatar from '#lib/v2/components/Avatar.svelte';
  import StageMeter from '#lib/v2/components/StageMeter.svelte';
  import PipelineSwitcher from '#lib/v2/components/PipelineSwitcher.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { money, moneyEach, sumByCurrency, count, shortDate } from '#lib/v2/format.js';
  import { dealNextStep } from '#lib/v2/deal-next-step.js';
  import { isOn } from '#lib/v2/modules.js';
  import { AGING_TONE, AGING_LABEL } from '#lib/v2/enums.js';
  import { activeChips, activePresetKey, withoutParam } from '#lib/v2/filters.js';
  import { CalendarClock, Columns3, Download, List, Plus, TriangleAlert } from '@lucide/svelte';
  import { flip } from 'svelte/animate';
  import { dndzone } from 'svelte-dnd-action';
  import { refreshAll } from '$app/navigation';
  import { deserialize } from '$app/forms';
  import { holdLockedCard } from '#lib/v2/board-drag.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';

  /** @type {{ data: any }} */
  let { data } = $props();

  const FLIP_MS = 160;

  let deals = $derived(data.deals);
  // With Tasks off the API sends no next step, so the column goes too.
  let tasksOn = $derived(isOn(data.modules, 'tasks'));
  let totals = $derived(data.totals);
  let view = $derived(data.view);

  /* Lanes are built server-side from `/opportunities/kanban/`, which returns
     every stage with its true count. They used to be grouped on the client
     from whatever the list happened to return: correct only until the first
     page boundary, and wrong in the way that looks right: all the columns
     render, each is just short. */
  let lanes = $derived(data.lanes);

  /* Each deal's meter steps through its OWN pipeline's open stages; the list
     can hold deals from several pipelines at once. */
  let openSteps = $derived(
    Object.fromEntries(
      data.pipelines.map((/** @type {any} */ p) => [
        p.id,
        p.stages.filter((/** @type {any} */ s) => s.kind === 'open')
      ])
    )
  );

  /* The Stage filter offers the chosen pipeline's stages, or every code in
     the org when the list spans all of them (one entry per code, since a
     pipeline created from the defaults repeats them). */
  let stageOptions = $derived.by(() => {
    const pool = data.pipelineId
      ? data.pipelines.filter((/** @type {any} */ p) => p.id === data.pipelineId)
      : data.pipelines;
    /** @type {Record<string, string>} */
    const byCode = {};
    for (const p of pool) {
      for (const s of p.stages) byCode[s.code] ??= s.label;
    }
    return Object.entries(byCode).map(([id, name]) => ({ id, name }));
  });

  /* `dndzone` reorders the array it is handed, so the board renders from a
     local copy. Rebuilt whenever the server sends new lanes, which is what
     makes a rejected move snap back: the action calls `refreshAll()` and
     this effect overwrites the optimistic arrangement with the stored one. */
  let boardLanes = $state(/** @type {any[]} */ ([]));
  $effect(() => {
    boardLanes = lanes.map((/** @type {any} */ lane) => ({ ...lane, rows: [...lane.rows] }));
  });

  let moveError = $state('');

  /* The header has to describe the cards under it after an optimistic move,
     not the count the server sent before it. A capped lane keeps the server's
     total, since its own rows are not the whole story either way. */
  function laneCount(/** @type {any} */ lane) {
    return lane.truncated ? lane.count : lane.rows.length;
  }
  /* Money per currency, never added across: there are no exchange rates.
     Nothing priced reads as zero in the org's own currency. */
  function laneMoney(/** @type {any} */ lane) {
    return perCurrency(sumByCurrency(lane.rows));
  }
  function perCurrency(/** @type {{ currency: string, amount: number }[]} */ list) {
    return moneyEach(list) || money(0, data.org.currency);
  }

  function onConsider(/** @type {any} */ lane, /** @type {any} */ e) {
    lane.rows = e.detail.items;
  }

  async function onFinalize(/** @type {any} */ lane, /** @type {any} */ e) {
    lane.rows = e.detail.items;
    const movedId = e.detail.info?.id;
    const index = e.detail.items.findIndex((/** @type {any} */ r) => r.id === movedId);
    // Finalize fires on both lanes of a cross-lane move. Only the lane now
    // holding the card knows where it landed, so only that one persists.
    if (index === -1) return;
    await persistMove(
      movedId,
      lane.stage,
      e.detail.items[index - 1]?.id,
      e.detail.items[index + 1]?.id
    );
  }

  /**
   * Both neighbours are sent when they exist. The server resolves them inside
   * the destination column and ignores any it cannot find there, so a board
   * another user has rearranged since this one loaded degrades to an append
   * rather than to a position computed from a card that has moved on.
   */
  async function persistMove(
    /** @type {string} */ id,
    /** @type {string} */ columnId,
    /** @type {string | undefined} */ aboveId,
    /** @type {string | undefined} */ belowId
  ) {
    const body = new FormData();
    body.set('id', id);
    body.set('column_id', columnId);
    if (aboveId) body.set('above_id', aboveId);
    if (belowId) body.set('below_id', belowId);
    try {
      const res = await fetch('?/move', { method: 'POST', body });
      const result = deserialize(await res.text());
      if (result.type === 'success') {
        moveError = '';
        return;
      }
      moveError =
        (result.type === 'failure' && /** @type {any} */ (result.data)?.error) ||
        m.pipeline_move_failed_reverted();
    } catch {
      moveError = m.pipeline_move_failed_reverted_network();
    }
    await refreshAll();
  }

  /**
   * Whether the current view is actually narrowed, as opposed to merely
   * carrying a query string. `page.url.search` alone is the wrong test: on
   * this page `?view=board` is a layout toggle, not a filter, so a bare
   * "Board" click from the unfiltered list would otherwise claim these
   * numbers are filtered when nothing was. `'all'` is pipeline's own
   * empty-params preset (see `#lib/v2/filters.js`), its declared default, so
   * being on any other preset counts as filtered even when that preset
   * (`open`, `stalled`) sets no field a chip would represent.
   */
  let isFiltered = $derived(
    activeChips('pipeline', page.url, { people: data.people, tags: data.tags }).length > 0 ||
      activePresetKey('pipeline', page.url, data.meId) !== 'all'
  );

  /**
   * The List<->Board toggle used to be two static hrefs, `/pipeline` and
   * `/pipeline?view=board`, so switching layout silently dropped every active
   * filter. Board to List keeps every param and drops only `view`: the list
   * can run everything the board could and more. List to Board keeps
   * `view=board` plus only the params the board offers
   * (`data.boardFields`, always returned by `load` regardless of the current
   * view, see the note in `+page.server.js`); the rest are deliberately
   * dropped, and it is visible rather than silent, since the chips for them
   * disappear along with the params.
   */
  let listHref = $derived(withoutParam(page.url, 'view'));
  let boardHref = $derived.by(() => {
    const next = new SvelteURLSearchParams();
    next.set('view', 'board');
    // `search` mirrors what `+page.server.js` forwards to the board itself
    // (the kanban endpoint runs the deal list's filters, `search` among
    // them); it is not one of `boardFields`
    // because it is not a descriptor field, just like on the list view.
    for (const key of [...(data.boardFields ?? []), 'search', 'pipeline']) {
      const value = page.url.searchParams.get(key);
      if (value) next.set(key, value);
    }
    return `/pipeline?${next}`;
  });
</script>

<PageHeader title={m.pipeline_title()}>
  {#snippet sub()}
    <!-- Totals come from the API aggregate, never from the rows on screen.
         Not "open deals": the default view is now the pipeline's own "All
         deals" preset (empty params), which includes closed stages, so a word
         that was only ever true under the old hardcoded ?open=true would lie
         here as soon as somebody switched presets. -->
    <span class="v2-num">{count(totals.count)}</span>
    {m.pipeline_list_sub_deals({ count: totals.count })} ·
    <span class="v2-num">{perCurrency(totals.amount_by_currency)}</span> ·
    <span class="v2-num">{perCurrency(totals.weighted_by_currency)}</span>
    {m.pipeline_list_sub_weighted()} ·
    <span class="v2-num" style="color:var(--v2-rust)">{totals.stalled_count}</span>
    {m.pipeline_list_sub_stalled({ count: totals.stalled_count })}
  {/snippet}
  {#snippet actions()}
    {#if view === 'board'}
      <a class="v2-btn v2-btn-quiet" href={resolve(asInternalPath(listHref))}
        ><List />{m.pipeline_view_list()}</a
      >
      <span class="v2-btn" aria-current="true"><Columns3 />{m.pipeline_view_board()}</span>
    {:else}
      <span class="v2-btn" aria-current="true"><List />{m.pipeline_view_list()}</span>
      <a class="v2-btn v2-btn-quiet" href={resolve(asInternalPath(boardHref))}
        ><Columns3 />{m.pipeline_view_board()}</a
      >
    {/if}
    <!-- The page's own query string: the export rebuilds the same API query
         from it, so the file holds every row this list would page through. -->
    <a
      class="v2-btn"
      href="{resolve('api/deals/export')}?{page.url.searchParams}"
      data-sveltekit-reload
    >
      <Download />{m.pipeline_export()}
    </a>
    <a class="v2-btn v2-btn-primary" href={resolve('pipeline/new')}
      ><Plus />{m.pipeline_new_deal()}</a
    >
  {/snippet}
</PageHeader>

{#if isFiltered}
  <p class="v2-sub" style="font-size:11.5px;margin:8px 0 0">
    {m.pipeline_list_filtered_note()}
  </p>
{/if}

<div class="v2-pad" style="flex:none">
  <PipelineSwitcher
    url={page.url}
    pipelines={data.pipelines}
    current={data.pipelineId}
    allLabel={view === 'board' ? null : m.pipeline_all_pipelines()}
  />
</div>

<FilterBar
  page="pipeline"
  url={page.url}
  people={data.people}
  tags={data.tags}
  stages={stageOptions}
  meId={data.meId}
  saved={data.savedViews}
  onlyFields={data.onlyFields}
  onlyPresets={data.onlyPresets}
  meta={view === 'board' ? m.pipeline_board_meta() : m.pipeline_list_meta()}
/>

{#if moveError}
  <!-- The card has already snapped back by the time this renders, so the
       message explains a reversal the user has just watched rather than
       warning about one to come. Same banner as the tasks board. -->
  <div class="v2-pad" style="padding-top:12px;flex:none">
    <div class="v2-move-error" role="status">
      <TriangleAlert size={13} style="flex:none" />
      <span>{moveError}</span>
    </div>
  </div>
{/if}

{#if view === 'board'}
  <div class="v2-board">
    {#each boardLanes as lane (lane.stage)}
      <section class="v2-lane">
        <div class="v2-lane-head">
          <span class="v2-label">{lane.label}</span>
          <span class="v2-num">{count(laneCount(lane))} · {laneMoney(lane)}</span>
        </div>
        {#if lane.truncated}
          <!-- The API caps a column at 100 cards. Saying so beats a lane that
               silently stops. Outside the dndzone below, so it never becomes a
               drop target of its own. -->
          <p class="v2-sub" style="padding:0 2px 6px;font-size:11.5px">
            {#each messageParts(m.pipeline_board_truncated( { count: slot('count') } )) as p, i (i)}{#if p.key === 'count'}<span
                  class="v2-num">{lane.rows.length}</span
                >{:else}{p.text}{/if}{/each}
          </p>
        {/if}
        <div
          class="v2-lane-body"
          use:dndzone={{ items: lane.rows, flipDurationMs: FLIP_MS }}
          onconsider={(e) => onConsider(lane, e)}
          onfinalize={(e) => onFinalize(lane, e)}
          onmousedowncapture={holdLockedCard}
          ontouchstartcapture={holdLockedCard}
          onkeydowncapture={holdLockedCard}
        >
          {#each lane.rows as d (d.id)}
            {@const step = dealNextStep(d, tasksOn)}
            <!-- A div, not an anchor: dragging a link fights the browser's own
                 link-drag, so the card is the drag handle and the name inside
                 it is the way in. Matches the tasks board. `data-locked` marks
                 a deal this viewer may not move; the zone's capture handlers
                 keep it from being picked up. -->
            <div
              class="v2-deal-card v2-card-drag"
              data-locked={d.canMove ? undefined : ''}
              animate:flip={{ duration: FLIP_MS }}
            >
              <a
                href={resolve(`pipeline/${d.id}`)}
                style="font-weight:600;letter-spacing:-0.012em;line-height:1.3;color:inherit;text-decoration:none"
                >{d.name}</a
              >
              <div class="v2-sub" style="margin-top:2px">{d.account.name}</div>
              {#if step}
                <div class="v2-next-step" class:late={step.late}>
                  <CalendarClock size={12} style="flex:none" aria-hidden="true" />
                  <span>{step.text}</span>
                </div>
              {/if}
              <div style="margin-top:9px">
                <Pill tone={AGING_TONE[d.aging_status]} dot>
                  {d.aging_status === 'green'
                    ? AGING_LABEL[d.aging_status]
                    : m.pipeline_aging_days_short({
                        label: AGING_LABEL[d.aging_status],
                        days: d.days_in_current_stage
                      })}
                </Pill>
              </div>
              <div class="v2-deal-card-foot">
                <Avatar name={d.assigned_to} size={21} />
                <span class="v2-num" style="font-weight:600">{money(d.amount, d.currency)}</span>
                <span class="v2-sub" style="margin-left:auto;font-size:11.5px"
                  >{shortDate(d.closed_on)}</span
                >
              </div>
            </div>
          {:else}
            <p class="v2-sub" style="padding:10px 2px;font-size:12px">
              {m.pipeline_board_lane_empty()}
            </p>
          {/each}
        </div>
      </section>
    {/each}
  </div>
{:else if deals.length === 0}
  <div class="v2-scroll">
    <EmptyState
      title={m.pipeline_empty_title()}
      body={isOn(data.modules, 'leads') ? m.pipeline_empty_body_leads() : m.pipeline_empty_body()}
    >
      {#snippet icon()}<Columns3 size={21} />{/snippet}
      {#snippet actions()}
        <a class="v2-btn v2-btn-primary" href={resolve('pipeline/new')}>{m.pipeline_new_deal()}</a>
        {#if isOn(data.modules, 'leads')}
          <a class="v2-btn" href={resolve('leads')}>{m.pipeline_empty_go_to_leads()}</a>
        {/if}
      {/snippet}
    </EmptyState>
  </div>
{:else}
  <div class="v2-scroll">
    <div class="v2-table-wrap">
      <table class="v2-table">
        <thead>
          <tr>
            <th>{m.pipeline_col_deal()}</th>
            <th>{m.pipeline_col_stage()}</th>
            <th>{m.pipeline_col_health()}</th>
            {#if tasksOn}<th>{m.pipeline_col_next_step()}</th>{/if}
            <th class="v2-r">{m.pipeline_col_value()}</th>
            <th>{m.pipeline_col_closing()}</th>
            <th class="v2-r">{m.pipeline_col_in_stage()}</th>
            <th>{m.pipeline_col_owner()}</th>
          </tr>
        </thead>
        <tbody>
          {#each deals as d (d.id)}
            {@const step = dealNextStep(d, tasksOn)}
            <tr>
              <td>
                <a class="v2-row-link" href={resolve(`pipeline/${d.id}`)}>
                  <div class="v2-table-primary">{d.name}</div>
                  <div class="v2-table-secondary">{d.account.name}</div>
                </a>
              </td>
              <td>
                <StageMeter
                  code={d.stage}
                  name={d.stage_label}
                  kind={d.stage_kind}
                  steps={openSteps[d.pipeline] ?? []}
                />
              </td>
              <td data-m="tag">
                <Pill tone={AGING_TONE[d.aging_status]} dot>{AGING_LABEL[d.aging_status]}</Pill>
              </td>
              {#if tasksOn}
                <td>
                  {#if step}
                    <span class="v2-next-step" class:late={step.late}>
                      <CalendarClock size={12} style="flex:none" aria-hidden="true" />
                      <span>{step.text}</span>
                    </span>
                  {/if}
                </td>
              {/if}
              <td class="v2-r v2-num" style="font-weight:600">{money(d.amount, d.currency)}</td>
              <td>{shortDate(d.closed_on)}</td>
              <!-- Hidden on a phone: the Health pill beside the title is computed
                   from this same number, so showing both spends a line to say
                   the same thing twice. -->
              <td
                class="v2-r v2-num"
                data-m="hide"
                style={d.aging_status === 'red'
                  ? 'color:var(--v2-rust);font-weight:600'
                  : 'color:var(--v2-slate)'}
              >
                {m.pipeline_days_short({ days: d.days_in_current_stage })}
              </td>
              <td data-m="hide"><Avatar name={d.assigned_to} size={22} /></td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <p class="v2-sub v2-pad" style="font-size:12px;padding-bottom:24px">
      {#each messageParts(m.pipeline_list_showing( { shown: slot('shown'), total: slot('total') } )) as p, i (i)}{#if p.key === 'shown'}<span
            class="v2-num">{deals.length}</span
          >{:else if p.key === 'total'}<span class="v2-num">{count(totals.count)}</span
          >{:else}{p.text}{/if}{/each}
    </p>
  </div>
{/if}

<style>
  /* One line on a card and in a row: the title can be anything a person
     typed, so it truncates rather than pushing the card or the row wider at
     390px. `late` is overdue or nothing scheduled, the two that need a hand. */
  .v2-next-step {
    display: flex;
    align-items: center;
    gap: 5px;
    min-width: 0;
    max-width: 100%;
    margin-top: 6px;
    font-size: 11.5px;
    color: var(--v2-slate);
  }
  .v2-next-step > span {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .v2-next-step.late {
    color: var(--v2-rust);
  }
  td > .v2-next-step {
    display: inline-flex;
    max-width: 240px;
    margin-top: 0;
  }
</style>
