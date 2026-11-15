<script>
  import { SvelteDate } from 'svelte/reactivity';
  import { resolve } from '$app/paths';
  /**
   * A week of logged time, one column per day, including the days with
   * nothing on them, because an unlogged Wednesday is the thing this page
   * exists to make visible. v1 rendered only the days that had entries, so a
   * gap and a quiet day looked identical.
   *
   * The running timer ticks locally from the server's live_duration_minutes.
   * The browser clock is a rendering detail, not a source of truth about how
   * long somebody has been working, so the number starts from the server's
   * and only the seconds since page load are added on top.
   */
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import { money, count, shortDate, hoursMinutes as hm } from '#lib/v2/format.js';
  import { todayIn } from '#lib/v2/dates.js';
  import { isBilled } from '#lib/v2/time-entry.js';
  import { ChevronLeft, ChevronRight, Square, Receipt } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();

  let week = $derived(data.week);

  // Disables every "Stop timer" button while a stop is in flight. Without
  // this, a double-click fires two POSTs; the first stops the timer and the
  // second gets a 400 "Timer is already stopped." back, so a successful stop
  // reads as a failure.
  let busy = $state(false);
  const stopping = () => {
    busy = true;
    return async (/** @type {any} */ { update }) => {
      await update();
      busy = false;
    };
  };

  /** Minutes elapsed since this page loaded, added to the server's figure. */
  let sinceLoad = $state(0);
  onMount(() => {
    const started = Date.now();
    const id = setInterval(() => {
      sinceLoad = Math.floor((Date.now() - started) / 60000);
    }, 30000);
    return () => clearInterval(id);
  });

  const liveMinutes = (e) =>
    e.is_running ? e.live_duration_minutes + sinceLoad : e.duration_minutes;

  const WEEKDAY = [
    m.timesheet_weekday_mon,
    m.timesheet_weekday_tue,
    m.timesheet_weekday_wed,
    m.timesheet_weekday_thu,
    m.timesheet_weekday_fri,
    m.timesheet_weekday_sat,
    m.timesheet_weekday_sun
  ];
  // The org's day, so the column marked today is the one the API files today's entries under.
  let todayISO = $derived(todayIn(data.org.timezone));

  /** Jump `deltaDays` from the current week's Mon..Sun and reload. */
  function shiftWeek(/** @type {number} */ deltaDays) {
    const s = new SvelteDate(`${week.start}T00:00:00Z`);
    const e = new SvelteDate(`${week.end}T00:00:00Z`);
    s.setUTCDate(s.getUTCDate() + deltaDays);
    e.setUTCDate(e.getUTCDate() + deltaDays);
    const qs = new URLSearchParams({
      start: s.toISOString().slice(0, 10),
      end: e.toISOString().slice(0, 10)
    });
    goto(resolve(`timesheet?${qs.toString()}`), { reset: false });
  }

  /** Back to the current ISO week (no params → server default). */
  function thisWeek() {
    goto(resolve('timesheet'), { reset: false });
  }

  let dayMinutes = $derived(
    week.days.map((d) => d.entries.reduce((a, e) => a + liveMinutes(e), 0))
  );
  let weekMinutes = $derived(dayMinutes.reduce((a, n) => a + n, 0));
  let billableMinutes = $derived(
    week.days.reduce(
      (a, d) => a + d.entries.filter((e) => e.billable).reduce((x, e) => x + liveMinutes(e), 0),
      0
    )
  );

  /**
   * Billable value at the rate snapshotted on each entry, not at today's rate.
   * hourly_rate is stored per entry precisely so a rate change next month does
   * not silently rewrite what last month was worth.
   */
  let billableValue = $derived(
    week.days.reduce(
      (a, d) =>
        a +
        d.entries
          .filter((e) => e.billable && e.hourly_rate)
          .reduce((x, e) => x + (liveMinutes(e) / 60) * e.hourly_rate, 0),
      0
    )
  );

  let unbilled = $derived(
    week.days.reduce((a, d) => a + d.entries.filter((e) => e.billable && !isBilled(e)).length, 0)
  );
</script>

<PageHeader title={m.timesheet_title()}>
  {#snippet sub()}
    {shortDate(week.start)} - {shortDate(week.end)} · {week.profile.name}
  {/snippet}
  {#snippet actions()}
    <button class="v2-btn" aria-label={m.timesheet_prev_week()} onclick={() => shiftWeek(-7)}>
      <ChevronLeft />
    </button>
    <button class="v2-btn" onclick={thisWeek}>{m.timesheet_this_week()}</button>
    <button class="v2-btn" aria-label={m.timesheet_next_week()} onclick={() => shiftWeek(7)}>
      <ChevronRight />
    </button>
    <!-- This page is one person's week. The report is every window and every
         grouping of the same entries, and where the CSV comes from. -->
    <a class="v2-btn" href={resolve('timesheet/report')}>{m.timesheet_report_link()}</a>
  {/snippet}
</PageHeader>

<div class="v2-pad" style="padding-top:16px;flex:none">
  <div class="v2-stats">
    <StatCard label={m.timesheet_stat_logged_week()} value={hm(weekMinutes)} tone="ink" />
    <StatCard
      label={m.timesheet_stat_billable()}
      value={hm(billableMinutes)}
      tone="moss"
      detail={m.timesheet_stat_billable_share({
        percent: Math.round((billableMinutes / Math.max(1, weekMinutes)) * 100)
      })}
    />
    <StatCard
      label={m.timesheet_stat_billable_value()}
      value={money(billableValue, data.org.currency)}
      tone="slate"
      detail={m.timesheet_stat_rate_note()}
    />
    <StatCard
      label={m.timesheet_stat_unbilled()}
      value={count(unbilled)}
      tone={unbilled ? 'clay' : 'slate'}
      detail={unbilled ? m.timesheet_stat_unbilled_some() : m.timesheet_stat_unbilled_none()}
    />
  </div>
</div>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-bottom:32px">
    {#if week.running_count}
      <!-- The one thing on this page that changes while you look at it. -->
      <div class="v2-next" style="margin-bottom:16px">
        <div class="v2-next-body">
          <div class="v2-label" style="color:var(--v2-ember)">
            {m.timesheet_timers_running({ count: week.running_count })}
          </div>
          {#if form?.error}
            <!-- Stop can fail (ownership check, network). Silent failure here
                 would repeat the exact bug this page exists to fix: a timer
                 that keeps accruing time with nothing on screen saying so. -->
            <p class="v2-error">{form.error}</p>
          {/if}
          <div class="v2-next-text">
            {#each week.days as d (d.date)}
              {#each d.entries.filter((e) => e.is_running) as e (e.id)}
                <div class="v2-running-row">
                  <span>
                    {#each messageParts(m.timesheet_running_on( { duration: slot('duration'), ticket: slot('ticket') } )) as p, i (i)}{#if p.key === 'duration'}<span
                          class="v2-num">{hm(liveMinutes(e))}</span
                        >{:else if p.key === 'ticket'}<a
                          href={resolve(`tickets/${e.case.id}`)}
                          style="color:inherit">{e.case.name}</a
                        >{:else}{p.text}{/if}{/each}
                  </span>
                  <!-- One form per entry. A single shared button could not say
                       which of several running timers it meant. -->
                  <form method="POST" action="?/stop" use:enhance={stopping}>
                    <input type="hidden" name="entry_id" value={e.id} />
                    <button class="v2-btn v2-btn-primary" type="submit" disabled={busy}>
                      <Square size={13} />{m.timesheet_stop_timer()}
                    </button>
                  </form>
                </div>
              {/each}
            {/each}
          </div>
        </div>
      </div>
    {/if}

    <div class="v2-week">
      {#each week.days as d, i (d.date)}
        <div class="v2-day" data-today={d.date === todayISO} data-empty={d.entries.length === 0}>
          <div class="v2-day-head">
            <div>
              <div style="font-size:11.5px;font-weight:650">{WEEKDAY[i]()}</div>
              <div class="v2-sub" style="font-size:11px">{shortDate(d.date)}</div>
            </div>
            {#if dayMinutes[i]}
              <span class="v2-num" style="font-size:12px;font-weight:600">{hm(dayMinutes[i])}</span>
            {/if}
          </div>

          {#each d.entries as e (e.id)}
            <div class="v2-entry">
              <div style="display:flex;gap:6px;align-items:baseline">
                <span class="v2-num" style="font-weight:600;font-size:11.5px">
                  {hm(liveMinutes(e))}
                </span>
                {#if e.is_running}
                  <Pill tone="clay" dot>{m.timesheet_entry_running()}</Pill>
                {:else if !e.billable}
                  <span class="v2-sub" style="font-size:10.5px">{m.timesheet_entry_internal()}</span
                  >
                {:else if isBilled(e)}
                  <!-- Already billed. Links out rather than offering to bill
                       it again. Double-billing an hour is a refund, not an
                       edge case. -->
                  {#if e.invoice}
                    <a
                      href={resolve(`invoices/${e.invoice.id}`)}
                      class="v2-sub"
                      style="font-size:10.5px;display:inline-flex;gap:3px;align-items:center;color:var(--v2-moss)"
                      title={m.timesheet_entry_billed_on({ number: e.invoice.invoice_number })}
                    >
                      <Receipt size={10} />{m.timesheet_entry_billed_number({
                        number: e.invoice.invoice_number
                      })}
                    </a>
                  {:else}
                    <span
                      class="v2-sub"
                      style="font-size:10.5px;display:inline-flex;gap:3px;align-items:center;color:var(--v2-moss)"
                    >
                      <Receipt size={10} />{m.timesheet_entry_billed()}
                    </span>
                  {/if}
                {/if}
              </div>
              <a
                href={resolve(`tickets/${e.case.id}`)}
                style="color:inherit;text-decoration:none;display:block;margin-top:3px;white-space:normal;line-height:1.35"
              >
                {e.case.name}
              </a>
              {#if e.description}
                <div class="v2-sub" style="font-size:11px;margin-top:3px;white-space:normal">
                  {e.description}
                </div>
              {/if}
            </div>
          {:else}
            <div style="flex:1;display:grid;place-items:center;padding:12px">
              <span class="v2-sub" style="font-size:11px">{m.timesheet_day_empty()}</span>
            </div>
          {/each}
        </div>
      {/each}
    </div>

    <p class="v2-sub" style="font-size:11.5px;margin-top:14px">
      {m.timesheet_footer_note()}
    </p>
  </div>
</div>

<style>
  .v2-running-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }
</style>
