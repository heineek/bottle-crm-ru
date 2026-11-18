<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * Documents: a model with a full API and, until now, no screen anywhere.
   * `Document` has existed since the first migration and neither v1 nor the
   * Flutter client ever rendered one, so three defects in
   * `/api/documents/` went unnoticed for its whole life: the list crashed for
   * non-admins, uploading a file did not let you open it, and sharing with a
   * team granted nobody anything. All three are fixed;
   * `common/tests/test_documents_access.py` covers them in both directions,
   * and the page is drawn against the corrected rules.
   *
   * The column that matters here is **who can open it**. On every other v2
   * list the interesting fact is the work; on this one it is the audience,
   * because a document nobody has been given is a document that does not
   * exist as far as the rest of the team is concerned. So the share is a
   * column, not a detail-page field.
   *
   * Deletion is deliberately narrower than reading, on both sides: a share
   * hands someone a copy to work with, not the right to remove it from
   * everyone else. The row only offers Delete where the server would allow
   * it, rather than offering it to everyone and failing on press.
   */
  import { page } from '$app/state';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import FilterBar from '#lib/v2/components/FilterBar.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { count, relativeDays } from '#lib/v2/format.js';
  import { intlLocale } from '#lib/i18n/locale.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { getLocale } from '#lib/paraglide/runtime.js';
  import { FileText, FileSpreadsheet, File, Users, Upload, Lock, Pencil } from '@lucide/svelte';
  import type { PageProps } from './$types';

  let { data }: PageProps = $props();

  let documents = $derived(data.results);
  let totals = $derived(data.totals);
  // Uploading is open to any org member (the server checks only auth + org), so
  // the Upload button shows for everyone. Editing/deleting are the narrow writes
  //. Those are gated per row by `can_write` (creator or admin) below.

  const ICON: Record<string, typeof File> = {
    pdf: FileText,
    sheet: FileSpreadsheet,
    text: FileText
  };
  const iconFor = (kind: string) => ICON[kind] ?? File;

  /** kB and MB, never bytes. Nobody reads a file size in bytes. A missing file
      has no size the server could read, so it shows an em dash, not "0 kB". */
  function fileSize(bytes: number | null) {
    if (bytes == null) return '—';
    const number = (n: number, digits: number) =>
      new Intl.NumberFormat(intlLocale(getLocale(), 'number'), {
        minimumFractionDigits: digits,
        maximumFractionDigits: digits,
        useGrouping: false
      }).format(n);
    if (bytes >= 1_000_000) return m.documents_size_mb({ size: number(bytes / 1_000_000, 1) });
    return m.documents_size_kb({ size: number(Math.round(bytes / 1000), 0) });
  }

  /**
   * Who can open a document, in the same terms the server uses: the creator,
   * anyone in `shared_to`, anyone in a team it is shared with, plus admins.
   *
   * Names rather than a count while there are few enough to read; "Marcus
   * and Ken" is checkable at a glance and "2 people" is not. Teams are named
   * separately below because "the Support team" is the thing that was chosen,
   * and flattening it to three names loses the reason.
   */
  function reachLabel(d: { shared_to: { name: string }[]; teams: unknown[] }) {
    const names = d.shared_to.map((p) => p.name.split(' ')[0]);
    if (!names.length) return d.teams.length ? '' : m.documents_reach_nobody();
    if (names.length === 1) return names[0];
    if (names.length === 2) return m.documents_reach_two({ first: names[0], second: names[1] });
    return m.documents_reach_many({ first: names[0], second: names[1], rest: names.length - 2 });
  }
</script>

<PageHeader title={m.documents_list_title()}>
  {#snippet sub()}
    {#each messageParts(m.documents_list_sub( { active: slot('active'), archived: slot('archived') } )) as p, i (i)}{#if p.key === 'active'}<span
          class="v2-num">{count(totals.active)}</span
        >{:else if p.key === 'archived'}<span class="v2-num">{count(totals.inactive)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    <a class="v2-btn v2-btn-primary" href={resolve('documents/new')}
      ><Upload />{m.documents_list_upload()}</a
    >
  {/snippet}
</PageHeader>

{#if page.url.search}
  <p class="v2-sub" style="font-size:11.5px;margin:8px 0 0">
    {m.documents_list_filtered_note()}
  </p>
{/if}

<div class="v2-pad" style="padding-top:14px;flex:none">
  <div class="v2-stats">
    <StatCard
      label={m.documents_stat_unshared()}
      value={count(totals.unshared)}
      tone={totals.unshared ? 'clay' : 'slate'}
      detail={m.documents_stat_unshared_detail()}
    />
    <StatCard label={m.documents_stat_active()} value={count(totals.active)} tone="ink" />
    <StatCard label={m.documents_stat_archived()} value={count(totals.inactive)} tone="slate" />
    <StatCard label={m.documents_stat_total()} value={count(totals.count)} tone="slate" />
  </div>
</div>

<FilterBar page="documents" url={page.url} meta={m.documents_list_meta()} />

<div class="v2-scroll">
  {#if documents.length === 0}
    <EmptyState title={m.documents_empty_title()} body={m.documents_empty_body()}>
      {#snippet icon()}<FileText size={21} />{/snippet}
      {#snippet actions()}
        <a class="v2-btn v2-btn-primary" href={resolve('documents/new')}
          >{m.documents_empty_action()}</a
        >
      {/snippet}
    </EmptyState>
  {:else}
    <div class="v2-table-wrap">
      <table class="v2-table">
        <thead>
          <tr>
            <th>{m.documents_col_document()}</th>
            <th>{m.documents_col_reach()}</th>
            <th>{m.documents_col_uploaded_by()}</th>
            <th class="v2-r">{m.documents_col_size()}</th>
            <th class="v2-r">{m.documents_col_added()}</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {#each documents as d (d.id)}
            {@const Icon = iconFor(d.file_kind)}
            <tr class:archived={d.status === 'inactive'}>
              <td style="white-space:normal;max-width:420px">
                <span class="doc">
                  <Icon size={14} style="color:var(--v2-slate);flex:none" />
                  <span>
                    <!-- Still not a media URL: `download_href` is a route on
                         this origin that streams the file from an endpoint
                         gated by the same read predicate as the record. A
                         `/media/` link would be readable by every tenant and
                         would 403 for the person entitled to it. -->
                    {#if d.download_href}
                      <a class="v2-table-primary title" href={d.download_href} download>
                        {d.title}
                      </a>
                    {:else}
                      <span class="v2-table-primary">{d.title}</span>
                    {/if}
                    <span class="v2-table-secondary path">{d.document_file}</span>
                  </span>
                </span>
              </td>

              <td style="white-space:normal;max-width:280px">
                {#if reachLabel(d)}
                  <span class="reach" class:narrow={!d.shared_to.length && !d.teams.length}>
                    {#if !d.shared_to.length && !d.teams.length}<Lock size={11} />{/if}
                    {reachLabel(d)}
                  </span>
                {/if}

                <!-- Named as the team, not flattened into its members: the
                     team is what somebody chose, and it keeps being right as
                     people join and leave it. -->
                {#if d.teams.length}
                  <span class="team-share">
                    <Users size={11} />
                    {d.teams
                      .map(
                        (t: { name: string; member_count: number }) =>
                          `${t.name} (${t.member_count})`
                      )
                      .join(', ')}
                  </span>
                {/if}
              </td>

              <td>{d.created_by.name}</td>

              <td class="v2-r v2-num v2-muted">{fileSize(d.size_bytes)}</td>
              <td class="v2-r v2-muted">{relativeDays(d.created_at)}</td>

              <!-- Edit is offered only where the server would allow the write,
                   the uploader or an admin, so the row never presents an action
                   that would 403. Managing shares and deleting both live behind
                   it. Reading is broader, but that is what the row already is. -->
              <td class="v2-r">
                {#if d.can_write}
                  <a
                    class="edit"
                    href={resolve(`documents/${d.id}/edit`)}
                    title={m.documents_row_manage()}
                  >
                    <Pencil size={13} />
                  </a>
                {/if}
              </td>
            </tr>
          {/each}
        </tbody>
      </table>
    </div>

    <p class="v2-sub v2-pad" style="font-size:12px;padding-bottom:24px">
      {#each messageParts(m.documents_list_showing( { shown: slot('shown'), total: slot('total') } )) as p, i (i)}{#if p.key === 'shown'}<span
            class="v2-num">{documents.length}</span
          >{:else if p.key === 'total'}<span class="v2-num">{count(totals.count)}</span
          >{:else}{p.text}{/if}{/each}
    </p>
  {/if}
</div>

<style>
  .doc {
    display: flex;
    gap: 8px;
    align-items: flex-start;
  }
  .path {
    font-family: var(--v2-mono);
    font-size: 11px;
  }

  /* A block so the whole title line is the tap target on a phone, where the
     row is a card and there is no second column to aim at. */
  a.title {
    display: block;
    color: inherit;
    text-decoration: none;
  }

  a.title:hover {
    text-decoration: underline;
  }

  .reach {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    font-size: 12.5px;
  }
  .reach.narrow {
    color: var(--v2-clay);
  }

  .team-share {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-top: 3px;
    font-size: 11.5px;
    color: var(--v2-slate);
  }

  /* Archived rows stay legible. Dimming them to near-invisible is how people
     stop believing the archive contains anything. */
  .archived .v2-table-primary {
    color: var(--v2-slate);
  }

  .edit {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    color: var(--v2-slate);
  }
  .edit:hover {
    color: var(--v2-ink);
  }
</style>
