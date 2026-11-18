<script lang="ts">
  /**
   * Lead pipelines: the stages a lead moves through on the board.
   *
   * One pipeline's stages are on screen at a time, picked by `?pipeline=`, the
   * same control the board uses. Stages are reordered with up and down
   * buttons rather than by dragging: they work with a thumb at 390px and from
   * a keyboard, and each press is one small reorder the server checks.
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
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import { count } from '#lib/v2/format.js';
  import { LEAD_STATUS_LABEL } from '#lib/v2/enums.js';
  import { ArrowDown, ArrowUp, Columns3, Plus } from '@lucide/svelte';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageData, PageProps } from './$types';

  let { data, form }: PageProps = $props();

  type Stage = NonNullable<PageData['pipeline']>['stages'][number];

  /** `LeadStage.STAGE_TYPE_CHOICES`. */
  const STAGE_TYPES = [
    ['open', m.settings_leadpipelines_type_open()],
    ['won', m.settings_leadpipelines_type_won()],
    ['lost', m.settings_leadpipelines_type_lost()]
  ] as const;
  const TYPE_LABEL = Object.fromEntries(STAGE_TYPES);
  const TYPE_TONE = {
    open: 'slate',
    won: 'moss',
    lost: 'rust'
  } as Record<string, 'slate' | 'moss' | 'rust'>;

  /**
   * The statuses a stage may map to. "converted" is not offered: the board
   * refuses every move into a stage mapped to it, and the API refuses a new
   * mapping to it. A stage that already carries it keeps an option for it
   * below, because a select with no matching option would quietly submit
   * "None" on an unrelated edit.
   */
  const STAGE_STATUSES = ['assigned', 'in process', 'recycled', 'closed'];

  const statusLabel = (s: string) => (LEAD_STATUS_LABEL as Record<string, string>)[s] ?? s;

  let pipeline = $derived(data.pipeline);

  // `null` closed, `'new'` adding a stage, or the stage being edited. One
  // panel, so two stages can never be open for edit at once.
  let editing = $state<null | 'new' | Stage>(null);
  let addingPipeline = $state(false);
  let renaming = $state(false);

  // Landing on another pipeline (picked, just created, or the next one after
  // a delete) closes any open form, which belonged to the one before.
  let pipelineId = $derived(pipeline?.id);
  $effect(() => {
    void pipelineId;
    editing = null;
    renaming = false;
    addingPipeline = false;
  });

  let stageOptions = $derived(
    editing &&
      editing !== 'new' &&
      editing.mapsToStatus &&
      !STAGE_STATUSES.includes(editing.mapsToStatus)
      ? [...STAGE_STATUSES, editing.mapsToStatus]
      : STAGE_STATUSES
  );
</script>

<PageHeader title={m.settings_leadpipelines_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#each messageParts(m.settings_leadpipelines_sub( { count: data.pipelines.length, shown: slot('shown') } )) as p, i (i)}{#if p.key}<span
          class="v2-num">{count(data.pipelines.length)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    {#if data.can_edit && !addingPipeline}
      <button class="v2-btn v2-btn-primary" onclick={() => (addingPipeline = true)}
        ><Plus />{m.settings_leadpipelines_new_pipeline()}</button
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    {#if addingPipeline}
      <SettingsFormPanel
        title={m.settings_leadpipelines_new_pipeline()}
        action="?/createPipeline"
        error={form?.createPipeline?.error}
        submitLabel={m.settings_leadpipelines_create_pipeline()}
        oncancel={() => (addingPipeline = false)}
        ondone={() => (addingPipeline = false)}
      >
        {#snippet fields()}
          <div class="v2-field v2-sfp-wide">
            <label for="p-name">{m.settings_leadpipelines_name_label()}</label>
            <!-- svelte-ignore a11y_autofocus -->
            <input id="p-name" class="v2-input" name="name" maxlength="255" required autofocus />
            <p class="v2-hint">
              {m.settings_leadpipelines_new_pipeline_hint()}
            </p>
          </div>
        {/snippet}
      </SettingsFormPanel>
    {/if}

    {#if data.pipelines.length === 0}
      <EmptyState
        title={m.settings_leadpipelines_empty_title()}
        body={data.can_edit
          ? m.settings_leadpipelines_empty_body_admin()
          : m.settings_leadpipelines_empty_body_member()}
      >
        {#snippet icon()}<Columns3 size={21} />{/snippet}
      </EmptyState>
    {:else}
      {#if data.pipelines.length > 1}
        <div class="v2-label" style="margin-bottom:10px">
          {m.settings_leadpipelines_pipelines_heading()}
        </div>
        <nav class="lp-pipelines" aria-label={m.settings_leadpipelines_pipelines_heading()}>
          {#each data.pipelines as p (p.id)}
            <a
              class="v2-btn lp-pipeline"
              href={resolve(`settings/lead-pipelines?pipeline=${p.id}`)}
              aria-current={p.id === pipeline?.id ? 'page' : undefined}
            >
              {p.name}
              <span class="v2-sub v2-num">{count(p.stageCount)}</span>
            </a>
          {/each}
        </nav>
      {/if}

      {#if pipeline}
        <div class="v2-card lp-head">
          {#if renaming}
            <form
              class="lp-rename"
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
                >{m.settings_leadpipelines_pipeline_name_label()}</label
              >
              <input
                id="p-rename"
                class="v2-input"
                name="name"
                maxlength="255"
                required
                value={pipeline.name}
              />
              <button class="v2-btn v2-btn-primary" type="submit"
                >{m.settings_leadpipelines_save()}</button
              >
              <button class="v2-btn" type="button" onclick={() => (renaming = false)}
                >{m.settings_leadpipelines_cancel()}</button
              >
            </form>
          {:else}
            <div style="flex:1;min-width:0">
              <b style="font-size:14px">{pipeline.name}</b>
              <div class="v2-sub" style="font-size:11.5px;margin-top:3px">
                {#each messageParts(m.settings_leadpipelines_stage_count( { count: pipeline.stages.length, shown: slot('shown') } )) as p, i (i)}{#if p.key}<span
                      class="v2-num">{count(pipeline.stages.length)}</span
                    >{:else}{p.text}{/if}{/each}
                ·
                {#each messageParts(m.settings_leadpipelines_lead_count_in( { count: pipeline.leadCount, shown: slot('shown') } )) as p, i (i)}{#if p.key}<span
                      class="v2-num">{count(pipeline.leadCount)}</span
                    >{:else}{p.text}{/if}{/each}
                ·
                <a href={resolve(`leads/board?pipeline=${pipeline.id}`)} style="color:inherit"
                  >{m.settings_leadpipelines_open_board()}</a
                >
              </div>
            </div>
            {#if data.can_edit}
              <div class="lp-actions">
                <button class="v2-btn v2-btn-sm" type="button" onclick={() => (renaming = true)}>
                  {m.settings_leadpipelines_rename()}
                </button>
                <ConfirmAction
                  action="?/deletePipeline"
                  label={m.settings_leadpipelines_delete()}
                  confirmLabel={m.settings_leadpipelines_delete_pipeline()}
                  explain={m.settings_leadpipelines_delete_pipeline_explain()}
                  hidden={{ id: pipeline.id }}
                />
              </div>
            {/if}
          {/if}
        </div>
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
              ? m.settings_leadpipelines_new_stage()
              : m.settings_leadpipelines_edit_stage_title({ name: editing.name })}
            action={editing === 'new' ? '?/createStage' : '?/updateStage'}
            error={form?.stage?.error}
            submitLabel={editing === 'new'
              ? m.settings_leadpipelines_add_stage()
              : m.settings_leadpipelines_save_stage()}
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
                <label for="s-name">{m.settings_leadpipelines_name_label()}</label>
                <input
                  id="s-name"
                  class="v2-input"
                  name="name"
                  maxlength="100"
                  required
                  value={current === 'new' ? '' : current.name}
                />
              </div>
              <div class="v2-field">
                <label for="s-type">{m.settings_leadpipelines_type_label()}</label>
                <select id="s-type" class="v2-input" name="stage_type">
                  {#each STAGE_TYPES as [value, label] (value)}
                    <option
                      {value}
                      selected={current === 'new' ? value === 'open' : current.stageType === value}
                      >{label}</option
                    >
                  {/each}
                </select>
              </div>
              <div class="v2-field">
                <label for="s-status">{m.settings_leadpipelines_status_label()}</label>
                <select id="s-status" class="v2-input" name="maps_to_status">
                  <option value="" selected={current === 'new' || !current.mapsToStatus}
                    >{m.settings_leadpipelines_status_keep()}</option
                  >
                  {#each stageOptions as s (s)}
                    <option value={s} selected={current !== 'new' && current.mapsToStatus === s}
                      >{statusLabel(s)}</option
                    >
                  {/each}
                </select>
                <p class="v2-hint">{m.settings_leadpipelines_status_hint()}</p>
              </div>
              <div class="v2-field">
                <label for="s-prob">{m.settings_leadpipelines_prob_label()}</label>
                <input
                  id="s-prob"
                  class="v2-input"
                  type="number"
                  name="win_probability"
                  min="0"
                  max="100"
                  step="1"
                  inputmode="numeric"
                  value={current === 'new' ? 0 : current.winProbability}
                />
                <p class="v2-hint">{m.settings_leadpipelines_prob_hint()}</p>
              </div>
            {/snippet}
          </SettingsFormPanel>
        {/if}

        {#if form?.stageList?.error}
          <p class="v2-error" style="margin-bottom:12px">{form.stageList.error}</p>
        {/if}

        <div class="lp-stages-head">
          <div class="v2-label">{m.settings_leadpipelines_stages_heading()}</div>
          {#if data.can_edit && !editing}
            <button class="v2-btn v2-btn-sm" type="button" onclick={() => (editing = 'new')}
              ><Plus size={13} />{m.settings_leadpipelines_add_stage()}</button
            >
          {/if}
        </div>
        <div class="v2-table-wrap">
          <table class="v2-table">
            <thead>
              <tr>
                <th>{m.settings_leadpipelines_col_stage()}</th>
                <th>{m.settings_leadpipelines_col_type()}</th>
                <th>{m.settings_leadpipelines_col_status()}</th>
                <th style="text-align:right">{m.settings_leadpipelines_col_win()}</th>
                <th style="text-align:right">{m.settings_leadpipelines_col_leads()}</th>
                {#if data.can_edit}<th></th>{/if}
              </tr>
            </thead>
            <tbody>
              {#each pipeline.stages as s, i (s.id)}
                <tr>
                  <td class="v2-table-primary" data-m="title">{s.name}</td>
                  <td data-m="tag"
                    ><Pill tone={TYPE_TONE[s.stageType] ?? 'slate'}
                      >{TYPE_LABEL[s.stageType] ?? s.stageType}</Pill
                    ></td
                  >
                  <td data-m="meta">{s.mapsToStatus ? statusLabel(s.mapsToStatus) : '—'}</td>
                  <td class="v2-num" style="text-align:right" data-m="meta">{s.winProbability}%</td>
                  <td class="v2-num" style="text-align:right" data-m="meta"
                    >{m.settings_leadpipelines_lead_count({
                      count: s.leadCount,
                      shown: count(s.leadCount)
                    })}</td
                  >
                  {#if data.can_edit}
                    <td class="lp-actions-cell">
                      <div class="lp-actions">
                        {#each ['up', 'down'] as direction (direction)}
                          <form method="POST" action="?/moveStage" use:enhance>
                            <input type="hidden" name="pipeline_id" value={pipeline.id} />
                            <input type="hidden" name="id" value={s.id} />
                            <input type="hidden" name="direction" value={direction} />
                            <button
                              class="v2-btn v2-btn-sm lp-icon"
                              type="submit"
                              aria-label={direction === 'up'
                                ? m.settings_leadpipelines_move_up({ name: s.name })
                                : m.settings_leadpipelines_move_down({ name: s.name })}
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
                        <button class="v2-btn v2-btn-sm" type="button" onclick={() => (editing = s)}
                          >{m.settings_leadpipelines_edit()}</button
                        >
                        <ConfirmAction
                          action="?/deleteStage"
                          label={m.settings_leadpipelines_delete()}
                          confirmLabel={m.settings_leadpipelines_delete_stage()}
                          explain={s.leadCount > 0
                            ? m.settings_leadpipelines_delete_stage_explain_busy()
                            : m.settings_leadpipelines_delete_stage_explain()}
                          hidden={{ id: s.id }}
                        />
                      </div>
                    </td>
                  {/if}
                </tr>
              {:else}
                <tr>
                  <td colspan={data.can_edit ? 6 : 5}>
                    <p class="v2-sub" style="margin:6px 0">
                      {m.settings_leadpipelines_no_stages()}
                    </p>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
        <p class="v2-sub" style="font-size:11.5px;margin-top:14px;max-width:64ch">
          {m.settings_leadpipelines_footnote()}
        </p>
      {/if}
    {/if}
  </div>
</div>

<style>
  .lp-pipelines {
    display: flex;
    flex-wrap: wrap;
    gap: 7px;
    margin-bottom: 18px;
  }
  .lp-pipeline[aria-current='page'] {
    border-color: var(--v2-ink);
    font-weight: 600;
  }
  .lp-head {
    display: flex;
    gap: 12px;
    align-items: center;
    flex-wrap: wrap;
    padding: 14px 16px;
    margin-bottom: 16px;
  }
  .lp-rename {
    display: flex;
    gap: 7px;
    align-items: center;
    flex-wrap: wrap;
    width: 100%;
  }
  .lp-rename .v2-input {
    flex: 1 1 200px;
  }
  .lp-actions {
    display: flex;
    gap: 6px;
    align-items: center;
    justify-content: flex-end;
    flex-wrap: wrap;
  }
  .lp-stages-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin-bottom: 10px;
  }
  @media (max-width: 768px) {
    /* Thumb-sized: the default small button is too short to hit reliably. */
    .lp-actions :global(.v2-btn),
    .lp-stages-head .v2-btn,
    .lp-pipeline,
    .lp-rename .v2-btn {
      min-height: 44px;
    }
    .lp-icon {
      min-width: 44px;
      justify-content: center;
    }
    .lp-actions {
      justify-content: flex-start;
    }
    /* Its own line under the meta run, not squeezed in beside it. */
    .lp-actions-cell {
      display: block;
      margin: 8px 0 0;
    }
  }
</style>
