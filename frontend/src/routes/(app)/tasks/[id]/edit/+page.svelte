<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * Editing a task.
   *
   * Same single "attached to" question as the new-task form, plus the two
   * hidden originals that let the save tell a real change from a re-send.
   * See the action for why that distinction matters here.
   */
  import RecordFieldInputs from '#lib/v2/components/RecordFieldInputs.svelte';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import { enhance } from '$app/forms';
  import { untrack } from 'svelte';
  import { ChevronRight } from '@lucide/svelte';
  import { isOn } from '#lib/v2/modules.js';
  import { m } from '#lib/paraglide/messages.js';
  import {
    parentKinds,
    taskPriorityLabel,
    taskStatusLabel,
    TASK_PRIORITY_CODES,
    TASK_STATUS_CODES
  } from '../../labels.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  let kinds = $derived(
    parentKinds().filter(
      (k) => !k.module || isOn(data.modules, k.module) || k.key === data.form.parent_kind
    )
  );

  let values = $derived(form?.values ?? data.form);
  let kind = $state(untrack(() => form?.values?.parent_kind ?? data.form.parent_kind ?? ''));
  let options = $derived(kind ? (data.parents[kind] ?? []) : []);
  let currentId = $derived(form?.values?.parent_id ?? data.form.parent_id ?? '');
</script>

<PageHeader title={m.tasks_edit_title()} record center width="62ch">
  {#snippet crumb()}
    <a href={resolve('tasks')}>{m.tasks_title()}</a>
    <ChevronRight size={12} />
    <a href={resolve(`tasks/${data.task.id}`)}>{data.task.title}</a>
    <ChevronRight size={12} />
    <span>{m.common_edit()}</span>
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <form
    method="POST"
    action="?/save"
    use:enhance
    class="v2-pad"
    style="padding-top:18px;padding-bottom:36px;max-width:62ch;margin-left:auto;margin-right:auto"
  >
    {#if form?.error}
      <p style="color:var(--v2-rust);font-size:12.5px;margin:0 0 14px" role="alert">{form.error}</p>
    {/if}

    <input type="hidden" name="parent_kind_original" value={data.form.parent_kind} />
    <input type="hidden" name="parent_id_original" value={data.form.parent_id} />

    <label class="v2-field">
      <span class="v2-label">{m.tasks_field_task()}</span>
      <input class="v2-input" name="title" required maxlength="200" value={values.title ?? ''} />
    </label>

    <div style="display:flex;gap:12px;flex-wrap:wrap">
      <label class="v2-field" style="flex:1;min-width:150px">
        <span class="v2-label">{m.common_priority()}</span>
        <select class="v2-input" name="priority" value={values.priority ?? 'Medium'}>
          {#each TASK_PRIORITY_CODES as code (code)}
            <option value={code}>{taskPriorityLabel(code)}</option>
          {/each}
        </select>
      </label>
      <label class="v2-field" style="flex:1;min-width:150px">
        <span class="v2-label">{m.common_status()}</span>
        <select class="v2-input" name="status" value={values.status ?? 'New'}>
          {#each TASK_STATUS_CODES as code (code)}
            <option value={code}>{taskStatusLabel(code)}</option>
          {/each}
        </select>
      </label>
      <label class="v2-field" style="flex:1;min-width:150px">
        <span class="v2-label">{m.tasks_field_due()}</span>
        <input class="v2-input" type="date" name="due_date" value={values.due_date ?? ''} />
      </label>
    </div>

    <label class="v2-field">
      <span class="v2-label">{m.tasks_field_attached()}</span>
      <select class="v2-input" name="parent_kind" bind:value={kind}>
        {#each kinds as k (k.key)}
          <option value={k.key}>{k.label}</option>
        {/each}
      </select>
    </label>

    {#if kind}
      <label class="v2-field">
        <span class="v2-label">{m.tasks_field_which()}</span>
        <select class="v2-input" name="parent_{kind}" required>
          <option value="">{m.tasks_form_choose()}</option>
          {#each options as option (option.id)}
            <option value={option.id} selected={currentId === option.id}>{option.name}</option>
          {/each}
        </select>
      </label>
    {/if}

    <label class="v2-field">
      <span class="v2-label">{m.tasks_field_assign()}</span>
      <select
        class="v2-input"
        name="assigned_to"
        multiple
        size={Math.min(data.owners.length || 1, 5)}
      >
        {#each data.owners as person (person.id)}
          <option value={person.id} selected={data.task.assigned_ids.includes(person.id)}>
            {person.name}
          </option>
        {/each}
      </select>
      <span class="v2-sub" style="font-size:11.5px">
        {m.tasks_form_assign_hint_edit()}
      </span>
    </label>

    <label class="v2-field">
      <span class="v2-label">{m.tasks_field_note()}</span>
      <textarea class="v2-input" name="description" rows="4">{values.description ?? ''}</textarea>
    </label>

    <RecordFieldInputs
      fields={data.customFields ?? []}
      typed={form?.values?.custom_fields}
      errors={form?.fieldErrors}
      heading={m.common_details()}
    />

    <div style="display:flex;gap:9px;margin-top:6px">
      <button class="v2-btn v2-btn-primary" type="submit">{m.common_save()}</button>
      <a class="v2-btn" href={resolve(`tasks/${data.task.id}`)}>{m.common_cancel()}</a>
    </div>
  </form>
</div>
