<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * The addresses that turn email into tickets, or into leads (`creates`).
   *
   * Two things this page is careful about:
   *
   * 1. NO SECRET COMES BACK. InboundMailbox carries a `webhook_secret` column
   *    (Postmark's basic-auth password, Mailgun's signing key). It is
   *    write-only: the form field is never prefilled, the form says only
   *    whether one is stored (`has_webhook_secret`), and a blank field sends
   *    nothing, so an edit cannot blank it. SES is proved by the SNS signature
   *    plus the topic pin (`topic_arn`, submitted only when changed,
   *    `topicArnEdit`); both are checked in `InboundMailboxWebhookView.post`.
   * 2. An address that creates nothing does not bounce. It keeps accepting
   *    mail and the webhook stops opening cases, so the sender gets silence
   *    rather than a delivery failure. That is a materially different thing
   *    from "off", and a grey pill saying "Off" does not say it.
   *
   * The ways an address creates nothing live in `./delivery.js`: turned
   * off, a provider the webhook does not implement, and an address not yet
   * connected (no SNS pin, or no stored webhook secret).
   */
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import SettingsFormPanel from '#lib/v2/components/SettingsFormPanel.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import { count, relativeDays } from '#lib/v2/format.js';
  import {
    MAILBOX_PROVIDER_LABEL,
    PRIORITY_TONE,
    CASE_PRIORITY_LABEL,
    CASE_TYPE_LABEL
  } from '#lib/v2/enums.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { missingOption, inactiveOptionLabel } from '#lib/v2/pickers.js';
  import { sourceLabel, sourceOptions } from '#lib/v2/lead-sources.js';
  import { isOn } from '#lib/v2/modules.js';
  import { dropSummary, limitNotice, dropPolicy } from '#lib/v2/inbound-drops.js';
  import {
    deliveryState,
    deliveryLabel,
    deliveryTone,
    deliveryExplanation,
    deliveringCount,
    silentMailboxes,
    providerChoiceLabel,
    SECRET_PROVIDERS,
    webhookSetupUrl
  } from './delivery.js';
  import { Plus, MailWarning, KeyRound } from '@lucide/svelte';
  import type { PageProps } from './$types';
  import type { MailboxRow } from '#lib/server/v2/inbound-email.js';

  let { data, form }: PageProps = $props();

  // cases.InboundMailbox.PROVIDER_CHOICES is MAILBOX_PROVIDER_LABEL's key
  // order. PRIORITY_CHOICE and CASE_TYPE mirror ticket-approvals' own local
  // copies: value and label are the same string for both, and no shared map
  // exists to derive them from.
  const PROVIDERS = ['ses', 'mailgun', 'postmark', 'imap'] as const;
  const PRIORITIES = ['Low', 'Normal', 'High', 'Urgent'];
  const CASE_TYPES = ['Question', 'Incident', 'Problem'];

  let totals = $derived(data.totals);
  let mailboxes = $derived(data.mailboxes);
  let delivering = $derived(deliveringCount(mailboxes));
  let silent = $derived(silentMailboxes(mailboxes));
  let policy = $derived(dropPolicy(data.daily_limit));

  let subParts = $derived(
    messageParts(m.settings_inbound_sub({ delivering: slot('delivering'), total: slot('total') }))
  );
  let recentParts = $derived(
    messageParts(
      m.settings_inbound_sub_recent({ count: totals.cases_last_30d ?? 0, shown: slot('shown') })
    )
  );
  let routingNote = $derived(messageParts(m.settings_inbound_routing_note({ link: slot('link') })));

  // `null` when the panel is closed, `'new'` when adding, or the mailbox
  // object when editing that row. One panel, two modes, so two rows can
  // never be open for edit at once.
  let editing = $state<'new' | MailboxRow | null>(null);
  // What the open form makes, and whether the server picks the address.
  let creates = $state('tickets');
  // The provider picked in the open form, which decides the credential shown.
  let provider = $state('ses');
  let addressMode = $state('own');

  // Lead addresses need an API that has them and Leads switched on. The page
  // is also open while only Leads is on, and then offers nothing else.
  let offerLeads = $derived(data.can_create_leads && isOn(data.modules, 'leads'));
  let ticketsOn = $derived(isOn(data.modules, 'tickets'));
  let generating = $derived(editing === 'new' && addressMode === 'generate');
  // A generated address is the server's, routed by its own catch-all.
  let serverOwned = $derived(generating || (editing && editing !== 'new' && editing.is_generated));

  function openCreate() {
    editing = 'new';
    creates = ticketsOn ? 'tickets' : 'leads';
    provider = 'ses';
    addressMode = data.generated_domain ? 'generate' : 'own';
  }

  function openEdit(m: MailboxRow) {
    editing = m;
    creates = m.creates;
    provider = m.provider;
    addressMode = 'own';
  }

  /** The lead source a new lead address starts with: Email, when the org has it on. */
  let newLeadSource = $derived(
    sourceOptions(data.sources).some((s) => s.key === 'email') ? 'email' : ''
  );

  // The stored default assignee when the picker cannot offer it, because the
  // profile has been deactivated since it was chosen. `getOrgPeopleAndTeams`
  // returns active profiles only, `InboundMailbox.default_assignee` keeps
  // whoever was set. A select with no matching option submits nothing, which
  // `readValues` reads as `''` and `buildBody` sends as `null`, so an edit
  // made to change the address or the provider would also quietly move this
  // mailbox back to Unassigned.
  let missingAssignee = $derived(
    editing && editing !== 'new' ? missingOption(data.people, editing.default_assignee) : null
  );
</script>

<PageHeader title={m.settings_inbound_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#each subParts as p, i (i)}{#if p.key === 'delivering'}<span class="v2-num"
          >{count(delivering)}</span
        >{:else if p.key === 'total'}<span class="v2-num">{count(totals.count)}</span
        >{:else}{p.text}{/if}{/each}{#if ticketsOn}
      ·
      {#each recentParts as p, i (i)}{#if p.key}<span class="v2-num"
            >{count(totals.cases_last_30d)}</span
          >{:else}{p.text}{/if}{/each}
    {/if}
  {/snippet}
  {#snippet actions()}
    {#if data.can_edit && !editing}
      <button class="v2-btn v2-btn-primary" onclick={openCreate}
        ><Plus />{m.settings_inbound_add()}</button
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    {#if editing}
      {@const current = editing}
      <SettingsFormPanel
        title={current === 'new'
          ? m.settings_inbound_new_title()
          : m.settings_inbound_edit_title({ address: current.address })}
        action={current === 'new' ? '?/create' : '?/update'}
        error={current === 'new' ? form?.create?.error : form?.update?.error}
        submitLabel={current === 'new' ? m.settings_inbound_add() : m.settings_inbound_save()}
        oncancel={() => (editing = null)}
        ondone={() => (editing = null)}
      >
        {#snippet fields()}
          {#if current !== 'new'}
            <input type="hidden" name="id" value={current.id} />
          {/if}

          {#if offerLeads}
            <div class="v2-field">
              <label for="m-creates">{m.settings_inbound_creates_label()}</label>
              <select id="m-creates" class="v2-input" name="creates" bind:value={creates}>
                {#if ticketsOn || (current !== 'new' && current.creates === 'tickets')}
                  <option value="tickets">{m.settings_inbound_creates_ticket()}</option>
                {/if}
                <option value="leads">{m.settings_inbound_creates_lead()}</option>
              </select>
              {#if creates === 'leads'}
                <p class="v2-hint">{m.settings_inbound_creates_lead_hint()}</p>
              {/if}
            </div>
          {/if}

          {#if current === 'new' && data.generated_domain}
            <div class="v2-field">
              <span class="v2-label" id="m-mode-label">{m.settings_inbound_address_label()}</span>
              <div role="radiogroup" aria-labelledby="m-mode-label" class="v2-mbx-modes">
                <label>
                  <input
                    type="radio"
                    name="address_mode"
                    value="generate"
                    bind:group={addressMode}
                  />
                  {m.settings_inbound_mode_generate({ domain: data.generated_domain })}
                </label>
                <label>
                  <input type="radio" name="address_mode" value="own" bind:group={addressMode} />
                  {m.settings_inbound_mode_own()}
                </label>
              </div>
            </div>
          {/if}

          {#if serverOwned}
            {#if current !== 'new'}
              <div class="v2-field">
                <span class="v2-label">{m.settings_inbound_address_label()}</span>
                <p class="v2-hint" style="margin:0">
                  {m.settings_inbound_server_owned({ address: current.address })}
                </p>
              </div>
            {/if}
          {:else}
            <div class="v2-field">
              <label for="m-address">{m.settings_inbound_address_label()}</label>
              <input
                id="m-address"
                class="v2-input"
                type="email"
                name="address"
                required
                value={current === 'new' ? '' : current.address}
              />
              {#if current !== 'new'}
                <p class="v2-hint">
                  {current.creates === 'leads'
                    ? m.settings_inbound_address_hint_leads()
                    : m.settings_inbound_address_hint()}
                </p>
              {/if}
            </div>

            <div class="v2-field">
              <label for="m-provider">{m.settings_inbound_provider_label()}</label>
              <select id="m-provider" class="v2-input" name="provider" bind:value={provider}>
                {#each PROVIDERS as p (p)}
                  <option value={p}>
                    {providerChoiceLabel(p, MAILBOX_PROVIDER_LABEL[p])}
                  </option>
                {/each}
              </select>
              <p class="v2-hint">{m.settings_inbound_provider_hint()}</p>
            </div>

            {#if SECRET_PROVIDERS.includes(provider)}
              {@const setupUrl =
                current === 'new' ? null : webhookSetupUrl(provider, current.id, data.api_base)}
              <div class="v2-field">
                <label for="m-secret"
                  >{provider === 'postmark'
                    ? m.settings_inbound_secret_password()
                    : m.settings_inbound_secret_signing_key()}</label
                >
                <input
                  id="m-secret"
                  class="v2-input"
                  type="password"
                  name="webhook_secret"
                  autocomplete="new-password"
                  autocapitalize="off"
                  spellcheck="false"
                  maxlength="128"
                  placeholder={current !== 'new' && current.has_webhook_secret
                    ? m.settings_inbound_secret_placeholder()
                    : ''}
                />
                <p class="v2-hint">
                  {current !== 'new' && current.has_webhook_secret
                    ? m.settings_inbound_secret_stored()
                    : m.settings_inbound_secret_missing()}
                  {provider === 'postmark'
                    ? m.settings_inbound_secret_postmark_hint()
                    : m.settings_inbound_secret_mailgun_hint()}
                </p>
                {#if setupUrl}
                  <p class="v2-hint">
                    {provider === 'postmark'
                      ? m.settings_inbound_setup_url_postmark()
                      : m.settings_inbound_setup_url_mailgun()}
                    <code style="word-break:break-all">{setupUrl}</code>
                  </p>
                {:else if current === 'new'}
                  <p class="v2-hint">{m.settings_inbound_setup_url_pending()}</p>
                {/if}
              </div>
            {:else}
              <div class="v2-field">
                <label for="m-topic">{m.settings_inbound_topic_label()}</label>
                <input
                  id="m-topic"
                  class="v2-input"
                  name="topic_arn"
                  autocomplete="off"
                  autocapitalize="off"
                  spellcheck="false"
                  placeholder="arn:aws:sns:us-east-1:123456789012:inbound-mail"
                  value={current === 'new' ? '' : (current.topic_arn ?? '')}
                />
                <input
                  type="hidden"
                  name="topic_arn_was"
                  value={current === 'new' ? '' : (current.topic_arn ?? '')}
                />
                <p class="v2-hint">{m.settings_inbound_topic_hint()}</p>
              </div>
            {/if}
          {/if}

          {#if offerLeads}
            <!-- Drawn either way and only hidden, so switching what the
                 address makes and back keeps both sets of defaults. -->
            <div class="v2-field" hidden={creates !== 'leads'}>
              <label for="m-lead-source">{m.settings_inbound_lead_source_label()}</label>
              <select
                id="m-lead-source"
                class="v2-input"
                name="lead_source"
                value={current === 'new' ? newLeadSource : current.lead_source}
              >
                <option value="">{m.settings_inbound_lead_source_none()}</option>
                {#each sourceOptions(data.sources, current === 'new' ? '' : current.lead_source) as s (s.key)}
                  <option value={s.key}>{s.label}</option>
                {/each}
              </select>
            </div>
            <div class="v2-field" hidden={creates !== 'leads'}>
              <label for="m-lead-detail">{m.settings_inbound_lead_detail_label()}</label>
              <input
                id="m-lead-detail"
                class="v2-input"
                name="lead_source_detail"
                maxlength="100"
                placeholder={m.settings_inbound_lead_detail_placeholder()}
                value={current === 'new' ? '' : current.lead_source_detail}
              />
            </div>
          {/if}

          <div class="v2-field" hidden={creates === 'leads'}>
            <label for="m-priority">{m.settings_inbound_priority_label()}</label>
            <select id="m-priority" class="v2-input" name="default_priority">
              {#each PRIORITIES as p (p)}
                <option
                  value={p}
                  selected={current === 'new' ? p === 'Normal' : current.default_priority === p}
                >
                  {CASE_PRIORITY_LABEL[p] ?? p}
                </option>
              {/each}
            </select>
          </div>

          <div class="v2-field" hidden={creates === 'leads'}>
            <label for="m-type">{m.settings_inbound_type_label()}</label>
            <select id="m-type" class="v2-input" name="default_case_type">
              <option value="" selected={current === 'new' || !current.default_case_type}>
                {m.settings_inbound_type_none()}
              </option>
              {#each CASE_TYPES as t (t)}
                <option value={t} selected={current !== 'new' && current.default_case_type === t}>
                  {CASE_TYPE_LABEL[t] ?? t}
                </option>
              {/each}
            </select>
          </div>

          <div class="v2-field">
            <label for="m-assignee">{m.settings_inbound_assignee_label()}</label>
            <select id="m-assignee" class="v2-input" name="default_assignee_id">
              <option value="" selected={current === 'new' || !current.default_assignee}>
                {m.settings_inbound_unassigned()}
              </option>
              {#if missingAssignee}
                <option value={missingAssignee.id} selected>
                  {inactiveOptionLabel(missingAssignee.name)}
                </option>
              {/if}
              {#each data.people as p (p.id)}
                <option
                  value={p.id}
                  selected={current !== 'new' && current.default_assignee?.id === p.id}
                >
                  {p.name}
                </option>
              {/each}
            </select>
            {#if missingAssignee}
              <p class="v2-hint">
                {m.settings_inbound_assignee_inactive_hint()}
              </p>
            {:else if creates === 'leads'}
              <p class="v2-hint">{m.settings_inbound_assignee_leads_hint()}</p>
            {/if}
          </div>

          {#if current === 'new'}
            <div class="v2-field">
              <label for="m-active">{m.settings_inbound_active_label()}</label>
              <label style="display:flex;gap:8px;align-items:center;font-weight:400">
                <input id="m-active" type="checkbox" name="is_active" value="true" checked />
                {creates === 'leads'
                  ? m.settings_inbound_active_hint_leads()
                  : m.settings_inbound_active_hint()}
              </label>
            </div>
          {/if}
        {/snippet}
      </SettingsFormPanel>
    {/if}

    {#if form?.deactivate?.error}
      <p class="v2-error" style="margin-bottom:12px">{form.deactivate.error}</p>
    {/if}
    {#if form?.activate?.error}
      <p class="v2-error" style="margin-bottom:12px">{form.activate.error}</p>
    {/if}
    {#if form?.remove?.error}
      <p class="v2-error" style="margin-bottom:12px">{form.remove.error}</p>
    {/if}

    <!-- On, and creating nothing. A turned-off address is not in here: that
         state was chosen, and the row already reads correctly. These two were
         drawn as working right up until this banner existed. -->
    {#if silent.length}
      <div class="v2-mbx-banner">
        <MailWarning size={17} style="color:var(--v2-clay);flex:none;margin-top:1px" />
        <div>
          <div style="font-weight:600;font-size:13px">
            {(silent.length === 1 ? m.settings_inbound_silent_one : m.settings_inbound_silent_many)(
              {
                addresses: silent.map((box) => box.address).join(', ')
              }
            )}
          </div>
          <p class="v2-sub" style="font-size:12px;margin:4px 0 0;line-height:1.5">
            {m.settings_inbound_silent_body()}
          </p>
        </div>
      </div>
    {/if}

    <div class="v2-label" style="margin-bottom:10px">{m.settings_inbound_addresses_heading()}</div>
    <div style="display:flex;flex-direction:column;gap:9px">
      {#each mailboxes as box (box.id)}
        {@const state = deliveryState(box)}
        {@const why = deliveryExplanation(
          state,
          MAILBOX_PROVIDER_LABEL[box.provider],
          box.creates,
          box.provider
        )}
        {@const dropped = dropSummary(box)}
        {@const atLimit = limitNotice(box.limit_reached, data.daily_limit)}
        <div class="v2-card v2-mbx" style="opacity:{state === 'live' ? 1 : 0.68}">
          <div style="flex:1;min-width:0">
            <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
              <b style="font-size:13.5px;overflow-wrap:anywhere">{box.address}</b>
              <Pill tone={deliveryTone(state)}>{deliveryLabel(state, box.creates)}</Pill>
            </div>
            <div class="v2-sub" style="font-size:11.5px;margin-top:4px">
              {box.is_generated
                ? m.settings_inbound_made_by_server()
                : MAILBOX_PROVIDER_LABEL[box.provider]} ·
              {#if box.creates === 'leads'}
                {m.settings_inbound_last_mail({ when: relativeDays(box.last_received_at) })}
              {:else if box.cases_last_30d}
                {#each messageParts(m.settings_inbound_recent( { count: box.cases_last_30d, shown: slot('shown'), when: relativeDays(box.last_received_at) } )) as p, i (i)}{#if p.key}<span
                      class="v2-num">{count(box.cases_last_30d)}</span
                    >{:else}{p.text}{/if}{/each}
              {:else}
                {m.settings_inbound_recent_none({ when: relativeDays(box.last_received_at) })}
              {/if}
            </div>
            {#if dropped}
              <div class="v2-sub" style="font-size:11.5px;margin-top:4px">{dropped}</div>
            {/if}
            {#if atLimit}
              <p
                class="v2-sub"
                style="font-size:11.5px;margin:6px 0 0;line-height:1.5;color:var(--v2-clay)"
              >
                {atLimit}
              </p>
            {/if}
            {#if why}
              <p class="v2-sub" style="font-size:11.5px;margin:6px 0 0;line-height:1.5">{why}</p>
            {/if}

            <!-- What a ticket from here starts out as. These are the defaults
                 a routing rule then reads, so they are worth stating next to
                 the address rather than behind an edit dialog. -->
            {#if box.creates === 'leads'}
              <div class="v2-mbx-defaults">
                <span class="v2-sub">{m.settings_inbound_makes_leads()}</span>
                {#if box.lead_source}
                  <Pill tone="slate">{sourceLabel(data.sources, box.lead_source)}</Pill>
                {/if}
                {#if box.lead_source_detail}
                  <span class="v2-sub">{box.lead_source_detail}</span>
                {/if}
                <span class="v2-sub">
                  {box.default_assignee
                    ? m.settings_inbound_owned_by({ name: box.default_assignee.name ?? '' })
                    : m.settings_inbound_owned_by_nobody()}
                </span>
              </div>
            {:else}
              <div class="v2-mbx-defaults">
                <span class="v2-sub">{m.settings_inbound_opens_as()}</span>
                <Pill tone={PRIORITY_TONE[box.default_priority]}
                  >{CASE_PRIORITY_LABEL[box.default_priority] ?? box.default_priority}</Pill
                >
                {#if box.default_case_type}
                  <Pill tone="slate"
                    >{CASE_TYPE_LABEL[box.default_case_type] ?? box.default_case_type}</Pill
                  >
                {/if}
                <span class="v2-sub">
                  {box.default_assignee
                    ? m.settings_inbound_assigned_to({ name: box.default_assignee.name ?? '' })
                    : m.settings_inbound_then_routed()}
                </span>
              </div>
            {/if}
          </div>

          {#if data.can_edit}
            <div style="display:flex;gap:6px;align-items:center;flex:none">
              <button class="v2-btn v2-btn-sm" type="button" onclick={() => openEdit(box)}>
                {m.settings_inbound_edit()}
              </button>
              {#if box.is_active}
                <ConfirmAction
                  action="?/deactivate"
                  label={m.settings_inbound_turn_off()}
                  confirmLabel={m.settings_inbound_turn_off()}
                  explain={box.creates === 'leads'
                    ? m.settings_inbound_turn_off_explain_leads()
                    : m.settings_inbound_turn_off_explain()}
                  hidden={{ id: box.id }}
                />
              {:else}
                <form method="POST" action="?/activate" use:enhance>
                  <input type="hidden" name="id" value={box.id} />
                  <button class="v2-btn v2-btn-sm" type="submit"
                    >{m.settings_inbound_turn_on()}</button
                  >
                </form>
              {/if}
              <ConfirmAction
                action="?/remove"
                label={m.settings_inbound_delete()}
                confirmLabel={m.settings_inbound_delete()}
                explain={box.creates === 'leads'
                  ? m.settings_inbound_delete_explain_leads()
                  : m.settings_inbound_delete_explain()}
                hidden={{ id: box.id }}
              />
            </div>
          {/if}
        </div>
      {/each}
    </div>

    <!--
      What actually authenticates a delivery, which is not what this card used
      to claim. It described a per-address shared secret the server minted on
      create; the server mints nothing, nothing in the backend compares that
      column, and an admin reading the old wording would have believed their
      inbound mail was protected by a credential that is not in the path. The
      real pair, the SNS signature and the topic pin, is stated instead.
    -->
    <div class="v2-card" style="padding:15px 16px;margin-top:20px">
      <div style="display:flex;gap:10px;align-items:flex-start">
        <KeyRound size={16} style="color:var(--v2-slate);flex:none;margin-top:2px" />
        <div>
          <div style="font-weight:600;font-size:13px">{m.settings_inbound_genuine_title()}</div>
          <p class="v2-sub" style="font-size:12.5px;margin:5px 0 0;line-height:1.5">
            {m.settings_inbound_genuine_body()}
          </p>
          {#if data.generated_domain}
            <p class="v2-sub" style="font-size:12.5px;margin:8px 0 0;line-height:1.5">
              {m.settings_inbound_generated_note()}
            </p>
          {/if}
          <p class="v2-sub" style="font-size:12.5px;margin:8px 0 0;line-height:1.5">
            {m.settings_inbound_secret_body()}
          </p>
          {#if policy}
            <p class="v2-sub" style="font-size:12.5px;margin:8px 0 0;line-height:1.5">{policy}</p>
          {/if}
        </div>
      </div>
    </div>

    <p class="v2-sub" style="font-size:11.5px;margin-top:14px">
      {#each routingNote as p, i (i)}{#if p.key === 'link'}<a
            href={resolve('settings/routing')}
            style="color:inherit">{m.settings_inbound_routing_link()}</a
          >{:else}{p.text}{/if}{/each}
    </p>
  </div>
</div>

<style>
  .v2-mbx {
    display: flex;
    gap: 13px;
    align-items: flex-start;
    padding: 14px 16px;
  }
  .v2-mbx-defaults {
    display: flex;
    gap: 6px;
    align-items: center;
    flex-wrap: wrap;
    margin-top: 9px;
    font-size: 11.5px;
  }
  .v2-mbx-modes {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .v2-mbx-modes label {
    display: flex;
    gap: 8px;
    align-items: center;
    min-height: 44px;
    font-weight: 400;
  }
  .v2-mbx-banner {
    display: flex;
    gap: 11px;
    align-items: flex-start;
    padding: 14px 16px;
    margin-bottom: 18px;
    border: 1px solid var(--v2-line);
    border-radius: var(--v2-radius);
    background: var(--v2-card);
  }
</style>
