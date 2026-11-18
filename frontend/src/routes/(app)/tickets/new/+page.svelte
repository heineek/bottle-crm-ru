<script lang="ts">
  import { m } from '#lib/paraglide/messages.js';
  import { resolve } from '$app/paths';
  /**
   * Raising a ticket.
   *
   * Deliberately short. A ticket that has just been raised has no history, no
   * closing date and nothing linked to it, so the only questions are what
   * happened, how bad it is, and who it is for.
   *
   * `?account=<id>` preselects the company, so "raise a ticket for this
   * account" arrives with the account already chosen.
   */
  import { tick, untrack } from 'svelte';
  import { enhance } from '$app/forms';
  import RecordFieldInputs from '#lib/v2/components/RecordFieldInputs.svelte';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import { ChevronRight, TriangleAlert } from '@lucide/svelte';
  import type { PageProps, SubmitFunction } from './$types';

  let { data, form: result }: PageProps = $props();

  // `untrack` so a re-render after a failed save does not throw away what the
  // person typed; `result.values` is the server's echo of the same fields.
  let form = $state(
    untrack(() => ({
      name: '',
      status: data.defaults.status,
      priority: data.defaults.priority,
      case_type: data.defaults.case_type,
      description: '',
      account: data.defaults.account ?? '',
      assigned_to: '',
      ...(result?.values ?? {})
    }))
  );
  let touched = $state<Record<string, boolean>>({});
  let submitted = $state(false);

  let errors = $derived.by(() => {
    const e: Record<string, string> = {};
    const name = form.name.trim();
    if (!name) e.name = m.tickets_new_subject_required();
    // `Case.name` is max_length=64, short for a subject line, but it is the
    // column, and a 65th character is a 400 from the serializer.
    else if (name.length > 64) e.name = m.tickets_new_subject_too_long({ length: name.length });
    return e;
  });

  let valid = $derived(Object.keys(errors).length === 0);
  const show = (field: string) => (touched[field] || submitted) && errors[field];

  const check: SubmitFunction = async ({ cancel }) => {
    submitted = true;
    if (!valid) {
      cancel();
      await tick();
      const first: HTMLElement | null = document.querySelector('[aria-invalid="true"]');
      first?.focus();
    }
  };
</script>

<PageHeader title={m.tickets_new_title()} center>
  {#snippet crumb()}
    <a href={resolve('tickets')}>{m.tickets_list_title()}</a>
    <ChevronRight size={12} />
    <span>{m.tickets_new_crumb()}</span>
  {/snippet}
  {#snippet sub()}
    {m.tickets_new_sub()}
  {/snippet}
</PageHeader>

<div class="v2-scroll v2-pad" style="padding-top:18px">
  <form class="v2-form" method="POST" action="?/create" use:enhance={check} novalidate>
    {#if result?.error}
      <div
        class="v2-next"
        style="background:color-mix(in srgb, var(--v2-rust) 9%, transparent);border-color:color-mix(in srgb, var(--v2-rust) 28%, transparent);margin-bottom:18px"
        role="alert"
      >
        <TriangleAlert size={17} style="color:var(--v2-rust);flex:none" />
        <div class="v2-next-body">
          <div style="font-weight:600">{m.tickets_new_refused()}</div>
          <div class="v2-sub" style="margin-top:2px">{result.error}</div>
        </div>
      </div>
    {/if}

    <div class="v2-field">
      <label for="f-name">{m.tickets_new_subject()}</label>
      <input
        id="f-name"
        name="name"
        class="v2-input"
        bind:value={form.name}
        onblur={() => (touched.name = true)}
        aria-invalid={show('name') ? 'true' : undefined}
      />
      {#if show('name')}
        <p class="v2-error">{errors.name}</p>
      {:else}
        <!-- Worth saying up front, because it is an unusual rule for a
             helpdesk and the refusal is otherwise baffling: two tickets in one
             organisation cannot share a subject, ignoring capitals. -->
        <p class="v2-hint">{m.tickets_new_subject_hint()}</p>
      {/if}
    </div>

    <div class="triple">
      <div class="v2-field">
        <label for="f-priority">{m.common_priority()}</label>
        <select id="f-priority" name="priority" class="v2-input" bind:value={form.priority}>
          {#each data.priorities as p (p.value)}
            <option value={p.value}>{p.label}</option>
          {/each}
        </select>
        <p class="v2-hint">{m.tickets_new_priority_hint()}</p>
      </div>
      <div class="v2-field">
        <label for="f-type">{m.tickets_new_type()}</label>
        <select id="f-type" name="case_type" class="v2-input" bind:value={form.case_type}>
          <option value="">{m.tickets_new_type_unset()}</option>
          {#each data.caseTypes as t (t.value)}
            <option value={t.value}>{t.label}</option>
          {/each}
        </select>
      </div>
      <div class="v2-field">
        <label for="f-status">{m.common_status()}</label>
        <select id="f-status" name="status" class="v2-input" bind:value={form.status}>
          {#each data.statuses as s (s.value)}
            <option value={s.value}>{s.label}</option>
          {/each}
        </select>
      </div>
    </div>

    <div class="pair">
      <div class="v2-field">
        <label for="f-account">{m.tickets_new_account()}</label>
        <select id="f-account" name="account" class="v2-input" bind:value={form.account}>
          <option value="">{m.tickets_new_account_none()}</option>
          {#each data.accounts as a (a.id)}
            <option value={a.id}>{a.name}</option>
          {/each}
        </select>
        <p class="v2-hint">{m.tickets_new_account_hint()}</p>
      </div>
      <div class="v2-field">
        <label for="f-owner">{m.tickets_new_assignee()}</label>
        <select id="f-owner" name="assigned_to" class="v2-input" bind:value={form.assigned_to}>
          <option value="">{m.tickets_new_assignee_none()}</option>
          {#each data.owners as o (o.id)}
            <option value={o.id}>{o.name}</option>
          {/each}
        </select>
        <p class="v2-hint">{m.tickets_new_assignee_hint()}</p>
      </div>
    </div>

    <div class="v2-field">
      <label for="f-contacts">{m.tickets_new_contacts()}</label>
      <select id="f-contacts" name="contacts" class="v2-input" multiple size="4">
        {#each data.contacts as c (c.id)}
          <option value={c.id}>{c.name}</option>
        {/each}
      </select>
      <p class="v2-hint">{m.tickets_new_contacts_hint()}</p>
    </div>

    <div class="v2-field">
      <label for="f-desc">{m.tickets_new_description()}</label>
      <textarea
        id="f-desc"
        name="description"
        class="v2-input"
        rows="4"
        bind:value={form.description}></textarea>
    </div>

    <RecordFieldInputs
      fields={data.customFields ?? []}
      typed={result?.values?.custom_fields}
      errors={result?.fieldErrors}
      heading="Details"
    />

    <div class="actions">
      <button class="v2-btn v2-btn-primary" type="submit">{m.tickets_new_submit()}</button>
      <a class="v2-btn" href={resolve('tickets')}>{m.common_cancel()}</a>
    </div>
  </form>
</div>

<style>
  .pair {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 14px;
  }
  .triple {
    display: grid;
    grid-template-columns: 1fr 1fr 1fr;
    gap: 14px;
  }
  .actions {
    display: flex;
    align-items: center;
    gap: 9px;
    margin-top: 22px;
    padding-bottom: 40px;
  }
  @media (max-width: 720px) {
    .pair,
    .triple {
      grid-template-columns: 1fr;
    }
  }
</style>
