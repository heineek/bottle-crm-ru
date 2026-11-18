<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * Whether a customer's reply can bring a closed ticket back.
   *
   * One row per org, four fields. Small enough that v1's form is not wrong,
   * just uninformative. The whole question here is what number to put in the
   * window, and the only thing that answers it is how customers actually
   * behave: the median reply comes back in two days, and four replies last
   * month arrived after the window and reopened nothing.
   *
   * Those four are the cost of the current setting. A settings form that shows
   * the field but not the consequence makes the number a guess forever.
   */
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import SettingsFormPanel from '#lib/v2/components/SettingsFormPanel.svelte';
  import { count } from '#lib/v2/format.js';
  import { REOPEN_TO_STATUSES, CASE_STATUS_LABEL } from '#lib/v2/enums.js';
  import { RotateCcw, MailX } from '@lucide/svelte';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  let editing = $state(false);

  let p = $derived(data.policy);
  let inboundNote = $derived(messageParts(m.settings_reopen_inbound_note({ link: slot('link') })));
</script>

<PageHeader title={m.settings_reopen_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {p.is_enabled
      ? m.settings_reopen_sub_on({ days: p.reopen_window_days })
      : m.settings_reopen_sub_off()}
  {/snippet}
  {#snippet actions()}
    {#if data.can_edit && !editing}
      <button class="v2-btn v2-btn-primary" onclick={() => (editing = true)}
        >{m.settings_reopen_edit_button()}</button
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-pad" style="padding-top:16px;flex:none">
  <div class="v2-stats">
    <StatCard
      label={m.settings_reopen_stat_reopened()}
      value={count(p.reopened_last_30d)}
      tone="ink"
      detail={m.settings_reopen_stat_reopened_detail()}
    />
    <!-- "n/a" rather than 0 while the policy is off. `_evaluate_reopen` returns
         `None` on `if not policy["is_enabled"]` BEFORE it compares the window,
         and the `out_of_reopen_window` flag this metric counts is written only
         for the "out_of_window" return. So with reopening off nothing is ever
         flagged and the count is always zero, in exactly the state where every
         reply to a closed ticket reopens nothing. A plain 0 there is
         reassurance about the one thing certainly happening. -->
    <StatCard
      label={m.settings_reopen_stat_missed()}
      value={p.is_enabled ? count(p.replies_after_window_30d) : m.settings_reopen_not_applicable()}
      tone={p.is_enabled && p.replies_after_window_30d > 0 ? 'clay' : 'slate'}
      detail={p.is_enabled
        ? m.settings_reopen_stat_missed_detail_on()
        : m.settings_reopen_stat_missed_detail_off()}
    />
    <StatCard
      label={m.settings_reopen_stat_median()}
      value={m.settings_reopen_stat_median_value({ days: p.median_days_to_reply })}
      tone="slate"
      detail={m.settings_reopen_stat_median_detail()}
    />
  </div>
</div>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-bottom:32px">
    {#if editing}
      <SettingsFormPanel
        title={m.settings_reopen_title()}
        action="?/update"
        error={form?.update?.error}
        submitLabel={m.settings_reopen_save_button()}
        oncancel={() => (editing = false)}
        ondone={() => (editing = false)}
      >
        {#snippet fields()}
          <div class="v2-field v2-sfp-wide">
            <label for="f-enabled">{m.settings_reopen_enabled_label()}</label>
            <label style="display:flex;gap:8px;align-items:center;font-weight:400">
              <input
                id="f-enabled"
                type="checkbox"
                name="is_enabled"
                value="true"
                checked={p.is_enabled}
              />
              {m.settings_reopen_enabled_hint()}
            </label>
          </div>

          <div class="v2-field">
            <label for="f-window">{m.settings_reopen_window_label()}</label>
            <input
              id="f-window"
              class="v2-input"
              type="number"
              name="reopen_window_days"
              min="1"
              max="365"
              required
              value={p.reopen_window_days}
            />
            <p class="v2-hint">{m.settings_reopen_window_hint()}</p>
          </div>

          <div class="v2-field">
            <label for="f-status">{m.settings_reopen_status_label()}</label>
            <select id="f-status" class="v2-input" name="reopen_to_status">
              {#each REOPEN_TO_STATUSES as status (status)}
                <option value={status} selected={status === p.reopen_to_status}
                  >{CASE_STATUS_LABEL[status] ?? status}</option
                >
              {/each}
            </select>
            <p class="v2-hint">
              {m.settings_reopen_status_hint()}
            </p>
          </div>

          <div class="v2-field v2-sfp-wide">
            <label for="f-notify">{m.settings_reopen_notify_label()}</label>
            <label style="display:flex;gap:8px;align-items:center;font-weight:400">
              <input
                id="f-notify"
                type="checkbox"
                name="notify_assigned"
                value="true"
                checked={p.notify_assigned}
              />
              {m.settings_reopen_notify_hint()}
            </label>
          </div>
        {/snippet}
      </SettingsFormPanel>
    {/if}
    <div class="v2-split">
      <div>
        <div class="v2-label" style="margin-bottom:10px">{m.settings_reopen_rule_heading()}</div>
        <div class="v2-card" style="overflow:hidden">
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.settings_reopen_enabled_label()}</b>
              <span class="v2-sub" style="font-size:11.5px">
                {m.settings_reopen_enabled_hint()}
              </span>
            </div>
            <Pill tone={p.is_enabled ? 'moss' : 'slate'}
              >{p.is_enabled ? m.settings_reopen_on() : m.settings_reopen_off()}</Pill
            >
          </div>
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.settings_reopen_window_row()}</b>
              <span class="v2-sub" style="font-size:11.5px">
                {m.settings_reopen_window_hint()}
              </span>
            </div>
            <span class="v2-num" style="font-size:13px"
              >{m.settings_reopen_window_days({ count: p.reopen_window_days })}</span
            >
          </div>
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.settings_reopen_status_label()}</b>
              <!-- Must be a non-terminal status: reopening a ticket into a
                   closed status would close it again on arrival. -->
              <span class="v2-sub" style="font-size:11.5px">
                {m.settings_reopen_status_row_hint()}
              </span>
            </div>
            <Pill tone="ink">{CASE_STATUS_LABEL[p.reopen_to_status] ?? p.reopen_to_status}</Pill>
          </div>
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.settings_reopen_notify_label()}</b>
              <span class="v2-sub" style="font-size:11.5px">
                {m.settings_reopen_notify_hint()}
              </span>
            </div>
            <Pill tone={p.notify_assigned ? 'moss' : 'slate'}>
              {p.notify_assigned ? m.common_yes() : m.common_no()}
            </Pill>
          </div>
        </div>
      </div>

      <div>
        <div class="v2-label" style="margin-bottom:10px">{m.settings_reopen_changes_heading()}</div>
        <div class="v2-card" style="padding:15px 16px">
          <div style="display:flex;gap:10px;align-items:flex-start">
            <RotateCcw size={16} style="color:var(--v2-slate);flex:none;margin-top:2px" />
            <p class="v2-sub" style="font-size:12.5px;margin:0;line-height:1.5">
              {#if p.is_enabled}
                {#each messageParts(m.settings_reopen_changes_on( { status: slot('status') } )) as part, i (i)}{#if part.key}<b
                      style="font-weight:600;color:var(--v2-ink)"
                      >{CASE_STATUS_LABEL[p.reopen_to_status] ?? p.reopen_to_status}</b
                    >{:else}{part.text}{/if}{/each}
              {:else}
                <!-- Present tense, and the policy is off, so this cannot be
                     written as though a reply still reopened anything. -->
                {#each messageParts(m.settings_reopen_changes_off( { status: slot('status') } )) as part, i (i)}{#if part.key}<b
                      style="font-weight:600;color:var(--v2-ink)"
                      >{CASE_STATUS_LABEL[p.reopen_to_status] ?? p.reopen_to_status}</b
                    >{:else}{part.text}{/if}{/each}
              {/if}
            </p>
          </div>
        </div>

        {#if !p.is_enabled}
          <div class="v2-card" style="padding:15px 16px;margin-top:12px">
            <div style="display:flex;gap:10px;align-items:flex-start">
              <MailX size={16} style="color:var(--v2-clay);flex:none;margin-top:2px" />
              <div>
                <div style="font-weight:600;font-size:13px">
                  {m.settings_reopen_no_count_title()}
                </div>
                <p class="v2-sub" style="font-size:12.5px;margin:5px 0 0;line-height:1.5">
                  {m.settings_reopen_no_count_body()}
                </p>
              </div>
            </div>
          </div>
        {:else if p.replies_after_window_30d > 0}
          <div class="v2-card" style="padding:15px 16px;margin-top:12px">
            <div style="display:flex;gap:10px;align-items:flex-start">
              <MailX size={16} style="color:var(--v2-clay);flex:none;margin-top:2px" />
              <div>
                <div style="font-weight:600;font-size:13px">
                  {#each messageParts(m.settings_reopen_late_title( { count: p.replies_after_window_30d, shown: slot('shown') } )) as part, i (i)}{#if part.key}<span
                        class="v2-num">{count(p.replies_after_window_30d)}</span
                      >{:else}{part.text}{/if}{/each}
                </div>
                <p class="v2-sub" style="font-size:12.5px;margin:5px 0 0;line-height:1.5">
                  {#each messageParts(m.settings_reopen_late_body( { days: slot('days') } )) as part, i (i)}{#if part.key}<span
                        class="v2-num">{p.reopen_window_days}</span
                      >{:else}{part.text}{/if}{/each}
                </p>
              </div>
            </div>
          </div>
        {/if}

        <p class="v2-sub" style="font-size:11.5px;margin-top:14px">
          {#each inboundNote as part, i (i)}{#if part.key}<a
                href={resolve('settings/inbound-email')}
                style="color:inherit">{m.settings_reopen_inbound_link()}</a
              >{:else}{part.text}{/if}{/each}
        </p>
      </div>
    </div>
  </div>
</div>
