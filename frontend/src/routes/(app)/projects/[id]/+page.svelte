<script lang="ts">
  import { resolve } from '$app/paths';
  import { enhance, type SubmitFunction } from '$app/forms';
  import { invalidateAll } from '$app/navigation';
  import { onMount, untrack } from 'svelte';
  import { asInternalPath } from '#lib/utils/paths.js';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import Avatar from '#lib/v2/components/Avatar.svelte';
  import Timeline from '#lib/v2/components/Timeline.svelte';
  import CustomFieldsCard from '#lib/v2/components/CustomFieldsCard.svelte';
  import CommentComposer from '#lib/v2/components/CommentComposer.svelte';
  import FileList from '#lib/v2/components/FileList.svelte';
  import { money, longDate, shortDate, shortAge, hoursMinutes as hm } from '#lib/v2/format.js';
  import {
    INVOICE_STATUS_TONE,
    TASK_STATUS,
    TASK_STATUS_LABEL,
    TASK_STATUS_TONE,
    invoiceStatusLabel
  } from '#lib/v2/enums.js';
  import {
    BILL_GROUPINGS,
    BILLING_TYPE_LABEL,
    PROJECT_STATUS_LABEL,
    PROJECT_STATUS_TONE,
    billActionUrl,
    burnMeter,
    defaultBillable,
    hoursText,
    monthLabel,
    retainerPanel,
    unratedText
  } from '#lib/v2/projects.js';
  import { isOrgAdmin } from '#lib/admin.js';
  import { isBilled } from '#lib/v2/time-entry.js';
  import { ChevronRight, Play, Plus, Square, Trash2 } from '@lucide/svelte';
  import type { components } from '#lib/api-schema.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  let project = $derived(data.project);
  let burn = $derived(project.burn);
  let hoursMeter = $derived(burnMeter(burn.hours_percent));
  let amountMeter = $derived(burnMeter(burn.amount_percent));
  let isFixedFee = $derived(project.billing_type === 'fixed_fee');
  let billable = $derived(defaultBillable(project.billing_type));
  let isAdmin = $derived(isOrgAdmin(data));
  let retainer = $derived(
    project.billing_type === 'retainer'
      ? retainerPanel({ ...project, usage: data.retainerUsage })
      : null
  );
  let retainerMonth = $derived(monthLabel(data.retainerUsage?.month));
  /* A refused bill (already billed, ended) means the page is out of date. */
  $effect(() => {
    if (form?.retainerError) void invalidateAll();
  });
  /** Rates kept for someone no longer on the project, listed after the team. */
  let offTeamRates = $derived(
    project.rates.filter((r) => !project.assigned_to.some((p) => p.id === r.profile.id))
  );

  const TABS: { key: string; label: string; on: 'tasks' | 'timesheet' | 'invoices' | null }[] = [
    { key: 'overview', label: m.projects_tab_overview(), on: null },
    { key: 'tasks', label: m.projects_tab_tasks(), on: 'tasks' },
    { key: 'time', label: m.projects_tab_time(), on: 'timesheet' },
    { key: 'invoices', label: m.projects_tab_invoices(), on: 'invoices' },
    { key: 'files', label: m.projects_tab_files(), on: null },
    { key: 'comments', label: m.projects_tab_comments(), on: null }
  ];
  let tabs = $derived(TABS.filter((t) => !t.on || data.on[t.on]));

  /* A link to a tab works without JavaScript (the page reloads on it); with
     it, the tab switches in place. A refused write reopens its own tab. */
  let tab = $state(
    untrack(() => {
      if (form?.timeError) return 'time';
      if (form?.noteError) return 'comments';
      return TABS.some((t) => t.key === data.tab) ? data.tab : 'overview';
    })
  );
  let shown = $derived(tabs.some((t) => t.key === tab) ? tab : 'overview');

  function pick(e: MouseEvent, key: string) {
    e.preventDefault();
    tab = key;
  }

  /* ── time, as on the ticket page ─────────────────────────────────────── */
  let entries = $derived(data.time.entries);
  let sinceLoad = $state(0);
  onMount(() => {
    const opened = Date.now();
    const id = setInterval(() => {
      sinceLoad = Math.floor((Date.now() - opened) / 60000);
    }, 30000);
    return () => clearInterval(id);
  });
  type TimeEntry = components['schemas']['TimeEntry'];
  const runningMinutes = (entry: TimeEntry) =>
    Math.floor((Date.parse(data.time.now) - Date.parse(entry.started_at)) / 60000) + sinceLoad;
  const isMine = (entry: TimeEntry) => entry.profile?.user_details?.id === data.time.viewerUserId;
  let myTimer = $derived((entries ?? []).find((e) => !e.ended_at && isMine(e)));
  let timeBusy = $state(false);
  let confirmDelete = $state('');

  const timeSubmit: SubmitFunction = () => {
    timeBusy = true;
    return async ({ update }) => {
      timeBusy = false;
      await update({ reset: false });
    };
  };

  /** Task titles by id, for the time rows and the log form. */
  let taskTitles = $derived(new Map((data.tasks ?? []).map((t) => [t.id, t.title])));
  let tasksView = $state('list');

  let amountMode = $state('amount');
  let billing = $state(false);
</script>

<PageHeader title={project.name} record>
  {#snippet crumb()}
    <a href={resolve('projects')}>{m.projects_title()}</a>
    {#if project.account.id}
      <ChevronRight size={12} />
      <a href={resolve(`accounts/${project.account.id}`)}>{project.account.name}</a>
    {/if}
  {/snippet}
  {#snippet sub()}
    <Pill tone={PROJECT_STATUS_TONE[project.status] ?? 'slate'}>
      {PROJECT_STATUS_LABEL[project.status] ?? project.status}
    </Pill>
    <span>{BILLING_TYPE_LABEL[project.billing_type] ?? ''}</span>
    {#if project.deal}
      <span
        >· {#each messageParts(m.projects_from_deal({ deal: slot('deal') })) as p, i (i)}{#if p.key === 'deal'}<a
              href={resolve(`pipeline/${project.deal.id}`)}>{project.deal.name}</a
            >{:else}{p.text}{/if}{/each}</span
      >
    {/if}
    {#if project.estimate}
      <span
        >· {#each messageParts(m.projects_from_estimate({ number: slot('number') })) as p, i (i)}{#if p.key === 'number'}<span
              class="v2-num">{project.estimate.estimate_number}</span
            >{:else}{p.text}{/if}{/each}</span
      >
    {/if}
  {/snippet}
  {#snippet actions()}
    {#if data.canEdit}
      <a class="v2-btn" href={resolve(`projects/${project.id}/edit`)}>{m.common_edit()}</a>
    {/if}
    {#if data.offers.billTime}
      <a class="v2-btn" href={resolve(asInternalPath(`/projects/${project.id}?bill=1`))}
        >{m.projects_bill_time()}</a
      >
    {/if}
    {#if data.canDelete}
      <ConfirmAction
        action="?/delete"
        label={m.common_delete()}
        confirmLabel={m.projects_delete_confirm()}
        explain={m.projects_delete_explain({ name: project.name })}
      />
    {/if}
  {/snippet}
</PageHeader>

{#if form?.error}
  <div class="v2-pad" style="padding-top:12px;flex:none">
    <p class="p-error" role="alert">{form.error}</p>
  </div>
{/if}

<nav class="v2-tabs" aria-label={m.projects_sections_label()}>
  {#each tabs as t (t.key)}
    <a
      href={resolve(asInternalPath(`/projects/${project.id}?tab=${t.key}`))}
      aria-current={shown === t.key ? 'page' : undefined}
      onclick={(e) => pick(e, t.key)}
    >
      {t.label}
    </a>
  {/each}
</nav>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:16px;padding-bottom:36px">
    {#if data.bill.open}
      {@const u = data.bill.unbilled}
      <section class="v2-card panel" aria-labelledby="bill-head">
        <div class="panel-head">
          <div class="v2-label" id="bill-head">{m.projects_bill_time()}</div>
          <a class="v2-btn v2-btn-sm" href={resolve(`projects/${project.id}`)}>{m.common_close()}</a>
        </div>
        <form method="GET" class="bill-date">
          <input type="hidden" name="bill" value="1" />
          <label class="v2-field">
            <span class="v2-label">{m.projects_bill_up_to()}</span>
            <input class="v2-input" type="date" name="up_to" value={data.bill.upTo} />
          </label>
          <button class="v2-btn" type="submit">{m.projects_bill_check()}</button>
        </form>
        {#if u === null}
          <p class="v2-sub panel-text">
            {m.projects_bill_preview_failed()}
          </p>
        {:else if u.entry_count === 0}
          <p class="v2-sub panel-text">
            {m.projects_bill_nothing({ date: longDate(data.bill.upTo) })}
          </p>
        {:else}
          <p class="panel-text">
            {#each messageParts(m.projects_bill_summary({ count: u.entry_count, entries: slot('entries'), hours: slot('hours'), value: slot('value'), date: longDate(data.bill.upTo) })) as p, i (i)}{#if p.key === 'entries'}<b
                  class="v2-num">{u.entry_count}</b
                >{:else if p.key === 'hours'}<b class="v2-num">{hoursText(u.hours)}</b
                >{:else if p.key === 'value'}<b class="v2-num"
                  >{money(u.value, u.currency ?? project.currency)}</b
                >{:else}{p.text}{/if}{/each}
          </p>
          {#if unratedText(u.unrated_count)}
            <p class="panel-text unrated">{unratedText(u.unrated_count)}</p>
          {/if}
        {/if}
        <form
          method="POST"
          action={billActionUrl(data.bill.upTo)}
          class="bill-go"
          use:enhance={() => {
            billing = true;
            return async ({ update }) => {
              billing = false;
              await update({ reset: false });
            };
          }}
        >
          <input type="hidden" name="up_to" value={data.bill.upTo} />
          <label class="v2-field">
            <span class="v2-label">{m.projects_bill_lines()}</span>
            <select class="v2-input" name="group_by" value="entry">
              {#each BILL_GROUPINGS as g (g.value)}
                <option value={g.value}>{g.label}</option>
              {/each}
            </select>
          </label>
          <button
            class="v2-btn v2-btn-primary"
            type="submit"
            disabled={billing || (u !== null && u.entry_count === 0)}
          >
            {m.projects_create_draft_invoice()}
          </button>
        </form>
        <p class="v2-hint">
          {m.projects_bill_hint()}
        </p>
        {#if form?.billError}
          <p class="v2-error" role="alert">{form.billError}</p>
        {/if}
      </section>
    {/if}

    {#if shown === 'overview'}
      {#if retainer}
        <section class="v2-card panel retainer" aria-labelledby="retainer-head">
          <div class="v2-label" id="retainer-head">{m.projects_billing_retainer()}</div>
          <p class="retainer-fee v2-num">{retainer.fee}</p>
          {#if retainer.usage}<p class="retainer-line">{retainer.usage}</p>{/if}
          {#if retainer.overage}<p class="retainer-line">{retainer.overage}</p>{/if}
          {#if retainer.carried}<p class="retainer-line v2-sub">{retainer.carried}</p>{/if}
          {#if retainer.ended}<p class="retainer-line v2-sub">{retainer.ended}</p>{/if}
          {#if data.offers.billRetainer && retainerMonth}
            <div class="retainer-bill">
              <ConfirmAction
                action="?/billRetainer"
                label={m.projects_bill_month({ month: retainerMonth })}
                confirmLabel={m.projects_bill_month({ month: retainerMonth })}
                hidden={{ month: data.retainerUsage?.month ?? '' }}
                explain={m.projects_bill_month_explain({ month: retainerMonth })}
              />
            </div>
          {/if}
          {#if form?.retainerError}
            <p class="v2-error" role="alert">{form.retainerError}</p>
          {/if}
        </section>
      {/if}

      <div class="v2-stats">
        <StatCard
          label={m.projects_stat_hours_logged()}
          value={hoursText(burn.logged_hours)}
          tone={hoursMeter?.tone ?? 'ink'}
          detail={project.budget_hours !== null
            ? m.projects_percent_of({
                percent: String(burn.hours_percent ?? 0),
                total: hoursText(project.budget_hours)
              })
            : m.projects_no_hours_budget()}
        />
        <StatCard
          label={m.projects_stat_billable_value()}
          value={money(burn.billable_value, project.currency)}
          tone={amountMeter?.tone ?? 'slate'}
          detail={project.budget_amount !== null
            ? m.projects_percent_of({
                percent: String(burn.amount_percent ?? 0),
                total: money(project.budget_amount, project.currency)
              })
            : m.projects_no_budget_amount()}
        />
        <StatCard
          label={m.projects_stat_unbilled()}
          value={money(burn.unbilled_value, project.currency)}
          tone={burn.unbilled_value > 0 ? 'clay' : 'slate'}
          detail={m.projects_stat_unbilled_detail()}
        />
        {#if burn.invoiced_amount !== null}
          <StatCard
            label={m.projects_stat_invoiced()}
            value={money(burn.invoiced_amount, project.currency)}
            tone="slate"
            detail={isFixedFee && project.budget_amount !== null
              ? m.projects_of_fee({ fee: money(project.budget_amount, project.currency) })
              : m.projects_stat_invoiced_detail()}
          />
        {/if}
      </div>

      {#if hoursMeter || amountMeter}
        <div class="meters">
          {#if hoursMeter}
            <div>
              <div class="meter-head">
                <span class="v2-label">{m.projects_hours_budget()}</span>
                <span class="v2-num" style="color:var(--v2-{hoursMeter.tone})"
                  >{hoursMeter.percent}%</span
                >
              </div>
              <div class="v2-bar" role="img" aria-label={m.projects_meter_hours_label({ percent: String(hoursMeter.percent) })}>
                <i style="width:{hoursMeter.width}%;background:var(--v2-{hoursMeter.tone})"></i>
              </div>
              <div class="v2-bar-legend">
                <span>{m.projects_legend_logged({ value: hoursText(burn.logged_hours) })}</span>
                <span>{m.projects_legend_budget({ value: hoursText(project.budget_hours) })}</span>
              </div>
            </div>
          {/if}
          {#if amountMeter}
            <div>
              <div class="meter-head">
                <span class="v2-label"
                  >{isFixedFee ? m.projects_fee() : m.projects_field_budget_amount()}</span
                >
                <span class="v2-num" style="color:var(--v2-{amountMeter.tone})"
                  >{amountMeter.percent}%</span
                >
              </div>
              <div class="v2-bar" role="img" aria-label={m.projects_meter_amount_label({ percent: String(amountMeter.percent) })}>
                <i style="width:{amountMeter.width}%;background:var(--v2-{amountMeter.tone})"></i>
              </div>
              <div class="v2-bar-legend">
                <span
                  >{m.projects_legend_billable({
                    value: money(burn.billable_value, project.currency)
                  })}</span
                >
                <span
                  >{m.projects_legend_budget({
                    value: money(project.budget_amount, project.currency)
                  })}</span
                >
              </div>
            </div>
          {/if}
        </div>
      {/if}

      {#if data.offers.invoiceAmount}
        <details class="v2-card panel" open={Boolean(form?.amountError)}>
          <summary class="v2-btn">{m.projects_invoice_amount()}</summary>
          <form method="POST" action="?/invoiceAmount" class="amount-form" use:enhance>
            <input type="hidden" name="budget_amount" value={project.budget_amount ?? ''} />
            <div class="amount-modes" role="radiogroup" aria-label={m.projects_invoice_mode_label()}>
              <label class="amount-mode">
                <input type="radio" name="mode" value="amount" bind:group={amountMode} />
                {m.projects_mode_amount()}
              </label>
              {#if project.budget_amount !== null}
                <label class="amount-mode">
                  <input type="radio" name="mode" value="percent" bind:group={amountMode} />
                  {m.projects_mode_percent()}
                </label>
              {/if}
            </div>
            <label class="v2-field">
              <span class="v2-label">
                {amountMode === 'percent'
                  ? m.projects_percentage()
                  : m.projects_amount_in({ currency: project.currency })}
              </span>
              <input
                class="v2-input"
                name="value"
                type="number"
                inputmode="decimal"
                min="0.01"
                max={amountMode === 'percent' ? '100' : undefined}
                step="0.01"
                required
              />
            </label>
            <label class="v2-field">
              <span class="v2-label">{m.projects_line_description()}</span>
              <input
                class="v2-input"
                name="description"
                maxlength="255"
                placeholder={m.projects_line_placeholder({ name: project.name })}
              />
            </label>
            <button class="v2-btn v2-btn-primary" type="submit"
              >{m.projects_create_draft_invoice()}</button
            >
            {#if form?.amountError}
              <p class="v2-error" role="alert">{form.amountError}</p>
            {/if}
            <p class="v2-hint">
              {m.projects_invoice_amount_hint({
                currency: project.currency,
                account: project.account.name
              })}
            </p>
          </form>
        </details>
      {/if}

      <div class="overview">
        <div>
          <div class="v2-label section-head">{m.projects_col_project()}</div>
          <dl class="v2-kv">
            <dt>{m.projects_account()}</dt>
            <dd>
              {#if project.account.id}
                <a href={resolve(`accounts/${project.account.id}`)}>{project.account.name}</a>
              {:else}
                {project.account.name}
              {/if}
            </dd>
            {#if project.deal}
              <dt>{m.projects_deal()}</dt>
              <dd><a href={resolve(`pipeline/${project.deal.id}`)}>{project.deal.name}</a></dd>
            {/if}
            <dt>{m.projects_col_billing()}</dt>
            <dd>{BILLING_TYPE_LABEL[project.billing_type] ?? ''}</dd>
            <dt>{m.projects_field_hourly_rate()}</dt>
            <dd class="v2-num">
              {project.hourly_rate !== null
                ? m.projects_per_hour({ amount: money(project.hourly_rate, project.currency) })
                : m.projects_not_set()}
            </dd>
            <dt>{m.projects_field_budget_hours()}</dt>
            <dd>
              {project.budget_hours !== null
                ? hoursText(project.budget_hours)
                : m.projects_not_set()}
            </dd>
            <dt>{isFixedFee ? m.projects_fee() : m.projects_budget()}</dt>
            <dd class="v2-num">
              {project.budget_amount !== null
                ? money(project.budget_amount, project.currency)
                : m.projects_not_set()}
            </dd>
            <dt>{m.projects_start()}</dt>
            <dd>{project.start_date ? longDate(project.start_date) : m.projects_not_set()}</dd>
            <dt>{m.projects_col_due()}</dt>
            <dd>{project.due_date ? longDate(project.due_date) : m.projects_not_set()}</dd>
            {#if project.tags.length}
              <dt>{m.common_tags()}</dt>
              <dd class="tags">
                {#each project.tags as tag (tag)}<Pill>{tag}</Pill>{/each}
              </dd>
            {/if}
          </dl>
          {#if project.description}
            <div class="v2-label section-head">{m.common_description()}</div>
            <p class="description">{project.description}</p>
          {/if}
          {#if data.customFields?.length}
            <CustomFieldsCard fields={data.customFields} />
          {/if}
        </div>

        <div>
          <div class="v2-label section-head">{m.projects_people()}</div>
          {#each project.assigned_to as p (p.id)}
            {@const rate = project.rates.find((r) => r.profile.id === p.id)}
            <div class="person">
              <Avatar name={p.name} size={24} />
              <span class="person-name">{p.name}</span>
              {#if rate && rate.hourly_rate !== null}
                <span class="v2-num v2-sub"
                  >{m.projects_per_hour({ amount: money(rate.hourly_rate, project.currency) })}</span
                >
              {/if}
            </div>
          {:else}
            <p class="v2-sub small">{m.projects_people_empty()}</p>
          {/each}
          {#each offTeamRates as r (r.profile.id)}
            <div class="person">
              <Avatar name={r.profile.name} size={24} />
              <span class="person-name">{r.profile.name}</span>
              <span class="v2-num v2-sub"
                >{m.projects_per_hour({ amount: money(r.hourly_rate, project.currency) })}</span
              >
            </div>
          {/each}
          <p class="v2-hint">
            {m.projects_rates_hint()}
          </p>
        </div>
      </div>
    {:else if shown === 'tasks'}
      <div class="tab-head">
        <span class="v2-sub">
          {data.tasks === null
            ? ''
            : m.projects_task_count({ count: data.tasks.length })}
        </span>
        <div class="seg" role="group" aria-label={m.projects_view_label()}>
          <button
            type="button"
            aria-pressed={tasksView === 'list'}
            onclick={() => (tasksView = 'list')}>{m.projects_view_list()}</button
          >
          <button
            type="button"
            aria-pressed={tasksView === 'board'}
            onclick={() => (tasksView = 'board')}>{m.projects_view_board()}</button
          >
        </div>
        <a
          class="v2-btn v2-btn-primary"
          href={resolve(asInternalPath(`/tasks/new?project=${project.id}`))}
          ><Plus size={13} />{m.projects_new_task()}</a
        >
      </div>
      {#if data.tasks === null}
        <p class="v2-sub small">{m.projects_tasks_failed()}</p>
      {:else if data.tasks.length === 0}
        <p class="v2-sub small">{m.projects_tasks_empty()}</p>
      {:else if tasksView === 'list'}
        <div class="v2-card" style="overflow:hidden">
          <div class="v2-table-wrap">
            <table class="v2-table">
              <thead>
                <tr>
                  <th>{m.projects_task()}</th>
                  <th>{m.common_status()}</th>
                  <th>{m.projects_col_due()}</th>
                  <th>{m.projects_people()}</th>
                  {#if data.on.timesheet && !myTimer}<th class="v2-r">{m.projects_timer()}</th>{/if}
                </tr>
              </thead>
              <tbody>
                {#each data.tasks as t (t.id)}
                  <tr>
                    <td data-m="title">
                      <a class="v2-row-link" href={resolve(`tasks/${t.id}`)}>
                        <span class="v2-table-primary">{t.title}</span>
                      </a>
                    </td>
                    <td data-m="tag"
                      ><Pill tone={TASK_STATUS_TONE[t.status]}
                        >{TASK_STATUS_LABEL[t.status] ?? t.status}</Pill
                      ></td
                    >
                    <td data-m="meta"
                      >{t.due_date ? m.projects_due_on({ date: shortDate(t.due_date) }) : ''}</td
                    >
                    <td data-m="meta" class="v2-sub">{t.assigned_names.join(', ')}</td>
                    {#if data.on.timesheet && !myTimer}
                      <td class="v2-r" data-m="meta">
                        <form method="POST" action="?/startTimer" use:enhance={timeSubmit}>
                          <input type="hidden" name="task" value={t.id} />
                          <input type="hidden" name="billable" value={String(billable)} />
                          <button class="v2-btn v2-btn-sm" disabled={timeBusy}>
                            <Play size={11} />{m.projects_start_timer_short()}
                          </button>
                        </form>
                      </td>
                    {/if}
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </div>
      {:else}
        <div class="lanes">
          {#each TASK_STATUS as status (status)}
            {@const lane = data.tasks.filter((t) => t.status === status)}
            <section class="lane">
              <div class="v2-lane-head">
                <span class="v2-label">{TASK_STATUS_LABEL[status] ?? status}</span>
                <span class="v2-num">{lane.length}</span>
              </div>
              {#each lane as t (t.id)}
                <a class="v2-deal-card" href={resolve(`tasks/${t.id}`)}>
                  <div style="font-weight:600">{t.title}</div>
                  {#if t.due_date}
                    <div class="v2-sub" style="font-size:11.5px">
                      {m.projects_due_on({ date: shortDate(t.due_date) })}
                    </div>
                  {/if}
                </a>
              {:else}
                <p class="v2-sub small">{m.projects_lane_empty()}</p>
              {/each}
            </section>
          {/each}
        </div>
      {/if}
    {:else if shown === 'time'}
      <section class="v2-card panel">
        <div class="time-head">
          <div class="time-title">
            <div class="v2-label">{m.projects_tab_time()}</div>
            <div class="v2-sub small">
              {#each messageParts(m.projects_time_summary({ logged: slot('logged'), billable: hoursText(burn.billable_hours) })) as p, i (i)}{#if p.key === 'logged'}<b
                    class="v2-num">{hoursText(burn.logged_hours)}</b
                  >{:else}{p.text}{/if}{/each} ·
              <a href={resolve(asInternalPath(`/timesheet/report?project=${project.id}`))}
                >{m.projects_who_logged()}</a
              >
            </div>
          </div>
          {#if myTimer}
            <form method="POST" action="?/stopTimer" use:enhance={timeSubmit}>
              <input type="hidden" name="entry_id" value={myTimer.id} />
              <button class="v2-btn v2-btn-primary" disabled={timeBusy}>
                <Square size={12} />{m.projects_stop_timer({
                  time: hm(runningMinutes(myTimer))
                })}
              </button>
            </form>
          {:else if data.canEdit}
            <form method="POST" action="?/startTimer" use:enhance={timeSubmit}>
              <input type="hidden" name="billable" value={String(billable)} />
              <button class="v2-btn" disabled={timeBusy}><Play size={12} />{m.projects_start_timer()}</button
              >
            </form>
          {/if}
          {#if data.canEdit}
            <details class="time-log">
              <summary class="v2-btn"><Plus size={12} />{m.projects_log_time()}</summary>
              <form method="POST" action="?/logTime" use:enhance={timeSubmit} class="time-form">
                <label class="v2-field">
                  <span class="v2-label">{m.projects_minutes()}</span>
                  <input
                    class="v2-input"
                    name="minutes"
                    type="number"
                    inputmode="numeric"
                    min="1"
                    max="1440"
                    step="1"
                    value="30"
                    required
                  />
                </label>
                {#if isAdmin}
                  <label class="v2-field">
                    <span class="v2-label">{m.projects_rate_per_hour()}</span>
                    <input
                      class="v2-input"
                      name="hourly_rate"
                      type="number"
                      inputmode="decimal"
                      min="0"
                      step="0.01"
                      placeholder={m.projects_rate_placeholder()}
                    />
                  </label>
                {/if}
                {#if data.tasks?.length}
                  <label class="v2-field wide">
                    <span class="v2-label">{m.projects_task()}</span>
                    <select class="v2-input" name="task">
                      <option value="">{m.projects_no_task()}</option>
                      {#each data.tasks as t (t.id)}
                        <option value={t.id}>{t.title}</option>
                      {/each}
                    </select>
                  </label>
                {/if}
                <label class="v2-field wide">
                  <span class="v2-label">{m.projects_what_was_done()}</span>
                  <input
                    class="v2-input"
                    name="description"
                    placeholder={m.projects_what_was_done_placeholder()}
                    required
                  />
                </label>
                <div class="wide time-foot">
                  {#if billable}
                    <label class="check">
                      <input type="checkbox" name="billable" checked />
                      {m.projects_billable()}
                    </label>
                  {/if}
                  <button class="v2-btn v2-btn-primary" disabled={timeBusy}
                    >{m.projects_log_time()}</button
                  >
                </div>
                <p class="v2-hint wide">
                  {isAdmin ? m.projects_log_hint_admin() : m.projects_log_hint_member()}
                </p>
              </form>
            </details>
          {/if}
        </div>

        {#if form?.timeError}
          <p class="v2-error" role="alert">
            <span>{form.timeError}</span>
            {#if form.runningProjectId}
              <a href={resolve(`projects/${form.runningProjectId}`)}>{m.projects_open_running_project()}</a
              >
            {:else if form.runningTicketId}
              <a href={resolve(`tickets/${form.runningTicketId}`)}>{m.projects_open_running_ticket()}</a
              >
            {/if}
          </p>
        {/if}

        {#if entries === null}
          <p class="v2-sub small">
            {m.projects_time_failed()}
          </p>
        {:else if entries.length === 0}
          <p class="v2-sub small">
            {m.projects_time_empty()}
          </p>
        {:else}
          <div class="v2-table-wrap" style="margin-top:10px">
            <table class="v2-table">
              <thead>
                <tr>
                  <th>{m.projects_what_was_done()}</th>
                  <th>{m.projects_who()}</th>
                  <th>{m.projects_when()}</th>
                  <th class="v2-r">{m.projects_col_logged()}</th>
                  <th class="v2-r">{m.projects_col_billing()}</th>
                </tr>
              </thead>
              <tbody>
                {#each entries as e (e.id)}
                  <tr>
                    <td data-m="title">
                      {e.description || m.projects_no_description()}
                      {#if !e.ended_at}<span class="running">{m.projects_running()}</span>{/if}
                      {#if e.task && taskTitles.get(e.task)}
                        <span class="v2-sub entry-task">{taskTitles.get(e.task)}</span>
                      {/if}
                    </td>
                    <td data-m="meta">
                      {e.profile?.user_details?.name ||
                        e.profile?.user_details?.email ||
                        m.projects_someone()}
                    </td>
                    <td data-m="meta">{m.projects_ago({ age: shortAge(e.started_at) })}</td>
                    <td class="v2-num v2-r" data-m="tag">
                      {e.ended_at ? hm(e.duration_minutes) : hm(runningMinutes(e))}
                    </td>
                    <td class="v2-r row-actions">
                      {#if !e.ended_at}
                        <form method="POST" action="?/stopTimer" use:enhance={timeSubmit}>
                          <input type="hidden" name="entry_id" value={e.id} />
                          <button class="v2-btn v2-btn-sm" disabled={timeBusy}>
                            <Square size={11} />{m.projects_stop()}
                          </button>
                        </form>
                      {:else if isBilled(e)}
                        {#if e.invoice}
                          <a class="v2-sub" href={resolve(`invoices/${e.invoice}`)}
                            >{m.projects_invoiced()}</a
                          >
                        {:else}
                          <span class="v2-sub">{m.projects_invoiced()}</span>
                        {/if}
                      {:else if confirmDelete === e.id}
                        <form method="POST" action="?/deleteTime" use:enhance={timeSubmit}>
                          <input type="hidden" name="entry_id" value={e.id} />
                          <button class="v2-btn v2-btn-sm danger" disabled={timeBusy}
                            >{m.common_delete()}</button
                          >
                        </form>
                        <button
                          type="button"
                          class="v2-btn v2-btn-sm"
                          onclick={() => (confirmDelete = '')}>{m.projects_keep()}</button
                        >
                      {:else}
                        {#if !billable}
                          <!-- A non-billable project's time stays non-billable. -->
                          <span class="v2-sub">{m.projects_not_billable()}</span>
                        {:else}
                          <form method="POST" action="?/setBillable" use:enhance={timeSubmit}>
                            <input type="hidden" name="entry_id" value={e.id} />
                            <input
                              type="hidden"
                              name="billable"
                              value={e.billable ? 'false' : 'true'}
                            />
                            <button
                              class="v2-btn v2-btn-sm"
                              class:billable={e.billable}
                              disabled={timeBusy}
                              title={e.billable
                                ? m.projects_mark_non_billable()
                                : m.projects_mark_billable()}
                            >
                              {#if e.billable}
                                {e.hourly_rate
                                  ? m.projects_per_hour({ amount: money(e.hourly_rate, e.currency) })
                                  : m.projects_billable()}
                              {:else}
                                {m.projects_not_billable()}
                              {/if}
                            </button>
                          </form>
                        {/if}
                        <button
                          type="button"
                          class="v2-btn v2-btn-sm"
                          aria-label={m.projects_delete_entry()}
                          title={m.projects_delete_entry()}
                          onclick={() => (confirmDelete = e.id)}
                        >
                          <Trash2 size={11} />
                        </button>
                      {/if}
                    </td>
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        {/if}
      </section>
    {:else if shown === 'invoices'}
      {#if project.invoices.length === 0}
        <p class="v2-sub small">
          {m.projects_invoices_empty()}
          {#if data.offers.billTime}{m.projects_invoices_empty_bill()}{/if}
        </p>
      {:else}
        <div class="v2-card" style="overflow:hidden">
          <div class="v2-table-wrap">
            <table class="v2-table">
              <thead>
                <tr>
                  <th>{m.projects_invoice()}</th>
                  <th>{m.common_status()}</th>
                  <th>{m.projects_issued()}</th>
                  <th class="v2-r">{m.projects_total()}</th>
                </tr>
              </thead>
              <tbody>
                {#each project.invoices as inv (inv.id)}
                  <tr>
                    <td data-m="title">
                      <a class="v2-row-link" href={resolve(`invoices/${inv.id}`)}>
                        <span class="v2-table-primary">{inv.invoice_number || m.projects_invoice_draft()}</span>
                      </a>
                    </td>
                    <td data-m="tag">
                      <Pill tone={INVOICE_STATUS_TONE[inv.status] ?? 'slate'}>
                        {invoiceStatusLabel(inv.status)}
                      </Pill>
                    </td>
                    <td data-m="meta">{inv.issue_date ? shortDate(inv.issue_date) : ''}</td>
                    <td class="v2-r v2-num" data-m="meta"
                      >{money(inv.total_amount, inv.currency)}</td
                    >
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </div>
        {#if burn.invoiced_amount !== null}
          <p class="v2-sub small" style="margin-top:10px">
            {isFixedFee && project.budget_amount !== null
              ? m.projects_invoiced_total_of_fee({
                  amount: money(burn.invoiced_amount, project.currency),
                  fee: money(project.budget_amount, project.currency)
                })
              : m.projects_invoiced_total({
                  amount: money(burn.invoiced_amount, project.currency)
                })}
          </p>
        {/if}
      {/if}
    {:else if shown === 'files'}
      <CommentComposer
        error={form?.noteError}
        placeholder={m.projects_file_note_placeholder()}
      />
      <FileList files={data.files} empty={m.projects_files_empty()} />
    {:else if shown === 'comments'}
      <CommentComposer error={form?.noteError} />
      {#if data.comments.length}
        <Timeline events={data.comments} />
      {:else}
        <p class="v2-sub small">{m.projects_comments_empty()}</p>
      {/if}
    {/if}
  </div>
</div>

<style>
  .p-error {
    margin: 0;
    padding: 9px 12px;
    font-size: 12.5px;
    color: var(--v2-clay);
    background: color-mix(in srgb, var(--v2-clay) 8%, transparent);
    border: 1px solid color-mix(in srgb, var(--v2-clay) 25%, transparent);
    border-radius: 7px;
  }
  .small {
    font-size: 12.5px;
    margin: 0;
  }
  .panel {
    margin-bottom: 18px;
    padding: 13px 15px;
  }
  .panel-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .panel-text {
    font-size: 13px;
    margin: 10px 0;
  }
  .retainer-fee {
    margin: 6px 0 2px;
    font-size: 18px;
    font-weight: 600;
  }
  .retainer-line {
    margin: 2px 0;
    font-size: 13px;
    overflow-wrap: anywhere;
  }
  .retainer-bill {
    margin-top: 12px;
  }
  @media (max-width: 768px) {
    .retainer-bill :global(.v2-btn) {
      min-height: 44px;
    }
    .retainer-bill :global(.v2-confirm) {
      width: 100%;
      flex-wrap: wrap;
    }
  }
  .bill-date,
  .bill-go {
    display: flex;
    align-items: flex-end;
    gap: 10px;
    flex-wrap: wrap;
    margin-top: 10px;
  }
  .bill-date .v2-field,
  .bill-go .v2-field {
    margin-bottom: 0;
    flex: 1 1 180px;
  }
  details.panel > summary {
    list-style: none;
    cursor: pointer;
  }
  details.panel > summary::-webkit-details-marker {
    display: none;
  }
  .amount-form {
    margin-top: 12px;
    padding-top: 12px;
    border-top: 1px solid var(--v2-line);
  }
  .amount-modes {
    display: flex;
    gap: 16px;
    flex-wrap: wrap;
    margin-bottom: 12px;
  }
  .amount-mode,
  .check {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12.5px;
    cursor: pointer;
  }
  .meters {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 16px;
    margin-bottom: 20px;
  }
  .meter-head {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    margin-bottom: 6px;
  }
  .overview {
    display: grid;
    grid-template-columns: minmax(0, 3fr) minmax(0, 2fr);
    gap: 24px;
  }
  .section-head {
    margin: 4px 0 10px;
  }
  .description {
    font-size: 13px;
    line-height: 1.6;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
    margin: 0 0 16px;
  }
  .tags {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }
  .person {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 36px;
  }
  .person-name {
    font-size: 13px;
    font-weight: 550;
    min-width: 0;
    overflow-wrap: anywhere;
    margin-right: auto;
  }
  .tab-head {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
    margin-bottom: 12px;
  }
  .tab-head > .v2-sub {
    margin-right: auto;
    font-size: 12.5px;
  }
  .seg {
    display: flex;
    border: 1px solid var(--v2-line);
    border-radius: 7px;
    overflow: hidden;
  }
  .seg button {
    padding: 5px 11px;
    font: inherit;
    font-size: 12px;
    color: var(--v2-slate);
    background: var(--v2-card);
    border: 0;
    cursor: pointer;
  }
  .seg button + button {
    border-left: 1px solid var(--v2-line);
  }
  .seg button[aria-pressed='true'] {
    color: var(--v2-ink);
    font-weight: 600;
    background: var(--v2-hover);
  }
  .lanes {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 12px;
  }
  .time-head {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    flex-wrap: wrap;
  }
  .time-title {
    margin-right: auto;
  }
  .time-log > summary {
    list-style: none;
    cursor: pointer;
  }
  .time-log > summary::-webkit-details-marker {
    display: none;
  }
  .time-log[open] {
    flex: 1 0 100%;
  }
  .time-form {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
    margin-top: 12px;
    padding-top: 13px;
    border-top: 1px solid var(--v2-line);
  }
  .time-form .v2-field {
    margin-bottom: 0;
  }
  .wide {
    grid-column: 1 / -1;
  }
  .time-foot {
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
  }
  .running {
    margin-left: 6px;
    font-size: 11px;
    font-weight: 600;
    color: var(--v2-ember);
  }
  .entry-task {
    display: block;
    font-size: 11.5px;
  }
  .row-actions {
    white-space: nowrap;
  }
  .row-actions form {
    display: inline;
  }
  .billable {
    color: var(--v2-moss);
  }
  .unrated {
    color: var(--v2-clay);
  }
  .danger {
    color: var(--v2-rust);
  }
  @media (max-width: 768px) {
    .overview,
    .lanes,
    .time-form {
      grid-template-columns: 1fr;
    }
    .panel .v2-btn,
    .tab-head .v2-btn,
    .seg button,
    .row-actions .v2-btn,
    .panel .v2-input {
      min-height: 44px;
    }
    .row-actions {
      white-space: normal;
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
      margin-top: 6px;
    }
  }
</style>
