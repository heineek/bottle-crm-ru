<script>
  /**
   * The security audit log: sign-ins, org switches, refused requests,
   * webhooks paused or turned back on, merges, and API tokens and calendar
   * feeds created or revoked. Read-only.
   *
   * Admins only on the server; a member gets "Admins only" here. Filters are a
   * plain GET form, so they work before any script loads and live in the URL.
   * Tapping a person narrows the log to them (`?actor=`), which is the only
   * way to set that filter: a user id is not something anyone types.
   *
   * Token refreshes (a signed-in app quietly renewing its session) are most of
   * the log, so the API hides them unless "Show token refreshes" is ticked or
   * the Token Refresh event is picked. The toggle is a view option rather than
   * a filter, so it alone does not make the page read as "filtered".
   */
  import { resolve } from '$app/paths';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { count, relativeTime } from '#lib/v2/format.js';
  import { auditActor, auditDetail, auditWebhookId } from '#lib/v2/audit-log.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';

  /** @type {{ data: any }} */
  let { data } = $props();

  /**
   * This page's query string with `changes` applied to the current filters.
   * A changed filter starts again from the first page.
   * @param {Record<string, string | number | null>} changes
   */
  function pageQuery(changes) {
    /** @type {Record<string, string | number | null>} */
    const next = { ...data.filters, offset: data.offset, ...changes };
    if (!('offset' in changes)) next.offset = null;
    return Object.entries(next)
      .filter(([k, v]) => v !== null && v !== undefined && v !== '' && !(k === 'offset' && v === 0))
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
      .join('&');
  }

  let filtered = $derived(
    !data.forbidden &&
      Object.keys(data.filters ?? {}).some((key) => key !== 'include_token_refresh')
  );

  let countParts = $derived(
    messageParts(
      (filtered ? m.settings_audit_count_match : m.settings_audit_count)({
        count: data.count ?? 0,
        shown: slot('shown')
      })
    )
  );
</script>

<PageHeader title={m.settings_audit_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#if !data.forbidden}
      {#each countParts as p, i (i)}{#if p.key}<span class="v2-num">{count(data.count)}</span
          >{:else}{p.text}{/if}{/each}
    {/if}
  {/snippet}
</PageHeader>

{#if data.forbidden}
  <div class="v2-pad" style="padding-top:40px">
    <NextAction label={m.settings_audit_admins_only()} text={m.settings_audit_admins_only_text()} />
  </div>
{:else}
  <div class="v2-scroll">
    <div class="v2-pad" style="padding-top:16px;padding-bottom:32px">
      <form method="GET" class="v2-card al-filters">
        {#if data.filters.actor}
          <input type="hidden" name="actor" value={data.filters.actor} />
        {/if}
        <div class="v2-field">
          <label for="al-type">{m.settings_audit_event()}</label>
          <select id="al-type" name="event_type" class="v2-input al-tap">
            <option value="">{m.settings_audit_all_events()}</option>
            {#each data.eventTypes as t (t.value)}
              <option value={t.value} selected={data.filters.event_type === t.value}>
                {t.label}
              </option>
            {/each}
          </select>
        </div>
        <div class="v2-field">
          <label for="al-from">{m.settings_audit_from()}</label>
          <input
            id="al-from"
            name="from"
            type="date"
            class="v2-input al-tap"
            value={data.filters.from ?? ''}
          />
        </div>
        <div class="v2-field">
          <label for="al-to">{m.settings_audit_to()}</label>
          <input
            id="al-to"
            name="to"
            type="date"
            class="v2-input al-tap"
            value={data.filters.to ?? ''}
          />
        </div>
        <label class="al-toggle al-tap">
          <input
            type="checkbox"
            name="include_token_refresh"
            value="true"
            checked={data.filters.include_token_refresh === 'true'}
          />
          {m.settings_audit_show_refreshes()}
        </label>
        <div class="al-buttons">
          <button class="v2-btn v2-btn-primary al-tap">{m.settings_audit_apply()}</button>
          {#if filtered}
            <a class="v2-btn al-tap" href={resolve('settings/audit-log')}
              >{m.settings_audit_clear()}</a
            >
          {/if}
        </div>
      </form>

      {#if data.filters.actor}
        <p class="v2-sub" style="font-size:12.5px;margin:0 0 12px">
          {m.settings_audit_one_person()}
          <a href={resolve(`settings/audit-log?${pageQuery({ actor: null })}`)}
            >{m.settings_audit_show_everyone()}</a
          >
        </p>
      {/if}

      {#if data.error}
        <div style="margin-bottom:16px">
          <NextAction label={m.settings_audit_filter_failed()} text={data.error} tone="rust" />
        </div>
      {/if}

      {#if !data.entries.length}
        {#if !data.error}
          <EmptyState
            title={filtered
              ? m.settings_audit_empty_filtered_title()
              : m.settings_audit_empty_title()}
            body={filtered ? m.settings_audit_empty_filtered_body() : m.settings_audit_empty_body()}
          />
        {/if}
      {:else}
        <div class="v2-table-wrap">
          <table class="v2-table">
            <thead>
              <tr>
                <th>{m.settings_audit_event()}</th>
                <th>{m.settings_audit_result()}</th>
                <th>{m.settings_audit_person()}</th>
                <th>{m.settings_audit_when()}</th>
                <th data-m="hide">{m.settings_audit_from_ip()}</th>
              </tr>
            </thead>
            <tbody>
              {#each data.entries as e (e.id)}
                {@const detail = auditDetail(e)}
                {@const webhookId = auditWebhookId(e)}
                <tr>
                  <td data-m="title">
                    <div class="v2-table-primary">{e.event_label}</div>
                    {#if detail || webhookId}
                      <div class="v2-table-secondary">
                        {detail}
                        {#if webhookId}
                          <a href={resolve(`settings/webhooks/${webhookId}`)}
                            >{m.settings_audit_open_webhook()}</a
                          >
                        {/if}
                      </div>
                    {/if}
                  </td>
                  <td data-m="tag">
                    <Pill tone={e.success ? 'moss' : 'rust'}
                      >{e.success ? m.settings_audit_ok() : m.settings_audit_refused()}</Pill
                    >
                  </td>
                  <td data-m="meta">
                    {#if e.actor}
                      <a
                        class="al-person"
                        href={resolve(`settings/audit-log?${pageQuery({ actor: e.actor.id })}`)}
                        >{auditActor(e)}</a
                      >
                    {:else}
                      <span class="v2-muted">{auditActor(e)}</span>
                    {/if}
                  </td>
                  <td data-m="meta" class="v2-muted">{relativeTime(e.created_at)}</td>
                  <td data-m="hide" class="v2-muted v2-num">{e.ip_address || ''}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
        <div style="display:flex;gap:8px;margin-top:12px">
          {#if data.offset > 0}
            <a
              class="v2-btn v2-btn-sm al-tap"
              href={resolve(
                `settings/audit-log?${pageQuery({ offset: Math.max(0, data.offset - data.pageSize) })}`
              )}>{m.settings_audit_newer()}</a
            >
          {/if}
          {#if data.offset + data.pageSize < data.count}
            <a
              class="v2-btn v2-btn-sm al-tap"
              href={resolve(
                `settings/audit-log?${pageQuery({ offset: data.offset + data.pageSize })}`
              )}>{m.settings_audit_older()}</a
            >
          {/if}
        </div>
      {/if}
    </div>
  </div>
{/if}

<style>
  .al-filters {
    display: flex;
    flex-wrap: wrap;
    gap: 10px 12px;
    align-items: flex-end;
    padding: 14px 15px;
    margin-bottom: 16px;
  }
  .al-filters .v2-field {
    flex: 1 1 150px;
    min-width: 0;
  }
  .al-toggle {
    flex: 1 1 100%;
    gap: 8px;
    font-size: 13px;
    cursor: pointer;
  }
  .al-buttons {
    display: flex;
    gap: 8px;
  }
  .al-tap {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
  }
  /* A name in a meta line. The padding widens what a thumb can hit without
     moving the text; the negative margin gives the space back. */
  .al-person {
    color: inherit;
    display: inline-block;
    padding: 10px 0;
    margin: -10px 0;
  }
</style>
