<script>
  import { resolve } from '$app/paths';
  /**
   * Status and visibility are two separate facts, and the list shows both.
   * An article can be approved and still not suggested on tickets; v1 showed
   * status alone, so those read as live and nobody published them.
   *
   * Publishing does reach a customer. An article that is both approved and
   * published is readable in the portal by any signed-in contact in the org,
   * and is suggested to them while they file a ticket. It also feeds the agent
   * suggester. Unpublishing withdraws both.
   *
   * Now on the real API, which changed one thing about that claim: publishing
   * is admin-only, so for everybody else the approved-and-unpublished row is
   * information rather than a button. It still says so. Knowing a colleague
   * has to release it is worth more than a control that answers 403.
   */
  import { page } from '$app/state';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import FilterBar from '#lib/v2/components/FilterBar.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { count, relativeDays } from '#lib/v2/format.js';
  import { SOLUTION_STATUS_LABEL, SOLUTION_STATUS_TONE } from '#lib/v2/enums.js';
  import { enhance } from '$app/forms';
  import { BookOpen, Eye, EyeOff, Plus } from '@lucide/svelte';
  import { isOn } from '#lib/v2/modules.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();

  let articles = $derived(data.articles);
  let totals = $derived(data.totals);
  // With Tickets off the API empties each article's ticket count.
  let ticketsOn = $derived(isOn(data.modules, 'tickets'));
</script>

<PageHeader title={m.solutions_list_title()}>
  {#snippet sub()}
    <!-- "Live to customers" rather than "published": the flag's own name says
         nothing about who ends up reading it, and this count is the one number
         on the page with a consequence outside the org. Stays grammatical at
         every count. -->
    {#each messageParts(m.solutions_list_sub_articles( { count: totals.count, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
          class="v2-num">{count(totals.count)}</span
        >{:else}{p.text}{/if}{/each} ·
    {#each messageParts(m.solutions_list_sub_live( { count: totals.published, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
          class="v2-num">{count(totals.published)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    <a class="v2-btn v2-btn-primary" href={resolve('solutions/new')}
      ><Plus />{m.solutions_new_article()}</a
    >
  {/snippet}
</PageHeader>

<!-- Unconditional, unlike every other v2 list page's "filtered list" caption:
     `solution_views.py:122-132` counts the five cards over the whole base on
     purpose, never the filtered page, because they partition the knowledge
     base and recomputing them inside `?status=draft` would leave the other
     four reading zero. True whether or not a filter is applied, so it always
     renders. -->
<p class="v2-sub" style="font-size:11.5px;margin:8px 0 0">
  {m.solutions_list_totals_note()}
</p>

<div class="v2-pad" style="padding-top:14px;flex:none">
  <div class="v2-stats">
    <StatCard
      label={m.solutions_stat_approved_unpublished()}
      value={count(totals.approved_unpublished)}
      tone={totals.approved_unpublished ? 'clay' : 'slate'}
      detail={totals.approved_unpublished
        ? data.canRelease
          ? m.solutions_stat_ready()
          : m.solutions_stat_waiting_admin()
        : m.solutions_stat_nothing_waiting()}
    />
    <StatCard label={m.solutions_stat_published()} value={count(totals.published)} tone="moss" />
    <StatCard label={m.solutions_stat_draft()} value={count(totals.draft)} tone="slate" />
    <StatCard label={m.solutions_stat_total()} value={count(totals.count)} tone="ink" />
  </div>
</div>

<FilterBar page="solutions" url={page.url} tags={data.tags} meta={m.solutions_filter_meta()} />

{#if form?.error}
  <p class="v2-pad" style="color:var(--v2-rust);font-size:12.5px;padding-top:10px">{form.error}</p>
{/if}

<div class="v2-scroll">
  {#if articles.length === 0}
    <EmptyState
      title={page.url.search ? m.solutions_empty_filtered_title() : m.solutions_empty_title()}
      body={page.url.search
        ? m.solutions_empty_filtered_body()
        : ticketsOn
          ? m.solutions_empty_body_tickets()
          : m.solutions_empty_body()}
    >
      {#snippet icon()}<BookOpen size={21} />{/snippet}
      {#snippet actions()}
        {#if page.url.search}
          <a class="v2-btn" href={resolve('solutions')}>{m.solutions_clear_filters()}</a>
        {/if}
        <a class="v2-btn v2-btn-primary" href={resolve('solutions/new')}
          >{m.solutions_new_article()}</a
        >
        {#if ticketsOn}
          <a class="v2-btn" href={resolve('tickets')}>{m.solutions_go_to_tickets()}</a>
        {/if}
      {/snippet}
    </EmptyState>
  {:else}
    <div class="v2-table-wrap">
      <table class="v2-table">
        <thead>
          <tr>
            <th>{m.solutions_col_article()}</th>
            <th>{m.solutions_col_status()}</th>
            <th>{m.solutions_col_visibility()}</th>
            {#if ticketsOn}<th class="v2-r">{m.solutions_col_tickets_solved()}</th>{/if}
            <th>{m.solutions_col_author()}</th>
            <th class="v2-r">{m.solutions_col_edited()}</th>
            <th style="width:110px"></th>
          </tr>
        </thead>
        <tbody>
          {#each articles as s (s.id)}
            <tr>
              <td style="white-space:normal;max-width:460px" data-m="title">
                <a class="v2-row-link" href={resolve(`solutions/${s.id}`)}>
                  <span class="v2-table-primary">{s.title}</span>
                </a>
              </td>
              <td data-m="tag">
                <Pill tone={SOLUTION_STATUS_TONE[s.status]}>
                  {SOLUTION_STATUS_LABEL[s.status]}
                </Pill>
              </td>
              <td>
                {#if s.is_published}
                  <span
                    style="display:inline-flex;gap:5px;align-items:center;color:var(--v2-slate);font-size:12.5px"
                  >
                    <Eye size={13} />{m.solutions_live()}
                  </span>
                {:else}
                  <span
                    style="display:inline-flex;gap:5px;align-items:center;font-size:12.5px"
                    style:color={s.awaiting_release ? 'var(--v2-clay)' : 'var(--v2-slate)'}
                  >
                    <EyeOff size={13} />{m.solutions_internal()}
                  </span>
                {/if}
              </td>
              <!-- The unit lives in the header, so the cell stays a bare
                   number and the column reads as a column. -->
              {#if ticketsOn}
                <td class="v2-r v2-num" class:v2-muted={!s.use_count} data-m="meta">
                  {s.use_count || '—'}
                </td>
              {/if}
              <td data-m="hide">{s.author || '—'}</td>
              <td class="v2-r v2-muted" data-m="hide">{relativeDays(s.updated_at)}</td>
              <td>
                <!--
                  Only the rows that are actually ready get the publish
                  control, and only for somebody who may press it. Offering it
                  on a draft would mean a state transition the server has to
                  reject; offering it to a non-admin would mean a 403.
                -->
                {#if s.awaiting_release && data.canRelease}
                  <form method="POST" action="?/publish" use:enhance>
                    <input type="hidden" name="id" value={s.id} />
                    <button class="v2-btn v2-btn-sm" type="submit">{m.solutions_publish()}</button>
                  </form>
                {/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
    <p class="v2-sub v2-pad" style="font-size:12px;padding-bottom:24px">
      {#each messageParts(m.solutions_showing( { shown: slot('shown'), total: slot('total') } )) as p, i (i)}{#if p.key === 'shown'}<span
            class="v2-num">{articles.length}</span
          >{:else if p.key === 'total'}<span class="v2-num">{count(totals.matched)}</span
          >{:else}{p.text}{/if}{/each}
      {#if page.url.search}
        · <a href={resolve('solutions')} style="color:inherit"
          >{m.solutions_clear_filters_lower()}</a
        >
      {/if}
    </p>
  {/if}
</div>
