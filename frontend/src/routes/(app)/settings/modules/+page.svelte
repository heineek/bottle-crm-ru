<script>
  /**
   * Settings › Modules: switch the parts of BottleCRM an organization does
   * not use off and on, and order them within their group. Switching off
   * deletes nothing. Forms use plain `use:enhance`, so the shell reloads and
   * the menus change at once.
   */
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';
  import { ArrowDown, ArrowUp, Boxes } from '@lucide/svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import { labelOf } from '#lib/v2/modules.js';
  import { asInternalPath } from '#lib/utils/paths.js';
  import { m } from '#lib/paraglide/messages.js';

  /** @type {{ data: any, form?: any }} */
  let { data, form } = $props();

  const GROUPS = [
    { key: 'sell', label: () => m.settings_modules_group_sell() },
    { key: 'serve', label: () => m.settings_modules_group_serve() },
    { key: 'bill', label: () => m.settings_modules_group_bill() }
  ];

  /** @type {import('#lib/v2/modules.js').ModuleRow[]} */
  let rows = $derived(data.modules ?? []);

  let groups = $derived(
    GROUPS.map((g) => ({ ...g, rows: rows.filter((r) => r.group === g.key) })).filter(
      (g) => g.rows.length
    )
  );

  let errors = $derived(Array.isArray(form?.errors) ? form.errors : []);
  let formsLink = $derived(form?.key === 'leads' || form?.key === 'tickets');
  let mailboxLink = $derived(form?.key === 'tickets');
  // Shown under the row it is about, so a phone user sees it where they tapped.
  let refusedKey = $derived(rows.some((r) => r.key === form?.key) ? form.key : null);

  /** @param {import('#lib/v2/modules.js').ModuleRow} row */
  function needOff(row) {
    const need = row.needs ? rows.find((r) => r.key === row.needs) : null;
    return need ? !need.available : false;
  }
</script>

<PageHeader title={m.settings_modules_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {m.settings_modules_sub()}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    {#if data.failed}
      <EmptyState title={m.settings_modules_failed_title()} body={m.settings_modules_failed_body()}>
        {#snippet icon()}<Boxes size={21} />{/snippet}
      </EmptyState>
    {:else if data.forbidden}
      <NextAction label={m.common_admins_only()} text={m.settings_modules_forbidden()} />
    {:else}
      {#snippet refusal()}
        <div class="mod-errors" role="alert">
          <ul>
            {#each errors as message, n (n)}
              <li>{message}</li>
            {/each}
          </ul>
          {#if formsLink || mailboxLink}
            <p>
              {#if formsLink}<a href={resolve(asInternalPath('/settings/web-forms'))}
                  >{m.settings_modules_open_web_forms()}</a
                >{/if}
              {#if mailboxLink}<a href={resolve(asInternalPath('/settings/inbound-email'))}
                  >{m.settings_modules_open_inbound()}</a
                >{/if}
            </p>
          {/if}
        </div>
      {/snippet}

      {#if errors.length && !refusedKey}
        {@render refusal()}
      {/if}

      {#each groups as g (g.key)}
        <div class="v2-label" style="margin-bottom:10px">{g.label()}</div>
        <div class="v2-card" style="overflow:hidden;margin-bottom:22px">
          {#each g.rows as row, i (row.key)}
            {@const blocked = needOff(row)}
            <div class="mod-item">
              <div class="mod-row">
                <div class="mod-body">
                  <div class="mod-title">
                    <b>{row.label}</b>
                    <Pill tone={row.available ? 'moss' : 'slate'}
                      >{row.available ? m.settings_modules_on() : m.settings_modules_off()}</Pill
                    >
                  </div>
                  <span class="v2-sub" style="font-size:11.5px">{row.covers}</span>
                  {#if blocked && row.needs}
                    <span class="v2-sub" style="font-size:11.5px">
                      {row.enabled
                        ? m.settings_modules_needs_back({ label: labelOf(data.modules, row.needs) })
                        : m.settings_modules_needs({ label: labelOf(data.modules, row.needs) })}
                    </span>
                  {/if}
                </div>
                <div class="mod-actions">
                  {#if row.available}
                    <ConfirmAction
                      action="?/switch"
                      label={m.settings_modules_switch_off()}
                      confirmLabel={m.settings_modules_switch_off()}
                      explain={row.stops}
                      hidden={{ key: row.key, on: 'false' }}
                    />
                  {:else if !blocked}
                    <form method="POST" action="?/switch" use:enhance>
                      <input type="hidden" name="key" value={row.key} />
                      <input type="hidden" name="on" value="true" />
                      <button class="v2-btn v2-btn-sm" type="submit"
                        >{m.settings_modules_switch_on()}</button
                      >
                    </form>
                  {/if}
                  <div class="mod-order">
                    {#each ['up', 'down'] as direction (direction)}
                      <form method="POST" action="?/move" use:enhance>
                        <input type="hidden" name="key" value={row.key} />
                        <input type="hidden" name="direction" value={direction} />
                        <button
                          class="v2-btn v2-btn-sm mod-icon"
                          type="submit"
                          aria-label={direction === 'up'
                            ? m.settings_modules_move_up({ label: row.label })
                            : m.settings_modules_move_down({ label: row.label })}
                          disabled={direction === 'up' ? i === 0 : i === g.rows.length - 1}
                        >
                          {#if direction === 'up'}<ArrowUp size={14} />{:else}<ArrowDown
                              size={14}
                            />{/if}
                        </button>
                      </form>
                    {/each}
                  </div>
                </div>
              </div>
              {#if errors.length && refusedKey === row.key}
                {@render refusal()}
              {/if}
            </div>
          {/each}
        </div>
      {/each}
    {/if}
  </div>
</div>

<style>
  .mod-errors {
    border: 1px solid color-mix(in srgb, var(--v2-rust) 28%, transparent);
    background: color-mix(in srgb, var(--v2-rust) 9%, transparent);
    border-radius: 8px;
    padding: 12px 14px;
    margin-bottom: 18px;
    font-size: 13px;
  }
  .mod-errors ul {
    margin: 0;
    padding-left: 18px;
  }
  .mod-errors p {
    margin: 8px 0 0;
    display: flex;
    gap: 14px;
    flex-wrap: wrap;
  }
  /* Inside a row, the refusal sits under the row it is about. */
  .mod-item .mod-errors {
    margin: 0 16px 12px;
  }
  .mod-item {
    border-top: 1px solid var(--v2-line);
  }
  .mod-item:first-child {
    border-top: 0;
  }
  /* Wraps, so an armed Switch off, whose sentence can run longer than the
     card is wide, drops under the name instead of pushing past the edge. */
  .mod-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 10px 14px;
    padding: 12px 16px;
  }
  .mod-body {
    flex: 1 1 260px;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .mod-title {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .mod-actions {
    display: flex;
    align-items: center;
    gap: 8px;
    flex: 0 1 auto;
    min-width: 0;
    margin-left: auto;
  }
  .mod-order {
    display: flex;
    gap: 6px;
  }
  .mod-icon {
    min-width: 44px;
    min-height: 44px;
    justify-content: center;
  }
  @media (max-width: 768px) {
    .mod-row {
      flex-direction: column;
      align-items: stretch;
    }
    .mod-body {
      flex-basis: auto;
    }
    .mod-actions {
      justify-content: space-between;
      flex-wrap: wrap;
      margin-left: 0;
    }
  }
</style>
