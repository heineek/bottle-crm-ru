<script>
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { CASE_PRIORITY_LABEL, CASE_TYPE_LABEL } from '#lib/v2/enums.js';
  import { resolve } from '$app/paths';
  /**
   * Service health. The questions, in the order a support lead asks them:
   * is the queue growing, are we answering in time (the first reply, then
   * every reply after it), are customers satisfied, who is carrying it, and
   * what is it made of. Every figure covers the same days: the satisfaction
   * and next-response figures are fetched from the window's first day (see
   * `service.js`).
   *
   * No chart library. Every mark here is a div sized by a percentage, which
   * keeps the page honest about how little it is actually drawing, and a
   * fourteen-bar series does not need an axis, a legend and 90kb of SVG.
   *
   * WHAT THIS PAGE DOES NOT DO
   * It never averages across priorities. "SLA attainment: 92%" folds four
   * different promises into one number that describes none of them; an urgent
   * incident answered in ninety minutes and a low-priority question answered
   * in ninety minutes are not the same event. Attainment is reported per
   * priority, against that priority's own target, or not at all.
   */
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SectionTabs from '#lib/v2/components/SectionTabs.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import Avatar from '#lib/v2/components/Avatar.svelte';
  import { count, shortDate } from '#lib/v2/format.js';
  import { Clock } from '@lucide/svelte';
  import { isOn } from '#lib/v2/modules.js';

  /** @type {{ data: any }} */
  let { data } = $props();

  let canView = $derived(data.can_view);
  let totals = $derived(data.totals);
  // Floor at 1 so an empty or all-zero window scales cleanly to flat bars
  // rather than dividing by a zero (or -Infinity) peak.
  let peak = $derived(Math.max(1, ...data.volume.map((d) => Math.max(d.opened, d.closed))));

  /**
   * Minutes → "41m" / "2h 20m" / "1d 3h" / "1d". A number of minutes is not a
   * duration, and neither is "1d 0h". A zero remainder is dropped rather than
   * printed, at every scale.
   */
  function duration(mins) {
    if (mins == null) return '—';
    if (mins < 60) return m.tickets_duration_m({ n: mins });
    const h = Math.floor(mins / 60);
    const rest = mins % 60;
    if (h < 24)
      return rest ? m.tickets_duration_h_m({ h, m: rest }) : m.tickets_duration_h({ n: h });
    const d = Math.floor(h / 24);
    return h % 24 ? m.tickets_duration_d_h({ d, h: h % 24 }) : m.tickets_duration_d({ n: d });
  }

  // Attainment among *decided* cases (met vs missed). A priority with no
  // decided cases yet (all in-flight, or none at all) has no percentage to
  // report, so it returns null and the row shows "—" rather than "NaN%".
  const attainment = (r) => {
    const decided = r.met + r.missed;
    return decided ? Math.round((r.met / decided) * 100) : null;
  };
  const barColor = (pct) =>
    pct == null
      ? 'var(--v2-line)'
      : pct >= 95
        ? 'var(--v2-moss)'
        : pct >= 85
          ? 'var(--v2-clay)'
          : 'var(--v2-rust)';

  /** Net change over the window. Opened minus closed is the backlog's direction. */
  let net = $derived(totals.opened - totals.closed);

  /** The next-response endpoint reports hours; `duration` reads whole minutes. */
  const minutesOf = (hours) => (hours == null ? null : Math.round(hours * 60));

  // Best first, so the bars read down from the answer most tickets hope for.
  const RATINGS = [5, 4, 3, 2, 1];
  const ratingShare = (n) => (data.csat.count ? Math.round((n / data.csat.count) * 100) : 0);
</script>

<PageHeader title={m.tickets_analytics_title()}>
  {#snippet sub()}
    {#if canView}
      {#each messageParts(m.tickets_analytics_window( { count: totals.window_days, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
            class="v2-num">{totals.window_days}</span
          >{:else}{p.text}{/if}{/each}
    {:else}
      {m.tickets_analytics_service_health()}
    {/if}
  {/snippet}
</PageHeader>

<SectionTabs set="tickets" />

{#if !canView}
  <div class="v2-pad" style="padding-top:40px">
    <!-- Centred, not left-hugging: this is all a non-admin sees on this page,
         so a capped card pinned to the left leaves the rest of a wide screen
         empty. margin-inline centres the column. -->
    <div class="v2-card" style="padding:20px 22px;max-width:520px;margin-inline:auto">
      <strong>{m.tickets_analytics_admins_title()}</strong>
      <p>
        {m.tickets_analytics_admins_body()}
        <a href={resolve('tickets')}>{m.tickets_analytics_admins_link()}</a
        >{m.tickets_analytics_admins_tail()}
      </p>
    </div>
  </div>
{:else}
  <div class="v2-pad" style="padding-top:16px;flex:none">
    <div class="v2-stats">
      <StatCard label={m.tickets_analytics_opened()} value={count(totals.opened)} tone="ink" />
      <StatCard label={m.tickets_analytics_closed()} value={count(totals.closed)} tone="moss" />
      <StatCard
        label={m.tickets_analytics_backlog()}
        value={count(totals.open_now)}
        tone={net > 0 ? 'clay' : 'slate'}
        detail={net > 0
          ? m.tickets_analytics_backlog_grew({ count: net })
          : net < 0
            ? m.tickets_analytics_backlog_shrank({ count: Math.abs(net) })
            : m.tickets_analytics_backlog_level()}
      />
      <StatCard
        label={m.tickets_analytics_median_resolution()}
        value={m.tickets_duration_h({ n: totals.median_resolution_hours })}
        tone="slate"
        detail={m.tickets_analytics_median_resolution_detail()}
      />
    </div>
  </div>

  <div class="v2-scroll">
    <div class="v2-pad" style="padding-bottom:32px">
      <!-- Volume -->
      <div class="v2-card" style="padding:16px 18px 14px;margin-bottom:18px">
        <div style="display:flex;align-items:baseline;gap:14px;margin-bottom:14px">
          <div class="v2-label">{m.tickets_analytics_volume_title()}</div>
          <span class="v2-sub" style="font-size:11.5px;margin-left:auto">
            <i class="v2-swatch v2-swatch-in"></i>{m.tickets_analytics_legend_opened()}
            <i class="v2-swatch" style="margin-left:10px"></i>{m.tickets_analytics_legend_closed()}
          </span>
        </div>
        <div class="v2-cols">
          {#each data.volume as d (d.date)}
            <div
              class="v2-col"
              title={m.tickets_analytics_volume_bar({
                date: shortDate(d.date),
                opened: d.opened,
                closed: d.closed
              })}
            >
              <i class="in" style="height:{(d.opened / peak) * 100}%"></i>
              <i class="out" style="height:{(d.closed / peak) * 100}%"></i>
            </div>
          {/each}
        </div>
        <div class="v2-cols-axis">
          {#each data.volume as d, i (d.date)}
            <!-- Every other label. Fourteen dates at 10px overlap; seven do not. -->
            <span>{i % 2 === 0 ? shortDate(d.date) : ''}</span>
          {/each}
        </div>
      </div>

      <div class="v2-split" style="margin-bottom:18px">
        <!-- First response -->
        <div class="v2-card" style="padding:16px 18px">
          <div class="v2-label" style="margin-bottom:4px">{m.tickets_analytics_first_title()}</div>
          <p class="v2-sub" style="font-size:11.5px;margin:0 0 14px">
            {m.tickets_analytics_first_body()}
          </p>
          {#each data.firstResponse as r (r.priority)}
            {@const pct = attainment(r)}
            <div style="margin-bottom:14px">
              <div
                style="display:flex;align-items:baseline;gap:8px;font-size:12.5px;margin-bottom:5px"
              >
                <b style="font-weight:600">{CASE_PRIORITY_LABEL[r.priority] ?? r.priority}</b>
                <span class="v2-sub" style="font-size:11.5px">
                  {m.tickets_analytics_target_median({
                    target: duration(r.target_minutes),
                    median: duration(r.median_minutes)
                  })}
                </span>
                <span
                  class="v2-num"
                  style="margin-left:auto;font-weight:650;color:{pct == null
                    ? 'var(--v2-slate)'
                    : barColor(pct)}"
                >
                  {pct == null ? '—' : `${pct}%`}
                </span>
              </div>
              <div class="v2-bar">
                <i style="width:{pct ?? 0}%;background:{barColor(pct)}"></i>
              </div>
              <div class="v2-bar-legend">
                <span><span class="v2-num">{r.met}</span> {m.tickets_analytics_in_time()}</span>
                <span>
                  {#if r.missed}
                    <span class="v2-num" style="color:var(--v2-rust)">{r.missed}</span>
                    {m.tickets_analytics_late()}
                  {:else}
                    {m.tickets_analytics_none_late()}
                  {/if}
                </span>
              </div>
            </div>
          {/each}
        </div>

        <!-- Mix -->
        <div class="v2-card" style="padding:16px 18px">
          <div class="v2-label" style="margin-bottom:4px">{m.tickets_analytics_mix_title()}</div>
          <p class="v2-sub" style="font-size:11.5px;margin:0 0 14px">
            {m.tickets_analytics_mix_body()}
          </p>
          {#each data.byType as t (t.case_type)}
            {@const share = Math.round(
              (t.count / data.byType.reduce((a, x) => a + x.count, 0)) * 100
            )}
            <div style="margin-bottom:13px">
              <div style="display:flex;align-items:baseline;font-size:12.5px;margin-bottom:5px">
                <span>{CASE_TYPE_LABEL[t.case_type] ?? t.case_type}</span>
                <span class="v2-sub v2-num" style="margin-left:auto;font-size:12px">
                  {t.count} · {share}%
                </span>
              </div>
              <div class="v2-bar"><i style="width:{share}%"></i></div>
            </div>
          {/each}

          {#if isOn(data.modules, 'knowledge_base') && data.byType.find((t) => t.case_type === 'Question')}
            <p class="v2-sub" style="font-size:11.5px;margin:16px 0 0">
              <a href={resolve('solutions')} style="color:inherit">
                {m.tickets_analytics_questions_link({
                  count: data.byType.find((t) => t.case_type === 'Question').count
                })}
              </a>. {m.tickets_analytics_questions_tail()}
            </p>
          {/if}
        </div>
      </div>

      <div class="v2-split" style="margin-bottom:18px">
        <!-- Next response. Built like the first-response card above, scored the
             same way: per priority, against that priority's own target. -->
        <div class="v2-card" style="padding:16px 18px">
          <div class="v2-label" style="margin-bottom:4px">{m.tickets_analytics_next_title()}</div>
          <p class="v2-sub" style="font-size:11.5px;margin:0 0 14px">
            {m.tickets_analytics_next_body()}
            <a href={resolve('settings/escalation')} style="color:inherit"
              >{m.tickets_analytics_next_link()}</a
            >. {m.tickets_analytics_next_tail()}
          </p>
          {#each data.nextResponse as r (r.priority)}
            {@const pct = attainment(r)}
            <div style="margin-bottom:14px">
              <div
                style="display:flex;align-items:baseline;gap:8px;font-size:12.5px;margin-bottom:5px"
              >
                <b style="font-weight:600">{CASE_PRIORITY_LABEL[r.priority] ?? r.priority}</b>
                <span class="v2-sub" style="font-size:11.5px">
                  {m.tickets_analytics_target_median({
                    target: duration(minutesOf(r.target_hours)),
                    median: duration(minutesOf(r.median_hours))
                  })}
                </span>
                <span
                  class="v2-num"
                  style="margin-left:auto;font-weight:650;color:{pct == null
                    ? 'var(--v2-slate)'
                    : barColor(pct)}"
                >
                  {pct == null ? '—' : `${pct}%`}
                </span>
              </div>
              <div class="v2-bar">
                <i style="width:{pct ?? 0}%;background:{barColor(pct)}"></i>
              </div>
              <div class="v2-bar-legend">
                <span><span class="v2-num">{r.met}</span> {m.tickets_analytics_in_time()}</span>
                <span>
                  {#if r.missed}
                    <span class="v2-num" style="color:var(--v2-rust)">{r.missed}</span>
                    {m.tickets_analytics_late()}
                  {:else}
                    {m.tickets_analytics_none_late()}
                  {/if}
                </span>
              </div>
            </div>
          {/each}
        </div>

        <!-- Satisfaction -->
        <div class="v2-card" style="padding:16px 18px">
          <div class="v2-label" style="margin-bottom:4px">{m.tickets_analytics_csat_title()}</div>
          {#if data.csat.count === 0}
            <p class="v2-sub" style="font-size:11.5px;margin:0">
              {m.tickets_analytics_csat_empty()}
              <a href={resolve('settings/organization')} style="color:inherit"
                >{m.tickets_analytics_csat_empty_link()}</a
              >.
            </p>
          {:else}
            <p class="v2-sub" style="font-size:11.5px;margin:0 0 10px">
              {m.tickets_analytics_csat_body()}
            </p>
            <div style="display:flex;align-items:baseline;gap:8px;margin-bottom:14px">
              <span class="v2-stat-value" style="margin:0">
                {data.csat.average == null ? '—' : data.csat.average.toFixed(1)}
              </span>
              <span class="v2-sub" style="font-size:12px">
                {m.tickets_analytics_csat_average_from()}
                <span class="v2-num">{count(data.csat.count)}</span>
                {m.tickets_analytics_csat_ratings({ count: data.csat.count })}
              </span>
            </div>
            {#each RATINGS as rating (rating)}
              {@const n = data.csat.distribution[rating] ?? 0}
              <div style="margin-bottom:11px">
                <div style="display:flex;align-items:baseline;font-size:12.5px;margin-bottom:5px">
                  <span>{m.tickets_analytics_rating_of_5({ rating })}</span>
                  <span class="v2-sub v2-num" style="margin-left:auto;font-size:12px">
                    {n} · {ratingShare(n)}%
                  </span>
                </div>
                <div class="v2-bar"><i style="width:{ratingShare(n)}%"></i></div>
              </div>
            {/each}
          {/if}
        </div>
      </div>

      <!-- Per agent -->
      <div class="v2-label" style="margin-bottom:10px">{m.tickets_analytics_agents_title()}</div>
      <div class="v2-table-wrap">
        <table class="v2-table">
          <thead>
            <tr>
              <th>{m.tickets_analytics_col_agent()}</th>
              <th class="v2-r">{m.tickets_analytics_col_open_now()}</th>
              <th class="v2-r">{m.tickets_analytics_col_closed_week()}</th>
              <th class="v2-r">{m.tickets_analytics_col_median_first()}</th>
              <th class="v2-r">{m.tickets_analytics_col_missed()}</th>
            </tr>
          </thead>
          <tbody>
            {#each data.byAgent as a (a.id ?? a.name)}
              <tr>
                <td>
                  <span style="display:flex;gap:8px;align-items:center">
                    {#if a.id}
                      <Avatar name={a.name} size={24} />
                    {:else}
                      <!-- Unassigned is not a person and does not get a face. -->
                      <span
                        style="width:24px;height:24px;border-radius:50%;border:1px dashed var(--v2-line);flex:none"
                      ></span>
                    {/if}
                    <span class="v2-table-primary">{a.name}</span>
                  </span>
                </td>
                <td class="v2-r v2-num">{a.open}</td>
                <td class="v2-r v2-num">{a.closed_this_week}</td>
                <td class="v2-r v2-num">{duration(a.median_first_response_minutes)}</td>
                <td
                  class="v2-r v2-num"
                  style={a.breached ? 'color:var(--v2-rust);font-weight:600' : ''}
                >
                  {a.breached || '—'}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>

      <!--
      The clock these figures are measured on. Without it "answered in 4h" is
      ambiguous: a ticket opened at 17:20 on Friday and answered at 09:10 on
      Monday is either fifteen hours late or fifty minutes early, and only the
      calendar says which.
    -->
      <div style="display:flex;gap:9px;align-items:flex-start;margin-top:16px">
        <Clock size={15} style="color:var(--v2-slate);flex:none;margin-top:2px" />
        <p class="v2-sub" style="font-size:12px;margin:0">
          {#if totals.business_hours_applied}
            {m.tickets_analytics_clock_business({ calendar: totals.calendar_name })}
            <a href={resolve('settings/business-hours')} style="color:inherit"
              >{m.tickets_analytics_clock_change()}</a
            >.
          {:else}
            {m.tickets_analytics_clock_none()}
            <a href={resolve('settings/business-hours')} style="color:inherit"
              >{m.tickets_analytics_clock_setup()}</a
            >.
          {/if}
        </p>
      </div>
    </div>
  </div>
{/if}
