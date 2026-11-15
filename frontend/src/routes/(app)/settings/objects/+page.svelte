<script>
  /**
   * Custom objects: org-defined record types. Admins add and manage them
   * here; members reach the records from the sidebar.
   */
  import { resolve } from '$app/paths';
  import { asInternalPath } from '#lib/utils/paths.js';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import SettingsFormPanel from '#lib/v2/components/SettingsFormPanel.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import { suggestKey } from '#lib/v2/custom-objects.js';
  import { count } from '#lib/v2/format.js';
  import { Plus } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';

  const OBJECT_LIMIT = 20;

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();

  let creating = $state(false);
  let label = $state('');
  let key = $state('');
  let keyEdited = $state(false);

  let objects = $derived(data.answer.objects);
  let archived = $derived(objects.filter((/** @type {any} */ o) => !o.is_active).length);
  let canAdd = $derived(data.can_edit && data.answer.has_custom_objects);

  let subParts = $derived(messageParts(m.settings_objects_sub({ count: slot('count') })));

  function openCreate() {
    label = '';
    key = '';
    keyEdited = false;
    creating = true;
  }

  /** @param {Event} event */
  function onLabel(event) {
    label = /** @type {HTMLInputElement} */ (event.currentTarget).value;
    if (!keyEdited) key = suggestKey(label, 28);
  }
</script>

<PageHeader title={m.settings_objects_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#each subParts as p, i (i)}{#if p.key}<span class="v2-num"
          >{count(objects.length - archived)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    {#if canAdd && !creating}
      <button class="v2-btn v2-btn-primary" onclick={openCreate}
        ><Plus />{m.settings_objects_new_button()}</button
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-pad" style="padding-top:16px;flex:none">
  <div class="v2-stats">
    <StatCard
      label={m.settings_objects_stat_active()}
      value={count(objects.length - archived)}
      tone="ink"
    />
    <StatCard label={m.settings_objects_stat_archived()} value={count(archived)} tone="slate" />
    <StatCard
      label={m.settings_objects_stat_used()}
      value={count(objects.length)}
      tone="slate"
      detail={m.settings_objects_stat_used_detail({ limit: OBJECT_LIMIT })}
    />
  </div>
</div>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-bottom:32px">
    {#if data.can_edit && !data.answer.has_custom_objects}
      <p class="v2-sub" style="font-size:12.5px;margin:0 0 16px;max-width:66ch">
        {m.settings_objects_no_plan()}
      </p>
    {/if}

    {#if creating && canAdd}
      <SettingsFormPanel
        title={m.settings_objects_new_title()}
        action="?/create"
        error={form?.create?.error}
        submitLabel={m.settings_objects_add_button()}
        oncancel={() => (creating = false)}
        ondone={() => (creating = false)}
      >
        {#snippet fields()}
          <div class="v2-field">
            <label for="o-label">{m.settings_objects_label_singular()}</label>
            <input
              id="o-label"
              class="v2-input"
              name="label"
              maxlength="64"
              required
              placeholder={m.settings_objects_label_placeholder()}
              value={label}
              oninput={onLabel}
            />
          </div>
          <div class="v2-field">
            <label for="o-plural">{m.settings_objects_label_plural()}</label>
            <input
              id="o-plural"
              class="v2-input"
              name="label_plural"
              maxlength="64"
              required
              placeholder={m.settings_objects_plural_placeholder()}
            />
          </div>
          <div class="v2-field">
            <label for="o-key">{m.settings_objects_key_label()}</label>
            <input
              id="o-key"
              class="v2-input"
              name="key"
              maxlength="28"
              pattern={'[a-z][a-z0-9_]{1,27}'}
              required
              placeholder="property"
              bind:value={key}
              oninput={() => (keyEdited = true)}
            />
            <p class="v2-hint">
              {m.settings_objects_key_hint()}
            </p>
          </div>
          <div class="v2-field">
            <label for="o-name-label">{m.settings_objects_name_label_label()}</label>
            <input
              id="o-name-label"
              class="v2-input"
              name="name_label"
              maxlength="64"
              placeholder={m.settings_objects_name()}
            />
          </div>
          <div class="v2-field v2-sfp-wide">
            <label for="o-desc">{m.settings_objects_description_label()}</label>
            <textarea id="o-desc" class="v2-input" name="description" rows="2"></textarea>
          </div>
          <fieldset class="v2-field v2-sfp-wide" style="border:0;padding:0;margin:0">
            <legend class="v2-label" style="padding:0">{m.settings_objects_access_legend()}</legend>
            <label class="o-choice">
              <input type="radio" name="record_access" value="own" checked />
              {m.settings_objects_access_own()}
            </label>
            <label class="o-choice">
              <input type="radio" name="record_access" value="everyone" />
              {m.settings_objects_access_everyone()}
            </label>
          </fieldset>
        {/snippet}
      </SettingsFormPanel>
    {/if}

    {#if !objects.length}
      <EmptyState title={m.settings_objects_empty_title()} body={m.settings_objects_empty_body()} />
    {:else}
      <div class="v2-table-wrap" style="margin-left:0;margin-right:0">
        <table class="v2-table">
          <thead>
            <tr>
              <th>{m.settings_objects_col_object()}</th>
              <th>{m.settings_objects_col_status()}</th>
              <th>{m.settings_objects_col_visible()}</th>
              <th>{m.settings_objects_col_key()}</th>
            </tr>
          </thead>
          <tbody>
            {#each objects as o (o.key)}
              <tr style="opacity:{o.is_active ? 1 : 0.7}">
                <td data-m="title">
                  <a
                    class="v2-row-link o-tap"
                    href={resolve(asInternalPath(`/settings/objects/${o.key}`))}
                  >
                    <div class="v2-table-primary">{o.label_plural}</div>
                    {#if o.description}
                      <div class="v2-table-secondary">{o.description}</div>
                    {/if}
                  </a>
                </td>
                <td data-m="tag">
                  {#if !o.is_active}<Pill tone="slate">{m.settings_objects_stat_archived()}</Pill
                    >{/if}
                </td>
                <td data-m="meta"
                  >{o.record_access === 'everyone'
                    ? m.settings_objects_visible_everyone()
                    : m.settings_objects_visible_involved()}</td
                >
                <td data-m="meta"><code class="o-key">{o.key}</code></td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </div>
</div>

<style>
  .o-choice {
    display: flex;
    gap: 8px;
    align-items: center;
    font-weight: 400;
    min-height: 32px;
  }
  .o-key {
    font-family: var(--v2-mono);
    font-size: 11px;
    color: var(--v2-slate);
  }
  .o-tap {
    display: block;
    min-height: 32px;
  }

  @media (max-width: 768px) {
    .o-choice,
    .o-tap {
      min-height: 44px;
    }
  }
</style>
