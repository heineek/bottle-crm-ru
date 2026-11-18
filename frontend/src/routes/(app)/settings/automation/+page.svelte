<script lang="ts">
  /**
   * Automation rules: what the organization does for itself when a record is
   * created or changes. Admins only; the server answers a member with a 403,
   * which the load turns into `forbidden`.
   */
  import { resolve } from '$app/paths';
  import { enhance } from '$app/forms';
  import { asInternalPath } from '#lib/utils/paths.js';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import AdminsOnly from '#lib/v2/components/automation/AdminsOnly.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import {
    triggerSentence,
    runsLabel,
    STATUS,
    OBJECT_LABELS,
    objectOf,
    statusNote,
    pausedByModule,
    modulePausedNote
  } from '#lib/v2/automation.js';
  import { ArrowUp, ArrowDown, Plus } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import type { Tone } from '#lib/v2/enums.js';
  import type { components } from '#lib/api-schema.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  let rules = $derived(data.rules ?? []);
  let paused = $derived(rules.filter((r) => r.status === 'paused'));

  function statusOf(rule: components['schemas']['RuleRow']) {
    return (
      (STATUS as Record<string, { label: string; tone: Tone }>)[rule.status] ?? {
        label: rule.status,
        tone: 'slate'
      }
    );
  }
</script>

<PageHeader title={m.settings_automation_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#if !data.forbidden && data.summary}{data.summary}{/if}
  {/snippet}
  {#snippet actions()}
    {#if !data.forbidden}
      <a class="v2-btn v2-btn-primary" href={resolve(asInternalPath('/settings/automation/new'))}
        ><Plus />{m.settings_automation_new_rule()}</a
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-bottom:32px">
    {#if data.forbidden}
      <AdminsOnly />
    {:else}
      {#if form?.error}
        <p class="v2-error" role="alert" style="margin:0 0 12px">{form.error}</p>
      {/if}

      {#each paused as r (r.id)}
        <div style="margin-bottom:12px">
          {#if pausedByModule(r, data.modules)}
            <NextAction
              label={m.settings_automation_paused_label()}
              tone="rust"
              text={modulePausedNote(r)}
              action="m.settings_automation_open_modules()"
              href="/settings/apps"
            />
          {:else}
            <NextAction
              label={m.settings_automation_paused_label()}
              tone="rust"
              text={m.settings_automation_paused_note({ name: r.name, status: r.status_text })}
              action={m.settings_automation_open_rule()}
              href={`/settings/automation/${r.id}`}
            />
          {/if}
        </div>
      {/each}

      {#if !rules.length}
        <EmptyState
          title={m.settings_automation_empty_title()}
          body={m.settings_automation_empty_body()}
        />
      {:else}
        <div class="v2-table-wrap" style="margin-left:0;margin-right:0;overflow-x:auto">
          <table class="v2-table au-table">
            <thead>
              <tr>
                <th>{m.settings_automation_col_rule()}</th>
                <th>{m.settings_automation_col_when()}</th>
                <th>{m.settings_automation_col_last_7_days()}</th>
                <th>{m.settings_automation_col_state()}</th>
                <th><span class="au-sr">{m.settings_automation_col_order()}</span></th>
              </tr>
            </thead>
            <tbody>
              {#each rules as r, i (r.id)}
                {@const st = statusOf(r)}
                {@const note = statusNote(r)}
                <tr>
                  <td data-m="title">
                    <a
                      class="v2-row-link au-tap"
                      href={resolve(asInternalPath(`/settings/automation/${r.id}`))}
                    >
                      <div class="v2-table-primary">{r.name}</div>
                      <div class="v2-table-secondary">
                        {objectOf(data.catalogue, r.object_key)?.label ??
                          OBJECT_LABELS[r.object_key] ??
                          r.object_key}
                      </div>
                      {#if note}
                        <div class="v2-table-secondary au-status-narrow">{note}</div>
                      {/if}
                    </a>
                  </td>
                  <td data-m="meta">{triggerSentence(r, data.catalogue)}</td>
                  <td data-m="meta">{runsLabel(r)}</td>
                  <td data-m="tag">
                    <Pill tone={st.tone}>{st.label}</Pill>
                    {#if note}
                      <div class="v2-table-secondary au-status-wide">{note}</div>
                    {/if}
                  </td>
                  <td class="au-order-cell">
                    <div class="au-order">
                      {#each ['up', 'down'] as direction (direction)}
                        <form method="POST" action="?/move" use:enhance>
                          <input type="hidden" name="id" value={r.id} />
                          <input type="hidden" name="direction" value={direction} />
                          <button
                            class="v2-btn v2-btn-sm au-icon"
                            type="submit"
                            aria-label={direction === 'up'
                              ? m.settings_automation_move_up({ name: r.name })
                              : m.settings_automation_move_down({ name: r.name })}
                            disabled={direction === 'up' ? i === 0 : i === rules.length - 1}
                          >
                            {#if direction === 'up'}<ArrowUp size={14} />{:else}<ArrowDown
                                size={14}
                              />{/if}
                          </button>
                        </form>
                      {/each}
                    </div>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    {/if}
  </div>
</div>

<style>
  .au-sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }
  .au-tap {
    display: block;
    min-height: 32px;
  }
  .au-status-narrow {
    display: none;
  }
  .au-table :global(td) {
    white-space: normal;
  }
  .au-status-wide {
    max-width: 200px;
    padding: 4px 0;
  }
  .au-order {
    display: flex;
    gap: 6px;
    justify-content: flex-end;
  }
  .au-icon {
    min-width: 44px;
    min-height: 44px;
    justify-content: center;
  }
  @media (max-width: 768px) {
    /* The tag cell is pinned to the row's corner, so its note moves under the name. */
    .au-status-wide {
      display: none;
    }
    .au-status-narrow {
      display: block;
    }
    .au-tap {
      min-height: 44px;
    }
    .au-order {
      justify-content: flex-start;
    }
    .au-order-cell {
      display: block;
      margin: 8px 0 0;
    }
  }
</style>
