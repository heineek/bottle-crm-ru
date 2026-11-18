<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * A new task.
   *
   * "Attached to" is one question, not four. The model allows exactly one
   * parent and now enforces it on every path, so a form with four separate
   * pickers would let somebody fill two and learn about the rule from a 400.
   * Pick the kind, then pick the record.
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
  } from '../labels.js';
  import type { TaskValues } from '#lib/server/v2/tasks.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  let kinds = $derived(parentKinds().filter((k) => !k.module || isOn(data.modules, k.module)));

  let values: Partial<TaskValues> = $derived(form?.values ?? data.prefill ?? {});
  let kind = $state(untrack(() => form?.values?.parent_kind ?? data.prefill?.parent_kind ?? ''));
  let options = $derived(kind ? (data.parents[kind] ?? []) : []);
</script>

<PageHeader title={m.tasks_new_title()} record center width="62ch">
  {#snippet crumb()}
    <a href={resolve('tasks')}>{m.tasks_title()}</a>
    <ChevronRight size={12} />
    <span>{m.tasks_new_crumb()}</span>
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <form
    method="POST"
    action="?/create"
    use:enhance
    class="v2-pad"
    style="padding-top:18px;padding-bottom:36px;max-width:62ch;margin-left:auto;margin-right:auto"
  >
    {#if form?.error}
      <p style="color:var(--v2-rust);font-size:12.5px;margin:0 0 14px" role="alert">{form.error}</p>
    {/if}

    <label class="v2-field">
      <span class="v2-label">{m.tasks_field_task()}</span>
      <input
        class="v2-input"
        name="title"
        required
        maxlength="200"
        value={values.title ?? ''}
        placeholder={m.tasks_form_title_placeholder()}
      />
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
    <p class="v2-sub" style="font-size:11.5px;margin:-6px 0 16px">
      {m.tasks_form_no_due_hint()}
    </p>

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
            <option value={option.id} selected={values[kind] === option.id}>{option.name}</option>
          {/each}
        </select>
        {#if options.length === 0}
          <span class="v2-sub" style="font-size:11.5px">{m.tasks_form_no_options()}</span>
        {/if}
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
          <option value={person.id}>{person.name}</option>
        {/each}
      </select>
      <span class="v2-sub" style="font-size:11.5px">
        {m.tasks_form_assign_hint_new()}
      </span>
    </label>

    <label class="v2-field">
      <span class="v2-label">{m.tasks_field_note()}</span>
      <textarea
        class="v2-input"
        name="description"
        rows="4"
        placeholder={m.tasks_form_note_placeholder()}>{values.description ?? ''}</textarea
      >
    </label>

    <RecordFieldInputs
      fields={data.customFields ?? []}
      typed={form?.values?.custom_fields}
      errors={form?.fieldErrors}
      heading={m.common_details()}
    />

    <div style="display:flex;gap:9px;margin-top:6px">
      <button class="v2-btn v2-btn-primary" type="submit">{m.tasks_form_create()}</button>
      <a class="v2-btn" href={resolve('tasks')}>{m.common_cancel()}</a>
    </div>
  </form>
</div>
