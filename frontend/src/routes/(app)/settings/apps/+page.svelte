<script lang="ts">
  /**
   * Settings › Apps: industry apps to install, update and remove, then the
   * modules (switched off and ordered as before), then sample data. Install,
   * Update and Remove open a confirmation built from the server's preview;
   * the apps section is hidden on an API without apps. Forms use plain
   * `use:enhance`, so the shell reloads and the menus change at once.
   */
  import { enhance, type SubmitFunction } from '$app/forms';
  import { resolve } from '$app/paths';
  import { ArrowDown, ArrowUp, Boxes, Trash2 } from '@lucide/svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import KeyReveal from '#lib/v2/components/KeyReveal.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import { updateLine } from '#lib/v2/apps.js';
  import { replaceSentence } from '#lib/v2/connected-apps.js';
  import { removeSentence } from '#lib/v2/private-apps.js';
  import { shortDate } from '#lib/v2/format.js';
  import { labelOf, type ModuleRow } from '#lib/v2/modules.js';
  import { asInternalPath } from '#lib/utils/paths.js';
  import type { App } from '#lib/server/v2/apps.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  const GROUPS = [
    {
      key: 'sell',
      get label() {
        return m.settings_modules_group_sell();
      }
    },
    {
      key: 'serve',
      get label() {
        return m.settings_modules_group_serve();
      }
    },
    {
      key: 'bill',
      get label() {
        return m.settings_modules_group_bill();
      }
    }
  ];

  let rows: ModuleRow[] = $derived(data.modules ?? []);

  let groups = $derived(
    GROUPS.map((g) => ({
      key: g.key,
      label: g.label,
      rows: rows.filter((r) => r.group === g.key)
    })).filter((g) => g.rows.length)
  );

  let errors = $derived(Array.isArray(form?.errors) ? form.errors : []);
  let formsLink = $derived(form?.key === 'leads' || form?.key === 'tickets');
  let mailboxLink = $derived(form?.key === 'tickets');
  // Shown under the row it is about, so a phone user sees it where they tapped.
  let refusedKey = $derived(rows.some((r) => r.key === form?.key) ? form?.key : null);

  let apps = $derived(data.apps?.apps ?? []);
  let confirm = $derived(data.confirm ?? null);
  let doneApp = $derived(apps.find((a) => a.id === data.done?.app) ?? null);
  let busy = $state(false);
  let privateOffered = $derived(data.privateApps?.offered === true && !data.privateApps.forbidden);
  let mine = $derived(data.privateApps?.offered ? data.privateApps.apps : []);
  let uploadErrors = $derived(
    form && 'uploadErrors' in form && form.uploadErrors
      ? Object.entries(form.uploadErrors as Record<string, string[]>)
      : []
  );
  const uploadPage = (id: string) => `/settings/apps/uploads/${encodeURIComponent(id)}`;
  let confirmingClear = $state(false);

  function doneLine(action: string, name: string) {
    if (action === 'install') return m.settings_apps_done_install({ name });
    if (action === 'upgrade') return m.settings_apps_done_upgrade({ name });
    return m.settings_apps_done_remove({ name });
  }
  function verb(action: string) {
    if (action === 'install') return m.settings_apps_install();
    if (action === 'upgrade') return m.settings_apps_update();
    return m.settings_apps_remove();
  }
  function confirmTitle(action: string, name: string) {
    if (action === 'install') return m.settings_apps_confirm_install({ name });
    if (action === 'upgrade') return m.settings_apps_confirm_upgrade({ name });
    return m.settings_apps_confirm_remove({ name });
  }
  function nothingTo(action: string) {
    if (action === 'install') return m.settings_apps_nothing_install();
    if (action === 'upgrade') return m.settings_apps_nothing_upgrade();
    return m.settings_apps_nothing_remove();
  }

  function statusLine(app: App) {
    if (app.status === 'removed') return m.settings_apps_status_removed();
    if (app.status !== 'installed') return '';
    const when = app.installedAt ? shortDate(app.installedAt) : '';
    const who = app.installedBy ?? '';
    if (when && who) return m.settings_apps_status_installed_when_who({ when, who });
    if (when) return m.settings_apps_status_installed_when({ when });
    if (who) return m.settings_apps_status_installed_who({ who });
    return m.settings_apps_status_installed();
  }

  const ask = (id: string, action: string) =>
    `/settings/apps?app=${encodeURIComponent(id)}&do=${action}`;

  const submitting: SubmitFunction = () => {
    busy = true;
    return async ({ update }) => {
      await update();
      busy = false;
    };
  };

  const clearSubmit: SubmitFunction = () => {
    busy = true;
    return async ({ update, result }) => {
      await update();
      busy = false;
      if (result?.type === 'success') confirmingClear = false;
    };
  };

  function needOff(row: ModuleRow) {
    const need = row.needs ? rows.find((r) => r.key === row.needs) : null;
    return need ? !need.available : false;
  }
</script>

<PageHeader title={m.settings_apps_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {m.settings_apps_sub()}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    {#if data.forbidden}
      <NextAction label={m.settings_apps_admins_only()} text={m.settings_apps_forbidden()} />
    {:else}
      {#if data.done && doneApp}
        <div class="app-done" role="status">
          {doneLine(data.done.action, doneApp.name)}
          {#if data.done.action === 'remove'}
            {m.settings_apps_done_remove_note()}
          {/if}
        </div>
      {/if}

      {#if form?.appError && confirm?.app !== form?.app}
        <p class="v2-error" role="alert" style="margin:0 0 14px">{form.appError}</p>
      {/if}

      {#if data.apps?.state !== 'absent'}
        <h2 class="app-h">{m.settings_apps_industry_heading()}</h2>
        {#if data.apps?.state === 'failed'}
          <div class="v2-card app-note">{m.settings_apps_load_failed()}</div>
        {:else if apps.length === 0}
          <div class="v2-card app-note">{m.settings_apps_none_available()}</div>
        {:else}
          <div class="v2-card" style="overflow:hidden;margin-bottom:22px">
            {#each apps as app (app.id)}
              {@const open = confirm?.app === app.id ? confirm : null}
              <div class="mod-item">
                <div class="mod-row">
                  <div class="mod-body">
                    <div class="mod-title">
                      <b>{app.name}</b>
                      {#if app.status === 'installed'}
                        <Pill tone="moss"
                          >{app.installedVersion
                            ? m.settings_apps_pill_installed_version({
                                version: app.installedVersion
                              })
                            : m.settings_apps_pill_installed()}</Pill
                        >
                      {:else if app.status === 'removed'}
                        <Pill tone="slate">{m.settings_apps_pill_removed()}</Pill>
                      {/if}
                    </div>
                    <span class="v2-sub" style="font-size:11.5px">{app.description}</span>
                    {#if statusLine(app)}
                      <span class="v2-sub" style="font-size:11.5px">{statusLine(app)}</span>
                    {/if}
                    {#if app.status === 'installed' && app.updateAvailable}
                      <span class="v2-sub app-update">
                        {updateLine(app)}
                      </span>
                    {/if}
                    {#if app.status === 'installed' && app.skippedModules.length}
                      <span class="v2-sub" style="font-size:11.5px">
                        {m.settings_apps_skipped_modules({
                          list: app.skippedModules
                            .map((k: string) => labelOf(data.modules, k))
                            .join(', ')
                        })}
                      </span>
                    {/if}
                  </div>
                  {#if !open}
                    <div class="mod-actions">
                      {#if app.status === 'installed'}
                        {#if app.updateAvailable}
                          <a
                            class="v2-btn v2-btn-sm app-tap"
                            href={resolve(asInternalPath(ask(app.id, 'upgrade')))}
                            >{m.settings_apps_update()}</a
                          >
                        {/if}
                        <a
                          class="v2-btn v2-btn-sm app-tap"
                          href={resolve(asInternalPath(ask(app.id, 'remove')))}
                          >{m.settings_apps_remove()}</a
                        >
                      {:else}
                        <a
                          class="v2-btn v2-btn-sm app-tap"
                          href={resolve(asInternalPath(ask(app.id, 'install')))}
                          >{m.settings_apps_install()}</a
                        >
                      {/if}
                    </div>
                  {/if}
                </div>

                {#if open}
                  <div class="app-confirm">
                    {#if open.error}
                      <p class="v2-error" role="alert" style="margin:0 0 10px">{open.error}</p>
                    {:else}
                      <div style="font-weight:600;font-size:13px;margin-bottom:6px">
                        {confirmTitle(open.action, app.name)}
                      </div>
                      {#if open.action === 'remove'}
                        <p class="v2-sub app-lede">{m.settings_apps_lede_remove()}</p>
                      {:else if open.action === 'upgrade'}
                        <p class="v2-sub app-lede">{m.settings_apps_lede_upgrade()}</p>
                      {:else}
                        <p class="v2-sub app-lede">{m.settings_apps_lede_install()}</p>
                      {/if}
                      {#each open.preview?.groups ?? [] as group (group.type)}
                        <div class="v2-label" style="margin:12px 0 4px">{group.label}</div>
                        <ul class="app-items">
                          {#each group.items as item, n (n)}
                            <li class:app-hand={item.effect === 'add_by_hand'}>
                              <span>{item.label}</span>
                              {#if item.target}<span class="v2-sub">
                                  {m.settings_apps_item_on({ target: item.target })}</span
                                >{/if}
                              <span class="v2-sub app-effect">{item.effectLabel}</span>
                            </li>
                          {/each}
                        </ul>
                      {:else}
                        <p class="v2-sub app-lede">{nothingTo(open.action)}</p>
                      {/each}
                    {/if}

                    {#if form?.appError && form?.app === app.id}
                      <p class="v2-error" role="alert" style="margin:12px 0 0">{form.appError}</p>
                    {/if}

                    <form
                      method="POST"
                      action="?/{open.action}"
                      use:enhance={submitting}
                      class="app-confirm-actions"
                    >
                      <input type="hidden" name="app" value={app.id} />
                      {#if open.action === 'install' && open.preview?.sampleData.offered}
                        <label class="app-sample">
                          <input
                            type="checkbox"
                            name="sample_data"
                            checked={open.preview.sampleData.defaultOn}
                          />
                          <span>
                            {open.preview.sampleData.records
                              ? m.settings_apps_sample_add_records({
                                  records: open.preview.sampleData.records
                                })
                              : m.settings_apps_sample_add()}
                            <span class="v2-sub" style="display:block;font-size:11.5px">
                              {m.settings_apps_sample_hint()}
                            </span>
                          </span>
                        </label>
                      {/if}
                      <div class="app-buttons">
                        {#if !open.error}
                          <button class="v2-btn v2-btn-sm v2-btn-primary" disabled={busy}>
                            {verb(open.action)}
                          </button>
                        {/if}
                        <a class="v2-btn v2-btn-sm" href={resolve(asInternalPath('/settings/apps'))}
                          >{m.common_cancel()}</a
                        >
                      </div>
                    </form>
                  </div>
                {/if}
              </div>
            {/each}
          </div>
        {/if}
      {/if}

      {#if form && 'revealed' in form && form.revealed}
        <KeyReveal
          title={m.settings_private_apps_new_key({ name: form.revealed.name })}
          secret={form.revealed.key}
        />
      {/if}
      {#if form && 'removedPrivate' in form && form.removedPrivate}
        <div class="app-done" role="status">
          {m.settings_private_apps_removed({ name: form.removedPrivate })}
        </div>
      {/if}

      {#if privateOffered}
        <h2 class="app-h">{m.settings_private_apps_heading()}</h2>
        {#if form && 'privateError' in form && form.privateError}
          <p class="v2-error" role="alert" style="margin:0 0 14px">{form.privateError}</p>
        {/if}
        {#if mine.length}
          <div class="v2-card" style="overflow:hidden;margin-bottom:14px">
            {#each mine as app (app.id)}
              <div class="mod-item">
                <div class="mod-row">
                  <div class="mod-body">
                    <div class="mod-title">
                      <b class="own-name">{app.name}</b>
                      <Pill tone={app.status === 'removed' ? 'slate' : 'moss'}>
                        {app.status === 'removed'
                          ? m.settings_private_apps_pill_removed({ version: app.version })
                          : m.settings_private_apps_pill_installed({ version: app.version })}
                      </Pill>
                    </div>
                    {#if app.description}
                      <span class="v2-sub own-text">{app.description}</span>
                    {/if}
                    <span class="v2-sub own-text">
                      {app.objects.length
                        ? m.settings_private_apps_objects({
                            list: app.objects.map((o) => o.label).join(', ')
                          })
                        : m.settings_private_apps_objects_none()}
                      {app.connection
                        ? m.settings_private_apps_holds_key()
                        : m.settings_private_apps_holds_no_key()}
                    </span>
                    {#if app.newer_upload && app.status !== 'removed'}
                      <span class="v2-sub app-update">
                        {m.settings_private_apps_waiting({ version: app.newer_upload.version })}
                      </span>
                    {/if}
                  </div>
                  <div class="mod-actions">
                    {#if app.status === 'removed'}
                      {#if app.upload_id}
                        <a
                          class="v2-btn v2-btn-sm app-tap"
                          href={resolve(asInternalPath(uploadPage(app.upload_id)))}
                          >{m.settings_private_apps_install_again()}</a
                        >
                      {/if}
                    {:else}
                      <a
                        class="v2-btn v2-btn-sm app-tap"
                        href={resolve(
                          asInternalPath(
                            app.newer_upload
                              ? uploadPage(app.newer_upload.id)
                              : '/settings/apps#upload-own'
                          )
                        )}>{m.settings_apps_update()}</a
                      >
                      {#if app.connection}
                        <ConfirmAction
                          action="?/replaceKey"
                          label={m.settings_private_apps_replace_key()}
                          confirmLabel={m.settings_private_apps_replace_key()}
                          explain={replaceSentence(app.name)}
                          hidden={{ id: app.id }}
                        />
                      {/if}
                      <ConfirmAction
                        action="?/removePrivate"
                        label={m.settings_apps_remove()}
                        confirmLabel={m.settings_apps_remove()}
                        explain={removeSentence(app.name, {
                          objects: app.objects.length > 0,
                          key: Boolean(app.connection)
                        })}
                        hidden={{ id: app.id }}
                      />
                    {/if}
                  </div>
                </div>
              </div>
            {/each}
          </div>
        {:else}
          <div class="v2-card app-note">{m.settings_private_apps_empty()}</div>
        {/if}

        <form
          id="upload-own"
          method="POST"
          action="?/upload"
          enctype="multipart/form-data"
          use:enhance={submitting}
          class="v2-card own-upload"
        >
          <div style="font-weight:600;font-size:13px">{m.settings_private_apps_upload_title()}</div>
          <p class="v2-sub app-lede">{m.settings_private_apps_upload_lede()}</p>
          <label class="v2-label" for="own-file">{m.settings_private_apps_upload_file()}</label>
          <input id="own-file" name="file" type="file" accept=".json,application/json" />
          <label class="v2-label" for="own-text">{m.settings_private_apps_upload_paste()}</label>
          <textarea id="own-text" name="manifest" rows="6" class="v2-input own-text-area"
          ></textarea>
          {#if form && 'uploadError' in form && form.uploadError}
            <p class="v2-error" role="alert" style="margin:0">{form.uploadError}</p>
          {/if}
          {#if uploadErrors.length}
            <div class="mod-errors" role="alert" style="margin:0">
              <ul>
                {#each uploadErrors as [path, messages] (path)}
                  <li><code>{path}</code>: {messages.join(' ')}</li>
                {/each}
              </ul>
            </div>
          {/if}
          <div class="app-buttons">
            <button class="v2-btn v2-btn-sm v2-btn-primary app-tap" disabled={busy}>
              {m.settings_private_apps_review()}
            </button>
          </div>
        </form>
        <div style="margin-bottom:22px"></div>
      {/if}

      <h2 class="app-h">{m.settings_modules_title()}</h2>
      {#if data.modulesFailed}
        <EmptyState
          title={m.settings_modules_failed_title()}
          body={m.settings_modules_failed_body()}
        >
          {#snippet icon()}<Boxes size={21} />{/snippet}
        </EmptyState>
      {/if}
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
        <div class="v2-label" style="margin-bottom:10px">{g.label}</div>
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

      <h2 class="app-h">{m.settings_apps_sample_heading()}</h2>
      <div class="v2-card danger">
        {#if form?.sampleError}
          <p class="v2-error" role="alert" style="margin:0;flex-basis:100%">{form.sampleError}</p>
        {/if}
        {#if confirmingClear}
          <form
            method="POST"
            action="?/clearSampleData"
            use:enhance={clearSubmit}
            style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"
          >
            <span class="v2-sub" style="font-size:12px">
              {m.settings_org_clear_confirm()}
            </span>
            <button class="v2-btn danger-btn" type="submit" disabled={busy}>
              <Trash2 size={14} />
              {m.settings_org_clear_button()}
            </button>
            <button
              class="v2-btn"
              type="button"
              disabled={busy}
              onclick={() => (confirmingClear = false)}
            >
              {m.common_cancel()}
            </button>
          </form>
        {:else if form?.cleared !== undefined}
          <span class="v2-sub" style="font-size:12.5px">
            {form.cleared
              ? m.settings_org_cleared({ count: form.cleared })
              : m.settings_org_cleared_none()}
            {#if form.retained}
              {m.settings_org_cleared_kept({ count: form.retained })}
            {/if}
          </span>
        {:else}
          <button class="v2-btn danger-btn" type="button" onclick={() => (confirmingClear = true)}>
            <Trash2 size={14} />
            {m.settings_org_clear_button()}
          </button>
          <span class="v2-sub" style="font-size:11.5px">
            {m.settings_org_clear_hint()}
          </span>
        {/if}
      </div>
    {/if}
  </div>
</div>

<style>
  .app-h {
    font-size: 14px;
    font-weight: 650;
    margin: 0 0 12px;
  }
  .app-done {
    border: 1px solid color-mix(in srgb, var(--v2-moss) 40%, var(--v2-line));
    background: color-mix(in srgb, var(--v2-moss) 8%, transparent);
    border-radius: 8px;
    padding: 12px 14px;
    margin-bottom: 18px;
    font-size: 13px;
  }
  .app-note {
    padding: 14px 16px;
    margin-bottom: 22px;
    font-size: 12.5px;
    color: var(--v2-slate);
  }
  .own-name,
  .own-text {
    overflow-wrap: anywhere;
  }
  .own-text {
    font-size: 11.5px;
  }
  .own-upload {
    padding: 14px 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .own-text-area {
    width: 100%;
    font-family: var(--v2-mono, monospace);
    font-size: 12px;
  }
  .app-update {
    font-size: 11.5px;
    color: var(--v2-clay);
  }
  .app-confirm {
    border-top: 1px solid var(--v2-line-soft);
    margin: 0 16px;
    padding: 12px 0 14px;
  }
  .app-lede {
    font-size: 12.5px;
    margin: 0;
    line-height: 1.5;
  }
  .app-items {
    margin: 0;
    padding-left: 18px;
    font-size: 12.5px;
    line-height: 1.6;
  }
  .app-items li {
    overflow-wrap: anywhere;
  }
  .app-effect {
    font-size: 11px;
  }
  .app-effect::before {
    content: ' · ';
  }
  .app-hand {
    color: var(--v2-clay);
  }
  .app-confirm-actions {
    margin-top: 14px;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .app-sample {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    font-size: 13px;
    min-height: 44px;
    cursor: pointer;
  }
  .app-sample input {
    width: 18px;
    height: 18px;
    flex: none;
    margin-top: 1px;
  }
  .app-buttons {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
  }
  .danger {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
    padding: 14px 16px;
  }
  .danger-btn {
    color: var(--v2-rust);
    border-color: color-mix(in srgb, var(--v2-rust) 32%, transparent);
  }
  .danger-btn:hover {
    background: color-mix(in srgb, var(--v2-rust) 9%, transparent);
  }
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
    .app-tap,
    .app-buttons .v2-btn {
      min-height: 44px;
      justify-content: center;
    }
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
