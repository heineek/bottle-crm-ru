<script lang="ts">
  /**
   * Outbound webhooks: where the org's events are sent.
   *
   * Admin-only to read as well as to change. A hook URL is often a credential
   * of its own (Zapier and Slack put theirs in the path), and every endpoint
   * receives copies of records, so the API answers a member 403 and this page
   * says so instead of drawing an empty table.
   *
   * The signing secret appears once, straight after a create, and never on
   * this list: the API only returns `secret_hint` here.
   */
  import { webhookFormatName } from '#lib/v2/lead-alerts.js';
  import { resolve } from '$app/paths';
  import { asInternalPath } from '#lib/utils/paths.js';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { count, shortDate } from '#lib/v2/format.js';
  import { enhance, type SubmitFunction } from '$app/forms';
  import { Plus, ShieldAlert } from '@lucide/svelte';
  import WebhookFields from './WebhookFields.svelte';
  import SecretOnce from './SecretOnce.svelte';
  import { wordsOn } from '#lib/v2/modules.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';
  import type { components } from '#lib/api-schema.js';

  type WebhookEndpoint = components['schemas']['WebhookEndpoint'];

  let { data, form }: PageProps = $props();

  // "a lead, deal, ticket or other record", naming only the modules that are on.
  let changedKinds = $derived.by(() => {
    const kinds = wordsOn(
      data.modules,
      [
        ['leads', m.settings_webhooks_kind_lead()],
        ['deals', m.settings_webhooks_kind_deal()],
        ['tickets', m.settings_webhooks_kind_ticket()],
        [null, m.settings_webhooks_kind_other()]
      ],
      m.settings_webhooks_kind_or()
    );
    return kinds === m.settings_webhooks_kind_other() ? m.settings_webhooks_kind_record() : kinds;
  });

  let sigBody = $derived(messageParts(m.settings_webhooks_sig_body({ header: slot('header') })));

  let creating = $state(false);
  let busy = $state(false);

  let atLimit = $derived(!data.forbidden && data.endpoints.length >= data.limit);

  const createSubmit: SubmitFunction = () => {
    busy = true;
    return async ({ update, result }) => {
      await update({ reset: false });
      busy = false;
      if (result?.type === 'success' && result?.data?.created) creating = false;
    };
  };

  /**
   * Who answers for an endpoint. Nobody once their user has been deleted,
   * which also pauses it.
   */
  function creatorLabel(e: WebhookEndpoint) {
    return e.created_by
      ? e.created_by.name || e.created_by.email
      : m.settings_webhooks_creator_removed();
  }

  function endpointState(e: WebhookEndpoint) {
    if (e.is_active) return { tone: 'moss' as const, label: m.settings_webhooks_state_sending() };
    // The server turned it off: a 410 from the receiver, or its creator lost
    // the standing to own it. Either way an admin can turn it back on.
    if (e.disabled_reason)
      return { tone: 'clay' as const, label: m.settings_webhooks_state_paused() };
    return { tone: 'slate' as const, label: m.settings_webhooks_state_off() };
  }
</script>

<PageHeader title={m.settings_webhooks_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#if !data.forbidden}
      {#each messageParts(m.settings_webhooks_list_sub( { sending: slot('sending'), total: slot('total') } )) as p, i (i)}{#if p.key === 'sending'}<span
            class="v2-num">{count(data.endpoints.filter((e) => e.is_active).length)}</span
          >{:else if p.key === 'total'}<span class="v2-num">{count(data.endpoints.length)}</span
          >{:else}{p.text}{/if}{/each}
    {/if}
  {/snippet}
  {#snippet actions()}
    {#if !data.forbidden && !atLimit}
      <button class="v2-btn v2-btn-primary" onclick={() => (creating = !creating)}>
        <Plus />{m.settings_webhooks_new()}
      </button>
    {/if}
  {/snippet}
</PageHeader>

{#if data.forbidden}
  <div class="v2-pad" style="padding-top:40px">
    <NextAction label={m.common_admins_only()} text={m.settings_webhooks_forbidden_list()} />
  </div>
{:else}
  <div class="v2-scroll">
    <div class="v2-pad" style="padding-top:16px;padding-bottom:32px">
      {#if form?.created?.secret}
        <SecretOnce title={m.settings_webhooks_created_title()} secret={form.created.secret} />
      {/if}

      {#if form?.create?.error && !creating}
        <div style="margin-bottom:16px">
          <NextAction
            label={m.settings_webhooks_error_label()}
            text={form.create.error}
            tone="rust"
          />
        </div>
      {/if}

      {#if creating}
        <form
          method="POST"
          action="?/create"
          use:enhance={createSubmit}
          class="v2-card"
          style="padding:14px 15px;margin-bottom:18px"
        >
          <WebhookFields
            catalogue={data.catalogue}
            values={form?.create?.values ?? {}}
            idPrefix="new"
          />
          {#if form?.create?.error}
            <p class="v2-sub" style="color:var(--v2-rust);font-size:12px;margin:10px 0 0">
              {form.create.error}
            </p>
          {/if}
          <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:14px">
            <button class="v2-btn v2-btn-primary wh-tap" disabled={busy}
              >{m.settings_webhooks_add()}</button
            >
            <button
              type="button"
              class="v2-btn wh-tap"
              disabled={busy}
              onclick={() => (creating = false)}
            >
              {m.common_cancel()}
            </button>
          </div>
        </form>
      {/if}

      {#if atLimit}
        <p class="v2-sub" style="font-size:12px;margin:0 0 14px">
          {m.settings_webhooks_at_limit({ count: data.limit })}
        </p>
      {/if}

      {#if !data.endpoints.length}
        <EmptyState
          title={m.settings_webhooks_empty_title()}
          body={m.settings_webhooks_empty_body({ kinds: changedKinds })}
        >
          {#snippet actions()}
            <button class="v2-btn v2-btn-primary" onclick={() => (creating = true)}>
              <Plus />{m.settings_webhooks_new()}
            </button>
          {/snippet}
        </EmptyState>
      {:else}
        <div class="v2-table-wrap">
          <table class="v2-table">
            <thead>
              <tr>
                <th>{m.settings_webhooks_col_endpoint()}</th>
                <th>{m.settings_webhooks_col_state()}</th>
                <th class="v2-r">{m.settings_webhooks_col_events()}</th>
                <th data-m="hide">{m.settings_webhooks_col_added()}</th>
              </tr>
            </thead>
            <tbody>
              {#each data.endpoints as e (e.id)}
                {@const s = endpointState(e)}
                <tr>
                  <td data-m="title">
                    <a
                      class="v2-row-link"
                      href={resolve(asInternalPath(`/settings/webhooks/${e.id}`))}
                    >
                      <div class="v2-table-primary" style="word-break:break-all">{e.url}</div>
                      <div class="v2-table-secondary">
                        {m.settings_webhooks_row_meta({
                          description: e.description || webhookFormatName(e.format),
                          creator: creatorLabel(e)
                        })}
                      </div>
                    </a>
                  </td>
                  <td data-m="tag"><Pill tone={s.tone}>{s.label}</Pill></td>
                  <td class="v2-r v2-num" data-m="meta" data-l={m.settings_webhooks_col_events()}
                    >{count(e.events.length)}</td
                  >
                  <td data-m="hide" class="v2-muted">{shortDate(e.created_at)}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}

      <div
        style="display:flex;gap:10px;align-items:flex-start;margin-top:20px;padding:14px 16px;border:1px solid var(--v2-line);border-radius:var(--v2-radius)"
      >
        <ShieldAlert size={16} style="color:var(--v2-clay);flex:none;margin-top:1px" />
        <div>
          <div style="font-weight:600;font-size:13px">
            {m.settings_webhooks_sig_title()}
          </div>
          <p class="v2-sub" style="font-size:12px;margin:4px 0 0">
            {#each sigBody as p, i (i)}{#if p.key}<code>X-BottleCRM-Signature</code
                >{:else}{p.text}{/if}{/each}
          </p>
        </div>
      </div>
    </div>
  </div>
{/if}

<style>
  .wh-tap {
    min-height: 44px;
  }
</style>
