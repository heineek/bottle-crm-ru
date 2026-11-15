<script>
  /**
   * One webhook: test it, switch it, rotate its secret, edit it, and read what
   * happened to each delivery.
   *
   * Sending is asynchronous. "Send test" queues a `ping` and the row appears
   * here as Pending; a worker makes the attempt within seconds, and Refresh
   * shows the answer. A failed attempt is retried on a schedule
   * (1m, 5m, 30m, 2h, 6h) before it is marked Failed, and Redeliver on a
   * settled row sends the same event again as a new row.
   */
  import { resolve } from '$app/paths';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import { count, relativeTime } from '#lib/v2/format.js';
  import { enhance } from '$app/forms';
  import WebhookFields from '../WebhookFields.svelte';
  import SecretOnce from '../SecretOnce.svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();

  let busy = $state(false);

  const working = () => {
    busy = true;
    return async (/** @type {any} */ { update }) => {
      await update({ reset: false });
      busy = false;
    };
  };

  const DELIVERY_TONE = /** @type {const} */ ({
    succeeded: 'moss',
    pending: 'slate',
    failed: 'rust'
  });

  let actionError = $derived(
    form?.update?.error ??
      form?.toggle?.error ??
      form?.test?.error ??
      form?.rotate?.error ??
      form?.redeliver?.error ??
      form?.remove?.error ??
      null
  );
</script>

{#if data.forbidden}
  <PageHeader title={m.settings_webhooks_title_one()}>
    {#snippet crumb()}<SettingsCrumb />{/snippet}
  </PageHeader>
  <div class="v2-pad" style="padding-top:40px">
    <NextAction label={m.common_admins_only()} text={m.settings_webhooks_forbidden_detail()} />
  </div>
{:else}
  {@const e = data.endpoint}
  <PageHeader title={e.description || m.settings_webhooks_title_one()}>
    {#snippet crumb()}<SettingsCrumb />{/snippet}
    {#snippet sub()}
      <span style="word-break:break-all">{e.url}</span>
    {/snippet}
  </PageHeader>

  <div class="v2-scroll">
    <div class="v2-pad" style="padding-top:16px;padding-bottom:32px">
      {#if form?.rotated?.secret}
        <SecretOnce title={m.settings_webhooks_rotated_title()} secret={form.rotated.secret} />
      {/if}
      {#if actionError}
        <div style="margin-bottom:16px">
          <NextAction label={m.settings_webhooks_error_label()} text={actionError} tone="rust" />
        </div>
      {/if}
      {#if form?.tested}
        <p class="v2-sub wh-note">{m.settings_webhooks_test_queued()}</p>
      {:else if form?.updated}
        <p class="v2-sub wh-note">{m.settings_webhooks_saved()}</p>
      {:else if form?.redelivered}
        <p class="v2-sub wh-note">{m.settings_webhooks_redelivered()}</p>
      {/if}

      <div class="v2-card" style="padding:14px 15px;margin-bottom:18px">
        <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
          <Pill tone={e.is_active ? 'moss' : e.disabled_reason ? 'clay' : 'slate'}>
            {e.is_active
              ? m.settings_webhooks_state_sending()
              : e.disabled_reason
                ? m.settings_webhooks_state_paused()
                : m.settings_webhooks_state_off()}
          </Pill>
          <span class="v2-sub" style="font-size:12px">
            {#each messageParts(m.settings_webhooks_format_secret( { format: e.format === 'slack' ? m.settings_webhooks_format_slack_message() : m.settings_webhooks_format_json(), hint: slot('hint') } )) as p, i (i)}{#if p.key === 'hint'}<span
                  class="v2-num">{e.secret_hint}</span
                >{:else}{p.text}{/if}{/each}
          </span>
        </div>
        <p class="v2-sub" style="font-size:12px;margin:8px 0 0;overflow-wrap:anywhere">
          {m.settings_webhooks_answers_for()}
          {#if e.created_by}
            {e.created_by.name || e.created_by.email}
            {#if e.created_by.name}<span class="v2-muted">({e.created_by.email})</span>{/if}
          {:else}
            {m.settings_webhooks_creator_removed()}
          {/if}
        </p>
        {#if e.disabled_reason}
          <p class="v2-sub" style="font-size:12px;color:var(--v2-clay);margin:8px 0 0">
            {e.disabled_reason}
          </p>
        {/if}
        <p class="v2-sub" style="font-size:12px;margin:8px 0 0">
          {m.settings_webhooks_answers_note()}
        </p>
        <div class="wh-actions">
          {#if e.is_active}
            <form method="POST" action="?/test" use:enhance={working}>
              <button class="v2-btn v2-btn-primary wh-tap" disabled={busy}
                >{m.settings_webhooks_send_test()}</button
              >
            </form>
          {/if}
          <form method="POST" action="?/toggle" use:enhance={working}>
            <input type="hidden" name="is_active" value={e.is_active ? 'false' : 'true'} />
            <button class="v2-btn wh-tap" disabled={busy}>
              {e.is_active
                ? m.settings_webhooks_turn_off()
                : e.disabled_reason
                  ? m.settings_webhooks_re_enable()
                  : m.settings_webhooks_turn_on()}
            </button>
          </form>
          <ConfirmAction
            action="?/rotate"
            label={m.settings_webhooks_rotate_secret()}
            confirmLabel={m.settings_webhooks_rotate_now()}
            explain={m.settings_webhooks_rotate_explain()}
          />
          <ConfirmAction
            action="?/remove"
            label={m.common_delete()}
            confirmLabel={m.settings_webhooks_delete_confirm()}
            explain={m.settings_webhooks_delete_explain()}
          />
        </div>
      </div>

      <form
        method="POST"
        action="?/update"
        use:enhance={working}
        class="v2-card"
        style="padding:14px 15px;margin-bottom:22px"
      >
        <div class="v2-label" style="margin-bottom:10px">{m.common_settings()}</div>
        <WebhookFields catalogue={data.catalogue} values={e} idPrefix="edit" />
        <button class="v2-btn v2-btn-primary wh-tap" style="margin-top:14px" disabled={busy}>
          {m.common_save()}
        </button>
      </form>

      <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">
        <div class="v2-label">{m.settings_webhooks_deliveries()}</div>
        <span class="v2-sub v2-num" style="font-size:12px">{count(data.deliveryCount)}</span>
        <a
          class="v2-btn v2-btn-sm wh-tap"
          style="margin-left:auto"
          href={resolve(`settings/webhooks/${e.id}?offset=${data.offset}`)}
        >
          {m.settings_webhooks_refresh()}
        </a>
      </div>

      {#if !data.deliveries.length}
        <p class="v2-sub" style="font-size:12.5px">
          {m.settings_webhooks_deliveries_empty()}
        </p>
      {:else}
        <div class="v2-table-wrap">
          <table class="v2-table">
            <thead>
              <tr>
                <th>{m.settings_webhooks_col_event()}</th>
                <th>{m.common_status()}</th>
                <th class="v2-r" data-m="hide">{m.settings_webhooks_col_tries()}</th>
                <th data-m="hide">{m.settings_webhooks_col_when()}</th>
                <th class="v2-r">{m.common_actions()}</th>
              </tr>
            </thead>
            <tbody>
              {#each data.deliveries as d (d.id)}
                <tr>
                  <td data-m="title">
                    <div class="v2-table-primary v2-num">{d.event}</div>
                    <div class="v2-table-secondary">
                      {#if d.response_status}HTTP {d.response_status} ·
                      {/if}{d.error || relativeTime(d.created_at)}
                    </div>
                  </td>
                  <td data-m="tag">
                    <Pill
                      tone={DELIVERY_TONE[
                        /** @type {'succeeded'|'pending'|'failed'} */ (d.status)
                      ] ?? 'slate'}
                    >
                      {d.status === 'succeeded'
                        ? m.settings_webhooks_delivery_delivered()
                        : d.status === 'failed'
                          ? m.settings_webhooks_delivery_failed()
                          : m.settings_webhooks_delivery_pending()}
                    </Pill>
                  </td>
                  <td class="v2-r v2-num" data-m="hide">{d.attempts}</td>
                  <td data-m="hide" class="v2-muted">{relativeTime(d.created_at)}</td>
                  <td class="v2-r">
                    {#if d.status !== 'pending' && e.is_active}
                      <form method="POST" action="?/redeliver" use:enhance={working}>
                        <input type="hidden" name="delivery_id" value={d.id} />
                        <button class="v2-btn v2-btn-sm wh-tap" disabled={busy}
                          >{m.settings_webhooks_redeliver()}</button
                        >
                      </form>
                    {/if}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
        <div style="display:flex;gap:8px;margin-top:12px">
          {#if data.offset > 0}
            <a
              class="v2-btn v2-btn-sm wh-tap"
              href={resolve(
                `settings/webhooks/${e.id}?offset=${Math.max(0, data.offset - data.pageSize)}`
              )}
            >
              {m.settings_webhooks_newer()}
            </a>
          {/if}
          {#if data.offset + data.pageSize < data.deliveryCount}
            <a
              class="v2-btn v2-btn-sm wh-tap"
              href={resolve(`settings/webhooks/${e.id}?offset=${data.offset + data.pageSize}`)}
              >{m.settings_webhooks_older()}</a
            >
          {/if}
        </div>
      {/if}
    </div>
  </div>
{/if}

<style>
  .wh-actions {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    align-items: center;
    margin-top: 12px;
  }
  .wh-tap {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
  }
  .wh-note {
    color: var(--v2-moss);
    font-size: 12.5px;
    margin: 0 0 14px;
    font-weight: 550;
  }
</style>
