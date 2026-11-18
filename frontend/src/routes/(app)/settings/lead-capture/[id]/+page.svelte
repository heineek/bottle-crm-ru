<script lang="ts">
  /**
   * One lead webhook: where to post and with what key, test it, switch it,
   * replace its key, set what a post becomes, and read its newest deliveries.
   *
   * The full key is never on this page except straight after a replace; reads
   * carry only its last four characters.
   */
  import { resolve } from '$app/paths';
  import { enhance } from '$app/forms';
  import { asInternalPath } from '#lib/utils/paths.js';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import { relativeTime } from '#lib/v2/format.js';
  import { missingOption, missingOptions, inactiveOptionLabel } from '#lib/v2/pickers.js';
  import { sourceOptions } from '#lib/v2/lead-sources.js';
  import {
    deliveryResult,
    intakeState,
    mappingTargets,
    presetLabel,
    targetsFor
  } from '#lib/v2/lead-intakes.js';
  import CopyValue from '../CopyValue.svelte';
  import KeyOnce from '../KeyOnce.svelte';
  import MappingEditor from './MappingEditor.svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps, SubmitFunction } from './$types';

  let { data, form }: PageProps = $props();

  let busy = $state(false);
  const working: SubmitFunction = () => {
    busy = true;
    return async ({ update }) => {
      await update({ reset: false });
      busy = false;
    };
  };

  // `refused` computes its key, so its type puts `{ error }` under every name, this one too.
  let replacedKey = $derived(form?.replaced && 'key' in form.replaced ? form.replaced.key : '');

  let actionError = $derived(
    form?.save?.error ??
      form?.toggle?.error ??
      form?.test?.error ??
      form?.key?.error ??
      form?.remove?.error ??
      null
  );

  /** What each preset's sender asks for, in its own words. */
  function how(preset: string) {
    if (preset === 'google_ads') return m.settings_lead_capture_how_google_ads();
    if (preset === 'tally') return m.settings_lead_capture_how_tally();
    if (preset === 'gravity_forms') return m.settings_lead_capture_how_gravity_forms();
    return m.settings_lead_capture_how_generic();
  }

  // The stored owner and tags when the pickers cannot offer them (someone
  // deactivated, a tag archived): a select with no matching option submits
  // nothing, and the save would drop them.
  let missingOwner = $derived(
    data.forbidden || !data.intake.assignee
      ? null
      : missingOption(data.people, {
          id: data.intake.assignee,
          name: data.intake.assignee_name ?? m.settings_lead_capture_former_member()
        })
  );
  let activeTags = $derived(data.forbidden ? [] : data.tags.filter((t) => t.is_active !== false));
  let missingTags = $derived(
    data.forbidden
      ? []
      : missingOptions(
          activeTags,
          data.intake.tags.map((id) => ({
            id,
            name: data.tags.find((t) => t.id === id)?.name ?? m.settings_lead_capture_removed_tag()
          }))
        )
  );
</script>

{#if data.forbidden}
  <PageHeader title={m.settings_lead_capture_col_webhook()}>
    {#snippet crumb()}<SettingsCrumb />{/snippet}
  </PageHeader>
  <div class="v2-pad" style="padding-top:40px">
    <NextAction
      label={m.settings_lead_capture_admins_only()}
      text={m.settings_lead_capture_admins_only_text()}
    />
  </div>
{:else}
  {@const i = data.intake}
  {@const state = intakeState(i)}
  <PageHeader title={i.name || m.settings_lead_capture_col_webhook()}>
    {#snippet crumb()}
      <a href={resolve('settings/lead-capture')} style="color:inherit"
        >{m.settings_lead_capture_title()}</a
      >
    {/snippet}
    {#snippet sub()}
      {presetLabel(i.preset)} · <Pill tone={state.tone}>{state.label}</Pill>
    {/snippet}
  </PageHeader>

  <div class="v2-scroll">
    <div class="v2-pad" style="padding-top:16px;padding-bottom:32px">
      {#if replacedKey}
        <KeyOnce
          title={m.settings_lead_capture_key_replaced_title()}
          secret={replacedKey}
          replaced
        />
      {/if}
      {#if actionError}
        <div style="margin-bottom:16px">
          <NextAction
            label={m.settings_lead_capture_did_not_work()}
            text={actionError}
            tone="rust"
          />
        </div>
      {/if}
      {#if form?.tested}
        <p class="v2-sub ic-note">{m.settings_lead_capture_test_sent()}</p>
      {:else if form?.saved}
        <p class="v2-sub ic-note">{m.settings_lead_capture_saved()}</p>
      {/if}

      <section class="v2-card ic-card">
        <h2 class="v2-section ic-head">{m.settings_lead_capture_where_title()}</h2>
        <CopyValue label={m.settings_lead_capture_webhook_url()} value={i.url} id="ic-url" />
        <p class="v2-sub ic-text">
          {#each messageParts(m.settings_lead_capture_key_hint( { hint: slot('hint') } )) as p, n (n)}{#if p.key}<span
                class="v2-num">{i.key_hint || '????'}</span
              >{:else}{p.text}{/if}{/each}
        </p>
        <p class="v2-sub ic-text">{how(i.preset)}</p>
        {#if i.last_received_at}
          <p class="v2-sub ic-text">
            {m.settings_lead_capture_last_post({ when: relativeTime(i.last_received_at) })}
          </p>
        {/if}
        {#if i.last_error}
          <p class="v2-sub ic-text" style="color:var(--v2-clay)">
            {m.settings_lead_capture_last_refused_post({ error: i.last_error })}
          </p>
        {/if}
        <div class="ic-actions">
          {#if i.is_active}
            <form method="POST" action="?/test" use:enhance={working}>
              <button class="v2-btn v2-btn-primary ic-tap" disabled={busy}
                >{m.settings_lead_capture_send_test()}</button
              >
            </form>
          {/if}
          <form method="POST" action="?/toggle" use:enhance={working}>
            <input type="hidden" name="is_active" value={i.is_active ? 'false' : 'true'} />
            <button class="v2-btn ic-tap" disabled={busy}>
              {i.is_active
                ? m.settings_lead_capture_switch_off()
                : m.settings_lead_capture_switch_on()}
            </button>
          </form>
          <ConfirmAction
            action="?/key"
            label={m.settings_lead_capture_replace_key()}
            confirmLabel={m.settings_lead_capture_replace_confirm()}
            explain={m.settings_lead_capture_replace_explain()}
          />
          <ConfirmAction
            action="?/remove"
            label={m.common_delete()}
            confirmLabel={m.settings_lead_capture_delete_confirm()}
            explain={m.settings_lead_capture_delete_explain()}
          />
        </div>
        {#if !i.is_active}
          <p class="v2-sub ic-text">
            {m.settings_lead_capture_switched_off_note()}
          </p>
        {/if}
      </section>

      <form
        method="POST"
        action="?/save"
        use:enhance={working}
        class="v2-card ic-card"
        style="margin-bottom:22px"
      >
        <h2 class="v2-section ic-head">{m.settings_lead_capture_becomes_title()}</h2>
        <div class="ic-grid">
          <div class="v2-field ic-wide">
            <label for="ic-name">{m.common_name()}</label>
            <input
              id="ic-name"
              name="name"
              class="v2-input"
              required
              maxlength="100"
              value={i.name}
            />
          </div>
          <div class="v2-field">
            <label for="ic-source">{m.settings_lead_capture_source()}</label>
            <select id="ic-source" name="default_source" class="v2-input" value={i.default_source}>
              <option value="">{m.settings_lead_capture_not_specified()}</option>
              {#each sourceOptions(data.sources, i.default_source) as s (s.key)}
                <option value={s.key}>{s.label}</option>
              {/each}
            </select>
          </div>
          <div class="v2-field">
            <label for="ic-detail">{m.settings_lead_capture_sub_source()}</label>
            <input
              id="ic-detail"
              name="source_detail"
              class="v2-input"
              maxlength="100"
              placeholder={m.settings_lead_capture_sub_source_placeholder()}
              value={i.source_detail}
            />
          </div>
          <div class="v2-field">
            <label for="ic-owner">{m.settings_lead_capture_owner()}</label>
            <select id="ic-owner" name="assignee" class="v2-input" value={i.assignee ?? ''}>
              <option value="">{m.settings_lead_capture_nobody()}</option>
              {#if missingOwner}
                <option value={missingOwner.id}>
                  {inactiveOptionLabel(missingOwner.name)}
                </option>
              {/if}
              {#each data.people as p (p.id)}
                <option value={p.id}>{p.name}</option>
              {/each}
            </select>
            <p class="v2-hint">
              {m.settings_lead_capture_owner_hint()}
            </p>
          </div>
          <div class="v2-field">
            <label for="ic-tags">{m.settings_lead_capture_tags()}</label>
            <select id="ic-tags" name="tags" class="v2-input ic-multi" multiple size="4">
              {#each missingTags as t (t.id)}
                <option value={t.id} selected>{inactiveOptionLabel(t.name)}</option>
              {/each}
              {#each activeTags as t (t.id)}
                <option value={t.id} selected={i.tags.includes(t.id)}>{t.name}</option>
              {/each}
            </select>
          </div>
        </div>

        <div class="ic-mapping">
          <div class="v2-label" style="margin-bottom:4px">{m.settings_lead_capture_fields()}</div>
          <p class="v2-sub ic-text" style="margin-top:0">
            {#each messageParts(m.settings_lead_capture_fields_hint( { example: slot('example') } )) as p, n (n)}{#if p.key}<code
                  >data.email</code
                >{:else}{p.text}{/if}{/each}
          </p>
          <MappingEditor
            rows={i.mapping}
            targets={targetsFor(mappingTargets(data.customFields), i.mapping)}
          />
        </div>

        <button class="v2-btn v2-btn-primary ic-tap" style="margin-top:16px" disabled={busy}>
          {m.common_save()}
        </button>
      </form>

      <div class="ic-deliveries-head">
        <h2 class="v2-section">{m.settings_lead_capture_deliveries()}</h2>
        <a
          class="v2-btn v2-btn-sm ic-tap"
          href={resolve(asInternalPath(`/settings/lead-capture/${i.id}`))}
        >
          {m.settings_lead_capture_refresh()}
        </a>
      </div>
      <p class="v2-sub ic-text" style="margin-top:0">
        {m.settings_lead_capture_deliveries_hint()}
      </p>

      {#if data.deliveriesFailed}
        <p class="v2-error">{m.settings_lead_capture_deliveries_failed()}</p>
      {:else if !data.deliveries.length}
        <p class="v2-sub" style="font-size:12.5px">
          {m.settings_lead_capture_deliveries_none()}
        </p>
      {:else}
        <div class="v2-table-wrap">
          <table class="v2-table">
            <thead>
              <tr>
                <th>{m.settings_lead_capture_col_when()}</th>
                <th>{m.settings_lead_capture_col_result()}</th>
                <th>{m.settings_lead_capture_col_lead()}</th>
                <th data-m="hide">{m.settings_lead_capture_col_sender_id()}</th>
              </tr>
            </thead>
            <tbody>
              {#each data.deliveries as d (d.id)}
                {@const r = deliveryResult(d.result)}
                <tr>
                  <td data-m="title">
                    <div class="v2-table-primary">
                      {d.received_at
                        ? relativeTime(d.received_at)
                        : m.settings_lead_capture_unknown_time()}
                    </div>
                    {#if d.error}
                      <div class="v2-table-secondary" style="overflow-wrap:anywhere">{d.error}</div>
                    {/if}
                  </td>
                  <td data-m="tag"><Pill tone={r.tone}>{r.label}</Pill></td>
                  <td data-m="meta">
                    {#if d.lead}
                      <a class="ic-lead" href={resolve(asInternalPath(`/leads/${d.lead}`))}
                        >{m.settings_lead_capture_open_lead()}</a
                      >
                    {:else}
                      <span class="v2-muted">{m.settings_lead_capture_no_lead()}</span>
                    {/if}
                  </td>
                  <td data-m="hide" class="v2-num v2-muted" style="overflow-wrap:anywhere">
                    {d.external_id}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </div>
  </div>
{/if}

<style>
  .ic-card {
    padding: 15px 16px;
    margin-bottom: 18px;
  }
  .ic-head {
    margin-bottom: 12px;
  }
  .ic-text {
    font-size: 12.5px;
    margin: 10px 0 0;
    line-height: 1.5;
    max-width: 72ch;
  }
  .ic-actions {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
    align-items: center;
    margin-top: 14px;
  }
  .ic-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 13px 18px;
    align-items: start;
  }
  .ic-wide {
    grid-column: 1 / -1;
  }
  .ic-multi {
    height: auto;
  }
  .ic-mapping {
    margin-top: 18px;
    padding-top: 14px;
    border-top: 1px solid var(--v2-line-soft);
  }
  .ic-deliveries-head {
    display: flex;
    align-items: center;
    gap: 10px;
    justify-content: space-between;
  }
  .ic-lead {
    color: inherit;
    display: inline-flex;
    align-items: center;
    min-height: 44px;
  }
  .ic-tap {
    min-height: 44px;
    display: inline-flex;
    align-items: center;
  }
  .ic-note {
    color: var(--v2-moss);
    font-size: 12.5px;
    margin: 0 0 14px;
    font-weight: 550;
  }
  @media (max-width: 768px) {
    .ic-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
