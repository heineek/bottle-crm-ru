<script>
  /**
   * One custom object's settings: its names, who sees its records, and its
   * fields. Without the plan only archive, restore and delete for good are
   * offered; everything else reads as plain text. The server refuses what
   * the page hides.
   */
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';
  import { asInternalPath } from '#lib/utils/paths.js';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsFormPanel from '#lib/v2/components/SettingsFormPanel.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import { FIELD_TYPE_LABEL } from '#lib/v2/enums.js';
  import { ChevronLeft, Plus } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';

  const TYPE_LABEL = /** @type {Record<string, string>} */ ({
    ...FIELD_TYPE_LABEL,
    link: m.settings_objects_type_link()
  });

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();

  let def = $derived(data.definition);
  let plan = $derived(data.customObjects?.has_custom_objects === true);
  let canWrite = $derived(data.can_edit && plan);
  let linkTargets = $derived(/** @type {any[]} */ (data.customObjects?.link_targets ?? []));

  let editingObject = $state(false);
  // `null` when closed, `'new'` when adding, or the field being edited.
  let editing = $state(/** @type {any} */ (null));
  let fieldType = $state('text');
  let optionRows = $state(/** @type {{ value: string, label: string }[]} */ ([]));

  function openNewField() {
    editing = 'new';
    fieldType = 'text';
    optionRows = [];
  }

  /** @param {any} f */
  function openEditField(f) {
    editing = f;
    fieldType = f.field_type;
    optionRows = (f.options ?? []).map((/** @type {any} */ o) => ({
      value: o.value,
      label: o.label
    }));
  }

  /** @param {string} target */
  const targetLabel = (target) => linkTargets.find((t) => t.key === target)?.label_plural ?? target;

  let rowErrors = $derived(
    [form?.fieldOff?.error, form?.fieldOn?.error, form?.restore?.error, form?.archive?.error]
      .concat([form?.destroy?.error])
      .filter(Boolean)
  );
</script>

<PageHeader title={def.label_plural}>
  {#snippet crumb()}
    <a class="o-back" href={resolve(asInternalPath('/settings/objects'))}
      ><ChevronLeft size={13} />{m.settings_objects_back()}</a
    >
  {/snippet}
  {#snippet sub()}
    <code class="o-key">{def.key}</code>
    {#if !def.is_active}<Pill tone="slate">{m.settings_objects_stat_archived()}</Pill>{/if}
  {/snippet}
  {#snippet actions()}
    {#if data.can_edit}
      {#if def.is_active}
        <ConfirmAction
          action="?/archive"
          label={m.settings_objects_archive()}
          confirmLabel={m.settings_objects_archive()}
          explain={m.settings_objects_archive_explain()}
        />
      {:else}
        <form method="POST" action="?/restore" use:enhance>
          <button class="v2-btn" type="submit">{m.settings_objects_restore()}</button>
        </form>
        <ConfirmAction
          action="?/destroy"
          label={m.settings_objects_destroy()}
          confirmLabel={m.settings_objects_destroy()}
          explain={m.settings_objects_destroy_explain()}
        />
      {/if}
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:16px;padding-bottom:32px">
    {#each rowErrors as message (message)}
      <p class="v2-error" style="margin:0 0 12px">{message}</p>
    {/each}

    {#if data.can_edit && data.customObjects?.has_custom_objects === false}
      <p class="v2-sub" style="font-size:12.5px;margin:0 0 16px;max-width:66ch">
        {m.settings_objects_no_plan()}
      </p>
    {/if}

    {#if editingObject && canWrite}
      <SettingsFormPanel
        title={m.settings_objects_edit_title({ label: def.label })}
        action="?/update"
        error={form?.update?.error}
        submitLabel={m.settings_objects_save_button()}
        oncancel={() => (editingObject = false)}
        ondone={() => (editingObject = false)}
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
              value={def.label}
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
              value={def.label_plural}
            />
          </div>
          <div class="v2-field">
            <label for="o-name-label">{m.settings_objects_name_label_label()}</label>
            <input
              id="o-name-label"
              class="v2-input"
              name="name_label"
              maxlength="64"
              value={def.name_label ?? ''}
            />
          </div>
          <div class="v2-field v2-sfp-wide">
            <label for="o-desc">{m.settings_objects_description_label()}</label>
            <textarea id="o-desc" class="v2-input" name="description" rows="2"
              >{def.description ?? ''}</textarea
            >
          </div>
          <fieldset class="v2-field v2-sfp-wide" style="border:0;padding:0;margin:0">
            <legend class="v2-label" style="padding:0">{m.settings_objects_access_legend()}</legend>
            <label class="o-choice">
              <input
                type="radio"
                name="record_access"
                value="own"
                checked={def.record_access !== 'everyone'}
              />
              {m.settings_objects_access_own()}
            </label>
            <label class="o-choice">
              <input
                type="radio"
                name="record_access"
                value="everyone"
                checked={def.record_access === 'everyone'}
              />
              {m.settings_objects_access_everyone()}
            </label>
          </fieldset>
        {/snippet}
      </SettingsFormPanel>
    {:else}
      <div class="v2-card o-summary">
        <dl>
          <div>
            <dt class="v2-label">{m.settings_objects_name()}</dt>
            <dd>{def.label} / {def.label_plural}</dd>
          </div>
          <div>
            <dt class="v2-label">{m.settings_objects_name_called()}</dt>
            <dd>{def.name_label || m.settings_objects_name()}</dd>
          </div>
          <div>
            <dt class="v2-label">{m.settings_objects_access_legend()}</dt>
            <dd>
              {def.record_access === 'everyone'
                ? m.settings_objects_access_everyone()
                : m.settings_objects_access_own()}
            </dd>
          </div>
          {#if def.description}
            <div>
              <dt class="v2-label">{m.settings_objects_description_label()}</dt>
              <dd>{def.description}</dd>
            </div>
          {/if}
        </dl>
        {#if canWrite}
          <button class="v2-btn" type="button" onclick={() => (editingObject = true)}>
            {m.settings_objects_edit_button()}
          </button>
        {/if}
      </div>
    {/if}

    <div class="o-fields-head">
      <h2 class="v2-label" style="margin:0">{m.settings_objects_fields_heading()}</h2>
      {#if canWrite && !editing}
        <button class="v2-btn v2-btn-sm o-add" type="button" onclick={openNewField}>
          <Plus />{m.settings_objects_new_field()}
        </button>
      {/if}
    </div>

    {#if editing && canWrite}
      <SettingsFormPanel
        title={editing === 'new'
          ? m.settings_objects_new_field()
          : m.settings_objects_edit_field_title({ label: editing.label })}
        action={editing === 'new' ? '?/createField' : '?/updateField'}
        error={editing === 'new' ? form?.createField?.error : form?.updateField?.error}
        submitLabel={editing === 'new'
          ? m.settings_objects_add_field()
          : m.settings_objects_save_field()}
        oncancel={() => (editing = null)}
        ondone={() => (editing = null)}
      >
        {#snippet fields()}
          {#if editing !== 'new'}
            <input type="hidden" name="field_key" value={editing.key} />
            <input type="hidden" name="field_type" value={editing.field_type} />
          {/if}

          <div class="v2-field">
            <label for="f-label">{m.settings_objects_field_label()}</label>
            <input
              id="f-label"
              class="v2-input"
              name="label"
              maxlength="128"
              required
              value={editing === 'new' ? '' : editing.label}
            />
          </div>

          <div class="v2-field">
            <label for="f-key">{m.settings_objects_key_label()}</label>
            {#if editing === 'new'}
              <input
                id="f-key"
                class="v2-input"
                name="key"
                maxlength="64"
                pattern="[a-z][a-z0-9_]*"
                required
                placeholder="price"
              />
              <p class="v2-hint">
                {m.settings_objects_key_hint()}
              </p>
            {:else}
              <code class="o-key">{editing.key}</code>
              <p class="v2-hint">{m.settings_objects_fixed()}</p>
            {/if}
          </div>

          <div class="v2-field">
            <label for="f-type">{m.settings_objects_type_label()}</label>
            {#if editing === 'new'}
              <select id="f-type" class="v2-input" name="field_type" bind:value={fieldType}>
                {#each Object.entries(TYPE_LABEL) as [value, label] (value)}
                  <option {value}>{label}</option>
                {/each}
              </select>
            {:else}
              <div style="font-size:13px">{TYPE_LABEL[editing.field_type]}</div>
              <p class="v2-hint">{m.settings_objects_fixed()}</p>
            {/if}
          </div>

          {#if fieldType === 'link'}
            {#if editing === 'new'}
              <div class="v2-field">
                <label for="f-target">{m.settings_objects_links_to()}</label>
                <select id="f-target" class="v2-input" name="target" required>
                  {#each linkTargets as t (t.key)}
                    <option value={t.key}>{t.label_plural}</option>
                  {/each}
                </select>
              </div>
              <div class="v2-field">
                <label for="f-many">{m.settings_objects_how_many()}</label>
                <select id="f-many" class="v2-input" name="many">
                  <option value="false">{m.settings_objects_one_record()}</option>
                  <option value="true">{m.settings_objects_several_records()}</option>
                </select>
              </div>
            {:else}
              <div class="v2-field">
                <label for="f-linked">{m.settings_objects_links_to()}</label>
                <div id="f-linked" style="font-size:13px">
                  {editing.many
                    ? m.settings_objects_link_summary_many({ target: targetLabel(editing.target) })
                    : m.settings_objects_link_summary_one({ target: targetLabel(editing.target) })}
                </div>
                <p class="v2-hint">{m.settings_objects_fixed()}</p>
              </div>
            {/if}
          {/if}

          {#if fieldType === 'dropdown'}
            <div class="v2-field v2-sfp-wide">
              <label for="f-choices">{m.settings_objects_choices_label()}</label>
              {#each optionRows as row, i (i)}
                <div class="o-option">
                  <input type="hidden" name="option_value" value={row.value} />
                  <input
                    id={i === 0 ? 'f-choices' : undefined}
                    class="v2-input"
                    name="option_label"
                    bind:value={row.label}
                    required
                  />
                  <button
                    class="v2-btn v2-btn-sm"
                    type="button"
                    onclick={() => (optionRows = optionRows.filter((_, j) => j !== i))}
                  >
                    {m.settings_objects_remove()}
                  </button>
                </div>
              {/each}
              <button
                class="v2-btn v2-btn-sm o-add"
                type="button"
                style="align-self:flex-start"
                onclick={() => (optionRows = [...optionRows, { value: '', label: '' }])}
              >
                {m.settings_objects_add_choice()}
              </button>
            </div>
          {/if}

          <div class="v2-field">
            <label for="f-order">{m.settings_objects_order_label()}</label>
            <input
              id="f-order"
              class="v2-input"
              type="number"
              name="display_order"
              min="0"
              value={editing === 'new' ? '' : editing.display_order}
            />
          </div>

          {#if fieldType !== 'link'}
            <div class="v2-field">
              <label for="f-required">{m.settings_objects_required_label()}</label>
              <label class="o-choice">
                <input
                  id="f-required"
                  type="checkbox"
                  name="is_required"
                  value="true"
                  checked={editing !== 'new' && editing.is_required}
                />
                {m.settings_objects_required_hint()}
              </label>
            </div>
          {/if}
        {/snippet}
      </SettingsFormPanel>
    {/if}

    {#if !data.fields.length}
      <EmptyState
        title={m.settings_objects_fields_empty_title()}
        body={m.settings_objects_fields_empty_body()}
      />
    {:else}
      <div class="v2-card" style="overflow:hidden">
        {#each data.fields as f (f.key)}
          <div class="v2-setting o-field" style="opacity:{f.is_active ? 1 : 0.6}">
            <div class="v2-setting-body">
              <div style="display:flex;gap:7px;align-items:baseline;flex-wrap:wrap">
                <b style="display:inline">{f.label}</b>
                <code class="o-key">{f.key}</code>
              </div>
              <span class="v2-sub" style="font-size:11.5px">
                {TYPE_LABEL[f.field_type] ?? f.field_type}
                {#if f.field_type === 'link'}
                  · {f.many
                    ? m.settings_objects_link_row_many({ target: targetLabel(f.target) })
                    : m.settings_objects_link_row_one({ target: targetLabel(f.target) })}
                {/if}
                {#if f.options}
                  · {f.options.map((/** @type {any} */ o) => o.label).join(', ')}
                {/if}
              </span>
            </div>
            {#if !f.is_active}
              <Pill tone="slate">{m.settings_objects_off()}</Pill>
            {:else if f.is_required}
              <Pill tone="clay">{m.settings_objects_required_label()}</Pill>
            {/if}
            {#if canWrite}
              <div class="o-actions">
                <button class="v2-btn v2-btn-sm" type="button" onclick={() => openEditField(f)}>
                  {m.settings_objects_edit()}
                </button>
                {#if f.is_active}
                  <ConfirmAction
                    action="?/fieldOff"
                    label={m.settings_objects_turn_off()}
                    confirmLabel={m.settings_objects_turn_off()}
                    explain={m.settings_objects_turn_off_explain()}
                    hidden={{ field_key: f.key }}
                  />
                {:else}
                  <form method="POST" action="?/fieldOn" use:enhance>
                    <input type="hidden" name="field_key" value={f.key} />
                    <button class="v2-btn v2-btn-sm" type="submit"
                      >{m.settings_objects_turn_on()}</button
                    >
                  </form>
                {/if}
              </div>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>
</div>

<style>
  .o-back {
    display: inline-flex;
    align-items: center;
    gap: 2px;
    color: inherit;
    text-decoration: none;
  }
  .o-back:hover {
    color: var(--v2-ink);
    text-decoration: underline;
  }
  .o-key {
    font-family: var(--v2-mono);
    font-size: 11px;
    color: var(--v2-slate);
    background: var(--v2-hover);
    border-radius: 3px;
    padding: 1px 4px;
  }
  .o-choice {
    display: flex;
    gap: 8px;
    align-items: center;
    font-weight: 400;
    min-height: 32px;
  }
  .o-summary {
    padding: 16px 17px;
    margin-bottom: 18px;
    display: flex;
    gap: 16px;
    align-items: flex-start;
    justify-content: space-between;
  }
  .o-summary dl {
    margin: 0;
    display: grid;
    gap: 10px;
    min-width: 0;
  }
  .o-summary dd {
    margin: 2px 0 0;
    font-size: 13px;
  }
  .o-fields-head {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin: 4px 0 10px;
  }
  .o-option {
    display: flex;
    gap: 7px;
    align-items: center;
    margin-bottom: 6px;
  }
  .o-actions {
    display: flex;
    gap: 6px;
    align-items: center;
    flex: none;
  }

  @media (max-width: 768px) {
    .o-summary {
      flex-direction: column;
    }
    .o-field {
      flex-wrap: wrap;
    }
    .o-actions {
      width: 100%;
      justify-content: flex-end;
      flex-wrap: wrap;
    }
    .o-actions :global(.v2-btn),
    .o-back,
    .o-choice,
    .o-add,
    .o-option :global(.v2-btn) {
      min-height: 44px;
    }
  }
</style>
