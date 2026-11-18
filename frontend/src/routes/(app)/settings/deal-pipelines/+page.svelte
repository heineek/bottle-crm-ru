<script lang="ts">
  /**
   * Deal pipelines: the stages a deal moves through, and how long it may sit
   * in each before it counts as rotting.
   *
   * One pipeline's stages are on screen at a time, picked by `?pipeline=`, the
   * same param the deal board uses. Stages are reordered with up and down
   * buttons rather than by dragging: they work with a thumb at 390px and from
   * a keyboard, and each press is one small reorder the server checks.
   *
   * What a stage MEANS is its kind. Reports, goals and the invoice gate count
   * a won-kind stage as won whatever it is called, so renaming "Closed Won"
   * changes words, not numbers. The server keeps at least one open, one won
   * and one lost stage in every pipeline and refuses a kind change or a delete
   * while deals sit in the stage; this page explains, the server decides.
   *
   * A member sees the same page with no write controls (`can_edit`). The
   * backend refuses every write from them regardless.
   */
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import SettingsFormPanel from '#lib/v2/components/SettingsFormPanel.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import { count } from '#lib/v2/format.js';
  import { ArrowDown, ArrowUp, Plus } from '@lucide/svelte';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageData, PageProps } from './$types';

  let { data, form }: PageProps = $props();

  type Stage = NonNullable<PageData['pipeline']>['stages'][number];

  /** `workflow.STAGE_KINDS`. */
  const KINDS = [
    ['open', m.settings_dealpipelines_type_open()],
    ['won', m.settings_dealpipelines_type_won()],
    ['lost', m.settings_dealpipelines_type_lost()]
  ] as const;
  const KIND_LABEL = Object.fromEntries(KINDS);
  const KIND_TONE = {
    open: 'slate',
    won: 'moss',
    lost: 'rust'
  } as Record<string, 'slate' | 'moss' | 'rust'>;

  let pipeline = $derived(data.pipeline);

  // `null` closed, `'new'` adding a stage, or the stage being edited. One
  // panel, so two stages can never be open for edit at once.
  let editing = $state<null | 'new' | Stage>(null);
  let addingPipeline = $state(false);
  let renaming = $state(false);
  // The kind picked in the open stage form: rotting days only apply to open.
  let editingKind = $state('open');

  // Landing on another pipeline (picked, just created, or the default after a
  // delete) closes any open form, which belonged to the one before.
  let pipelineId = $derived(pipeline?.id);
  $effect(() => {
    void pipelineId;
    editing = null;
    renaming = false;
    addingPipeline = false;
  });

  function edit(stage: 'new' | Stage) {
    editing = stage;
    editingKind = stage === 'new' ? 'open' : stage.kind;
  }

  function rotting(s: Stage) {
    if (s.kind !== 'open') return m.settings_dealpipelines_rots_closed();
    if (!s.expected_days) return m.settings_dealpipelines_rots_never();
    return s.warning_days
      ? m.settings_dealpipelines_rots_after_warn({ days: s.expected_days, warn: s.warning_days })
      : m.settings_dealpipelines_rots_after({ days: s.expected_days });
  }
</script>

<PageHeader title={m.settings_dealpipelines_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#each messageParts(m.settings_dealpipelines_sub( { count: data.pipelines.length, shown: slot('shown') } )) as p, i (i)}{#if p.key}<span
          class="v2-num">{count(data.pipelines.length)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    {#if data.can_edit && !addingPipeline}
      <button class="v2-btn v2-btn-primary" onclick={() => (addingPipeline = true)}
        ><Plus />{m.settings_dealpipelines_new_pipeline()}</button
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    {#if addingPipeline}
      <SettingsFormPanel
        title={m.settings_dealpipelines_new_pipeline()}
        action="?/createPipeline"
        error={form?.createPipeline?.error}
        submitLabel={m.settings_dealpipelines_create_pipeline()}
        oncancel={() => (addingPipeline = false)}
        ondone={() => (addingPipeline = false)}
      >
        {#snippet fields()}
          <div class="v2-field v2-sfp-wide">
            <label for="p-name">{m.settings_dealpipelines_name_label()}</label>
            <!-- svelte-ignore a11y_autofocus -->
            <input id="p-name" class="v2-input" name="name" maxlength="100" required autofocus />
            <p class="v2-hint">
              {m.settings_dealpipelines_new_pipeline_hint()}
            </p>
          </div>
        {/snippet}
      </SettingsFormPanel>
    {/if}

    {#if data.pipelines.length > 1}
      <div class="v2-label" style="margin-bottom:10px">
        {m.settings_dealpipelines_pipelines_heading()}
      </div>
      <nav class="dp-pipelines" aria-label={m.settings_dealpipelines_pipelines_heading()}>
        {#each data.pipelines as p (p.id)}
          <a
            class="v2-btn dp-pipeline"
            href={resolve(`settings/deal-pipelines?pipeline=${p.id}`)}
            aria-current={p.id === pipeline?.id ? 'page' : undefined}
          >
            {p.name}
            {#if p.is_default}<span class="v2-sub">{m.settings_dealpipelines_default_tag()}</span
              >{/if}
          </a>
        {/each}
      </nav>
    {/if}

    {#if pipeline}
      <div class="v2-card dp-head">
        {#if renaming}
          <form
            class="dp-rename"
            method="POST"
            action="?/renamePipeline"
            use:enhance={() =>
              async ({ result, update }) => {
                await update();
                if (result.type === 'success') renaming = false;
              }}
          >
            <input type="hidden" name="id" value={pipeline.id} />
            <label class="v2-sr-only" for="p-rename"
              >{m.settings_dealpipelines_pipeline_name_label()}</label
            >
            <input
              id="p-rename"
              class="v2-input"
              name="name"
              maxlength="100"
              required
              value={pipeline.name}
            />
            <button class="v2-btn v2-btn-primary" type="submit"
              >{m.settings_dealpipelines_save()}</button
            >
            <button class="v2-btn" type="button" onclick={() => (renaming = false)}
              >{m.settings_dealpipelines_cancel()}</button
            >
          </form>
        {:else}
          <div style="flex:1;min-width:0">
            <b style="font-size:14px">{pipeline.name}</b>
            {#if pipeline.is_default}<Pill tone="slate"
                >{m.settings_dealpipelines_default_pill()}</Pill
              >{/if}
            <div class="v2-sub" style="font-size:11.5px;margin-top:3px">
              {#each messageParts(m.settings_dealpipelines_stage_count( { count: pipeline.stages.length, shown: slot('shown') } )) as p, i (i)}{#if p.key}<span
                    class="v2-num">{count(pipeline.stages.length)}</span
                  >{:else}{p.text}{/if}{/each}
              ·
              <a href={resolve(`pipeline?view=board&pipeline=${pipeline.id}`)} style="color:inherit"
                >{m.settings_dealpipelines_open_board()}</a
              >
            </div>
          </div>
          {#if data.can_edit}
            <div class="dp-actions">
              <button class="v2-btn v2-btn-sm" type="button" onclick={() => (renaming = true)}>
                {m.settings_dealpipelines_rename()}
              </button>
              {#if !pipeline.is_default}
                <ConfirmAction
                  action="?/deletePipeline"
                  label={m.settings_dealpipelines_delete()}
                  confirmLabel={m.settings_dealpipelines_delete_pipeline()}
                  explain={m.settings_dealpipelines_delete_pipeline_explain()}
                  hidden={{ id: pipeline.id }}
                />
              {/if}
            </div>
          {/if}
        {/if}
      </div>
      {#if pipeline.is_default}
        <p class="v2-sub" style="font-size:11.5px;margin:-6px 0 14px;max-width:64ch">
          {m.settings_dealpipelines_default_note()}
        </p>
      {/if}
      {#if form?.renamePipeline?.error}
        <p class="v2-error" style="margin-bottom:12px">{form.renamePipeline.error}</p>
      {/if}
      {#if form?.deletePipeline?.error}
        <p class="v2-error" style="margin-bottom:12px">{form.deletePipeline.error}</p>
      {/if}

      {#if editing}
        <!-- The snippet below loses the `if` narrowing; a const keeps it. -->
        {@const current = editing}
        <SettingsFormPanel
          title={editing === 'new'
            ? m.settings_dealpipelines_new_stage()
            : m.settings_dealpipelines_edit_stage_title({ name: editing.label })}
          action={editing === 'new' ? '?/createStage' : '?/updateStage'}
          error={form?.stage?.error}
          submitLabel={editing === 'new'
            ? m.settings_dealpipelines_add_stage()
            : m.settings_dealpipelines_save_stage()}
          oncancel={() => (editing = null)}
          ondone={() => (editing = null)}
        >
          {#snippet fields()}
            {#if current === 'new'}
              <input type="hidden" name="pipeline_id" value={pipeline.id} />
            {:else}
              <input type="hidden" name="id" value={current.id} />
            {/if}
            <div class="v2-field">
              <label for="s-label">{m.settings_dealpipelines_name_label()}</label>
              <input
                id="s-label"
                class="v2-input"
                name="label"
                maxlength="100"
                required
                value={current === 'new' ? '' : current.label}
              />
            </div>
            <div class="v2-field">
              <label for="s-kind">{m.settings_dealpipelines_kind_label()}</label>
              <select id="s-kind" class="v2-input" name="kind" bind:value={editingKind}>
                {#each KINDS as [value, label] (value)}
                  <option {value}>{label}</option>
                {/each}
              </select>
              <p class="v2-hint">
                {m.settings_dealpipelines_kind_hint()}
              </p>
            </div>
            {#if editingKind === 'open'}
              <div class="v2-field">
                <label for="s-expected">{m.settings_dealpipelines_expected_label()}</label>
                <input
                  id="s-expected"
                  class="v2-input"
                  type="number"
                  name="expected_days"
                  min="1"
                  max="3650"
                  step="1"
                  inputmode="numeric"
                  value={current === 'new' ? '' : (current.expected_days ?? '')}
                />
                <p class="v2-hint">
                  {m.settings_dealpipelines_expected_hint()}
                </p>
              </div>
              <div class="v2-field">
                <label for="s-warning">{m.settings_dealpipelines_warning_label()}</label>
                <input
                  id="s-warning"
                  class="v2-input"
                  type="number"
                  name="warning_days"
                  min="1"
                  max="3650"
                  step="1"
                  inputmode="numeric"
                  value={current === 'new' ? '' : (current.warning_days ?? '')}
                />
                <p class="v2-hint">{m.settings_dealpipelines_warning_hint()}</p>
              </div>
            {/if}
          {/snippet}
        </SettingsFormPanel>
      {/if}

      {#if form?.stageList?.error}
        <p class="v2-error" style="margin-bottom:12px">{form.stageList.error}</p>
      {/if}

      <div class="dp-stages-head">
        <div class="v2-label">{m.settings_dealpipelines_stages_heading()}</div>
        {#if data.can_edit && !editing}
          <button class="v2-btn v2-btn-sm" type="button" onclick={() => edit('new')}
            ><Plus size={13} />{m.settings_dealpipelines_add_stage()}</button
          >
        {/if}
      </div>
      <div class="v2-table-wrap">
        <table class="v2-table">
          <thead>
            <tr>
              <th>{m.settings_dealpipelines_col_stage()}</th>
              <th>{m.settings_dealpipelines_col_kind()}</th>
              <th>{m.settings_dealpipelines_col_rots()}</th>
              {#if data.can_edit}<th></th>{/if}
            </tr>
          </thead>
          <tbody>
            {#each pipeline.stages as s, i (s.id)}
              <tr>
                <td class="v2-table-primary" data-m="title">{s.label}</td>
                <td data-m="tag"
                  ><Pill tone={KIND_TONE[s.kind] ?? 'slate'}>{KIND_LABEL[s.kind]}</Pill></td
                >
                <td data-m="meta">{rotting(s)}</td>
                {#if data.can_edit}
                  <td class="dp-actions-cell">
                    <div class="dp-actions">
                      {#each ['up', 'down'] as direction (direction)}
                        <form method="POST" action="?/moveStage" use:enhance>
                          <input type="hidden" name="pipeline_id" value={pipeline.id} />
                          <input type="hidden" name="id" value={s.id} />
                          <input type="hidden" name="direction" value={direction} />
                          <button
                            class="v2-btn v2-btn-sm dp-icon"
                            type="submit"
                            aria-label={direction === 'up'
                              ? m.settings_dealpipelines_move_up({ name: s.label })
                              : m.settings_dealpipelines_move_down({ name: s.label })}
                            disabled={direction === 'up'
                              ? i === 0
                              : i === pipeline.stages.length - 1}
                          >
                            {#if direction === 'up'}<ArrowUp size={14} />{:else}<ArrowDown
                                size={14}
                              />{/if}
                          </button>
                        </form>
                      {/each}
                      <button class="v2-btn v2-btn-sm" type="button" onclick={() => edit(s)}
                        >{m.settings_dealpipelines_edit()}</button
                      >
                      <ConfirmAction
                        action="?/deleteStage"
                        label={m.settings_dealpipelines_delete()}
                        confirmLabel={m.settings_dealpipelines_delete_stage()}
                        explain={m.settings_dealpipelines_delete_stage_explain()}
                        hidden={{ id: s.id }}
                      />
                    </div>
                  </td>
                {/if}
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </div>
</div>

<style>
  .dp-pipelines {
    display: flex;
    flex-wrap: wrap;
    gap: 7px;
    margin-bottom: 18px;
  }
  .dp-pipeline[aria-current='page'] {
    border-color: var(--v2-ink);
    font-weight: 600;
  }
  .dp-head {
    display: flex;
    gap: 12px;
    align-items: center;
    flex-wrap: wrap;
    padding: 14px 16px;
    margin-bottom: 16px;
  }
  .dp-rename {
    display: flex;
    gap: 7px;
    align-items: center;
    flex-wrap: wrap;
    width: 100%;
  }
  .dp-rename .v2-input {
    flex: 1 1 200px;
  }
  .dp-actions {
    display: flex;
    gap: 6px;
    align-items: center;
    justify-content: flex-end;
    flex-wrap: wrap;
  }
  .dp-stages-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin-bottom: 10px;
  }
  @media (max-width: 768px) {
    /* Thumb-sized: the default small button is too short to hit reliably. */
    .dp-actions :global(.v2-btn),
    .dp-stages-head .v2-btn,
    .dp-pipeline,
    .dp-rename .v2-btn {
      min-height: 44px;
    }
    .dp-icon {
      min-width: 44px;
      justify-content: center;
    }
    .dp-actions {
      justify-content: flex-start;
    }
    /* Its own line under the meta run, not squeezed in beside it. */
    .dp-actions-cell {
      display: block;
      margin: 8px 0 0;
    }
  }
</style>
