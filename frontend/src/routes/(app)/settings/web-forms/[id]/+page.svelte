<script lang="ts">
  /**
   * One web form: the editor.
   *
   * FIVE SECTIONS, ONE SAVE
   * Fields, Behaviour, Spam, Embed and Activity all sit on this page, and the
   * first three are inside a single form posting to `?/save`. A per-section
   * save would mean three requests, three failure states, and an ordering
   * question nobody asked ("I changed the fields and the success message, why
   * did only one stick?").
   *
   * THE FIELD LIST TRAVELS AS JSON
   * Rows are added, removed and reordered in the browser, so index-derived
   * input names (`fields[3][label]`) would have to be renumbered across the
   * DOM on every move. Instead the array this component holds is serialised
   * into one hidden input at submit time. `withOrder` stamps `order` from list
   * position on the way out, and the server re-derives it from list position
   * anyway (`_write_fields` enumerates what it is given), so a client that
   * sent its own `order` could not reorder anything by lying about it.
   *
   * TWO WAYS TO REORDER, ONE IMPLEMENTATION
   * Above 768px each row has a drag handle. At or below it, the handle is
   * hidden and up/down buttons appear. Both paths call `moveField`, so they
   * cannot disagree about what a move means. Both controls are always in the
   * DOM and CSS alone decides which is usable: a JS breakpoint variable is a
   * second opinion about the viewport that can drift from the media query.
   *
   * PUBLISHING IS NOT A CHECKBOX HERE
   * It has its own endpoint, which validates the source state and the form's
   * shape. `is_published` is read-only on the update serializer, so a checkbox
   * bound to it would look like it worked and do nothing.
   *
   * THE TARGET DECIDES THE VOCABULARY
   * A lead form offers Lead columns and Lead custom fields and records a
   * source; a ticket form offers ticket fields and Case custom fields and sets
   * the ticket's priority and type. The target is chosen when the form is
   * created and is shown, not edited, here: the API refuses to change it once
   * the form has submissions, and before that a change would have to replace
   * every field on the page at once.
   */
  import { untrack } from 'svelte';
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import { count, relativeTime, shortDate } from '#lib/v2/format.js';
  import {
    CASE_PRIORITIES,
    CASE_TYPES,
    CASE_PRIORITY_LABEL,
    CASE_TYPE_LABEL
  } from '#lib/v2/enums.js';
  import { sourceOptions } from '#lib/v2/lead-sources.js';
  import { inactiveOptionLabel } from '#lib/v2/pickers.js';
  import {
    moveField,
    withOrder,
    isFieldComplete,
    hasRequiredField,
    builtinFor,
    builtinFieldLabel
  } from '#lib/v2/webform-fields.js';
  import { ChevronUp, ChevronDown, GripVertical, Plus, Trash2, Copy, Check } from '@lucide/svelte';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps, SubmitFunction } from './$types';
  import type { components } from '#lib/api-schema.js';

  type Schemas = components['schemas'];
  type Row = {
    key: number;
    source: string;
    lead_field: string;
    ticket_field: string;
    custom_field: string | null;
    label: string;
    placeholder: string;
    is_required: boolean;
  };

  let { data, form }: PageProps = $props();

  let wf = $derived(data.form);
  let canManage = $derived(data.canManage);
  let isTicket = $derived(wf.target === 'ticket');
  /** The built-in field vocabulary for this form's target. */
  let builtin = $derived(builtinFor(wf.target));

  /**
   * The editable field list, seeded from the server ONCE and owned by the
   * browser from then on. `untrack` says that is deliberate: a `$derived`
   * would throw away every keystroke the moment anything invalidated `data`.
   *
   * Rows are keyed by a client-side `key` rather than by the row's `id`,
   * because a row added here has no id until it is saved, and `{#each}` needs
   * a stable key or Svelte re-uses the wrong DOM node on a reorder.
   */
  let fields = $state(untrack(() => seed(data.form.fields ?? [])));
  let nextKey = $state(1000);

  function seed(rows: Schemas['WebFormField'][]): Row[] {
    return rows.map((row, index) => ({
      key: index,
      source: row.source,
      lead_field: row.lead_field ?? '',
      ticket_field: row.ticket_field ?? '',
      custom_field: row.custom_field ?? null,
      label: row.label ?? '',
      placeholder: row.placeholder ?? '',
      is_required: Boolean(row.is_required)
    }));
  }

  let successMode = $state(untrack(() => data.form.success_mode));
  let captchaProvider = $state(untrack(() => data.form.captcha_provider ?? ''));
  let assignmentMode = $state(untrack(() => data.form.assignment_mode ?? 'person'));
  let busy = $state(false);
  let copied = $state('');

  /**
   * Re-seed when the page starts describing a different form.
   *
   * SvelteKit re-uses this component across a `[id]` change rather than
   * remounting it, and the three `untrack`ed values above would then still
   * hold the previous form's fields. Guarded on the id so an ordinary
   * invalidation (a save, a publish) leaves the editor's own copy alone, which
   * is the whole reason it is untracked.
   */
  let loadedId = $state(untrack(() => data.form.id));
  $effect(() => {
    if (data.form.id === loadedId) return;
    loadedId = data.form.id;
    fields = seed(data.form.fields ?? []);
    successMode = data.form.success_mode;
    captchaProvider = data.form.captcha_provider ?? '';
    assignmentMode = data.form.assignment_mode ?? 'person';
  });

  let complete = $derived(fields.every(isFieldComplete));

  /**
   * What stops this form being published, said before the round trip.
   *
   * The server runs the same checks and is what actually decides; this only
   * saves someone a 400 that says the same thing. The wording is kept close to
   * the API's own so the two never read like different rules.
   *
   * The last check reads the SAVED success mode rather than the select's
   * current value, on purpose: publish acts on the stored form, so a redirect
   * URL typed but not yet saved would not be there when the server looked.
   */
  let publishBlocker = $derived.by(() => {
    if (!fields.length) return m.settings_webforms_blocker_no_fields();
    if (!hasRequiredField(fields, wf.target)) {
      return isTicket
        ? m.settings_webforms_blocker_email_ticket()
        : m.settings_webforms_blocker_email_lead();
    }
    if (!complete) return m.settings_webforms_blocker_incomplete();
    if (wf.success_mode === 'redirect' && !wf.redirect_url) {
      return m.settings_webforms_blocker_redirect();
    }
    return null;
  });

  const working: SubmitFunction = () => {
    busy = true;
    return async ({ update }) => {
      await update();
      busy = false;
    };
  };

  /** Save also reseeds the editor from whatever came back, so a row the
   *  server rejected or normalised does not linger in the browser's copy. */
  const saveSubmit: SubmitFunction = () => {
    busy = true;
    return async ({ update, result }) => {
      await update({ reset: false });
      busy = false;
      if (result?.type === 'success') fields = seed(data.form.fields ?? []);
    };
  };

  function addField() {
    fields = [
      ...fields,
      {
        key: nextKey++,
        source: builtin.source,
        lead_field: '',
        ticket_field: '',
        custom_field: null,
        label: '',
        placeholder: '',
        is_required: false
      }
    ];
  }

  function removeField(index: number) {
    fields = fields.filter((_, i) => i !== index);
  }

  /**
   * When a row's target changes and the label is still the one the previous
   * target suggested (or empty), follow it. A label the person actually typed
   * is never overwritten: guessing is a convenience, not a correction.
   */
  function pickBuiltinField(index: number, value: string) {
    const row = fields[index];
    const key = builtin.key === 'ticket_field' ? 'ticket_field' : 'lead_field';
    const wasSuggested = !row.label.trim() || row.label === builtinFieldLabel(wf.target, row[key]);
    row[key] = value;
    row.custom_field = null;
    if (wasSuggested) row.label = builtinFieldLabel(wf.target, value);
  }

  function pickCustomField(index: number, value: string) {
    const row = fields[index];
    const previous = data.customFields.find((c) => c.id === row.custom_field);
    const wasSuggested = !row.label.trim() || row.label === previous?.label;
    row.custom_field = value || null;
    row.lead_field = '';
    row.ticket_field = '';
    const picked = data.customFields.find((c) => c.id === value);
    if (wasSuggested && picked) row.label = picked.label;
  }

  // ---- drag reorder, pointer only -------------------------------------
  //
  // `dragging` holds the index being carried. It is set on dragstart and
  // cleared on dragend, so an interrupted drag (Escape, drop outside the list)
  // leaves no stuck state.
  let dragging = $state<number | null>(null);

  function onDrop(index: number) {
    if (dragging === null || dragging === index) return;
    fields = moveField(fields, dragging, index - dragging);
    dragging = null;
  }

  async function copy(text: string, which: string) {
    try {
      await navigator.clipboard.writeText(text);
      copied = which;
      setTimeout(() => (copied = ''), 1600);
    } catch {
      // Clipboard blocked (no https, or no permission). The snippet is on
      // screen to select by hand; nothing else to do and nothing worth an
      // alarm.
    }
  }

  let actionError = $derived(
    form?.save?.error ??
      form?.publish?.error ??
      form?.unpublish?.error ??
      form?.delete?.error ??
      null
  );

  // The emphasised clause is its own message, slotted into the sentence that explains it.
  let originsScript = $derived(
    messageParts(m.settings_webforms_origins_hint_script({ emphasis: slot('emphasis') }))
  );

  let submissions = $derived(data.submissions ?? []);
  let totals = $derived(data.analytics?.totals ?? null);

  const statusTone = (status: string) =>
    status === 'accepted' || status === 'accepted_duplicate' ? 'moss' : 'slate';

  const statusLabel = (status: string) =>
    ({
      accepted: isTicket
        ? m.settings_webforms_status_ticket_opened()
        : m.settings_webforms_status_lead_created(),
      accepted_duplicate: m.settings_webforms_status_merged(),
      rejected_spam: m.settings_webforms_status_rejected_spam(),
      rejected_invalid: m.settings_webforms_status_rejected_invalid(),
      rejected_captcha: m.settings_webforms_status_rejected_captcha()
    })[status] ?? status;
</script>

<PageHeader title={wf.name} record>
  {#snippet crumb()}
    <a href={resolve('settings/web-forms')}>{m.settings_webforms_title()}</a>
  {/snippet}
  {#snippet sub()}
    <Pill tone={wf.is_published ? 'moss' : 'slate'}>
      {wf.is_published ? m.settings_webforms_pill_published() : m.settings_webforms_pill_draft()}
    </Pill>
    <span style="margin-left:8px">
      {isTicket
        ? m.settings_webforms_sub_creates_tickets()
        : m.settings_webforms_sub_creates_leads()}
      {wf.is_published
        ? m.settings_webforms_sub_accepting()
        : m.settings_webforms_sub_collecting_nothing()}
    </span>
  {/snippet}
  {#snippet actions()}
    {#if canManage}
      {#if wf.is_published}
        <ConfirmAction
          action="?/unpublish"
          label={m.settings_webforms_unpublish()}
          confirmLabel={m.settings_webforms_unpublish_confirm()}
          explain={m.settings_webforms_unpublish_explain_detail()}
        />
      {:else}
        <form method="POST" action="?/publish" use:enhance={working}>
          <button class="v2-btn v2-btn-primary" disabled={busy || Boolean(publishBlocker)}>
            {m.settings_webforms_publish()}
          </button>
        </form>
      {/if}
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad wf-body">
    {#if actionError}
      <div style="margin-bottom:18px">
        <NextAction label={m.settings_webforms_error_label()} text={actionError} tone="rust" />
      </div>
    {:else if form?.saved}
      <p class="v2-sub wf-ok">{m.settings_webforms_saved()}</p>
    {/if}

    {#if !wf.is_published && publishBlocker && canManage}
      <div style="margin-bottom:18px">
        <NextAction label={m.settings_webforms_before_publish()} text={publishBlocker} />
      </div>
    {/if}

    <form method="POST" action="?/save" use:enhance={saveSubmit}>
      <!-- The whole ordered list, in one value. `withOrder` stamps `order`
           from list position; the server does the same from the array's own
           order, so this is a convenience and not the authority. -->
      <input type="hidden" name="fields" value={JSON.stringify(withOrder(fields))} />

      <!-- ============ Fields ============ -->
      <section class="wf-section">
        <div class="wf-section-head">
          <h2 class="v2-section">{m.settings_webforms_fields_title()}</h2>
          <p class="v2-sub wf-section-sub">
            {m.settings_webforms_fields_sub()}
          </p>
        </div>

        {#if !fields.length}
          <p class="v2-sub wf-empty">{m.settings_webforms_fields_empty()}</p>
        {/if}

        <ul class="wf-fields">
          {#each fields as field, i (field.key)}
            <li
              class="wf-row"
              class:is-dragging={dragging === i}
              draggable={canManage}
              ondragstart={() => (dragging = i)}
              ondragend={() => (dragging = null)}
              ondragover={(e) => e.preventDefault()}
              ondrop={(e) => {
                e.preventDefault();
                onDrop(i);
              }}
            >
              <!-- Pointer reorder. Hidden below 768px, where a drag handle
                   competes with the scroll gesture and loses. -->
              <span class="wf-drag" aria-hidden="true"><GripVertical size={15} /></span>

              <div class="wf-row-body">
                <div class="wf-row-line">
                  <label class="wf-sr" for="src-{field.key}"
                    >{m.settings_webforms_field_type()}</label
                  >
                  <select
                    id="src-{field.key}"
                    class="v2-input wf-narrow"
                    disabled={!canManage}
                    value={field.source}
                    onchange={(e) => {
                      field.source = e.currentTarget.value;
                      field.lead_field = '';
                      field.ticket_field = '';
                      field.custom_field = null;
                    }}
                  >
                    <option value={builtin.source}
                      >{isTicket
                        ? m.settings_webforms_field_type_ticket()
                        : m.settings_webforms_field_type_lead()}</option
                    >
                    <option value="custom" disabled={!data.customFields.length}>
                      {data.customFields.length
                        ? m.settings_webforms_field_type_custom()
                        : m.settings_webforms_field_type_custom_none()}
                    </option>
                  </select>

                  {#if field.source === 'custom'}
                    <label class="wf-sr" for="tgt-{field.key}"
                      >{m.settings_webforms_field_type_custom()}</label
                    >
                    <select
                      id="tgt-{field.key}"
                      class="v2-input wf-narrow"
                      disabled={!canManage}
                      value={field.custom_field ?? ''}
                      onchange={(e) => pickCustomField(i, e.currentTarget.value)}
                    >
                      <option value="">{m.settings_webforms_choose_one()}</option>
                      {#each data.customFields as c (c.id)}
                        <option value={c.id}>{c.label}</option>
                      {/each}
                    </select>
                  {:else}
                    <label class="wf-sr" for="tgt-{field.key}"
                      >{isTicket
                        ? m.settings_webforms_field_type_ticket()
                        : m.settings_webforms_field_type_lead()}</label
                    >
                    <select
                      id="tgt-{field.key}"
                      class="v2-input wf-narrow"
                      disabled={!canManage}
                      value={isTicket ? field.ticket_field : field.lead_field}
                      onchange={(e) => pickBuiltinField(i, e.currentTarget.value)}
                    >
                      <option value="">{m.settings_webforms_choose_one()}</option>
                      {#each builtin.choices as f (f.value)}
                        <option value={f.value}>{f.label}</option>
                      {/each}
                    </select>
                  {/if}
                </div>

                <div class="wf-row-line">
                  <label class="wf-sr" for="lbl-{field.key}"
                    >{m.settings_webforms_label_label()}</label
                  >
                  <input
                    id="lbl-{field.key}"
                    class="v2-input"
                    disabled={!canManage}
                    maxlength="255"
                    placeholder={m.settings_webforms_label_placeholder()}
                    bind:value={field.label}
                  />
                  <label class="wf-sr" for="ph-{field.key}"
                    >{m.settings_webforms_placeholder_label()}</label
                  >
                  <input
                    id="ph-{field.key}"
                    class="v2-input"
                    disabled={!canManage}
                    maxlength="255"
                    placeholder={m.settings_webforms_placeholder_placeholder()}
                    bind:value={field.placeholder}
                  />
                </div>

                <label class="wf-check">
                  <input type="checkbox" disabled={!canManage} bind:checked={field.is_required} />
                  {m.common_required()}
                </label>
              </div>

              {#if canManage}
                <div class="wf-row-actions">
                  <!-- Touch reorder. Shown below 768px, where the drag handle
                       is hidden. Both call `moveField`, one implementation. -->
                  <div class="wf-move">
                    <button
                      type="button"
                      class="wf-move-btn"
                      disabled={i === 0}
                      aria-label={field.label
                        ? m.settings_webforms_move_up({ name: field.label })
                        : m.settings_webforms_move_up_unnamed()}
                      onclick={() => (fields = moveField(fields, i, -1))}
                    >
                      <ChevronUp size={16} />
                    </button>
                    <button
                      type="button"
                      class="wf-move-btn"
                      disabled={i === fields.length - 1}
                      aria-label={field.label
                        ? m.settings_webforms_move_down({ name: field.label })
                        : m.settings_webforms_move_down_unnamed()}
                      onclick={() => (fields = moveField(fields, i, 1))}
                    >
                      <ChevronDown size={16} />
                    </button>
                  </div>
                  <button
                    type="button"
                    class="wf-move-btn"
                    aria-label={field.label
                      ? m.settings_webforms_remove_field({ name: field.label })
                      : m.settings_webforms_remove_field_unnamed()}
                    onclick={() => removeField(i)}
                  >
                    <Trash2 size={15} />
                  </button>
                </div>
              {/if}
            </li>
          {/each}
        </ul>

        {#if canManage}
          <button type="button" class="v2-btn v2-btn-sm wf-add" onclick={addField}>
            <Plus size={13} />{m.settings_webforms_add_field()}
          </button>
        {/if}
      </section>

      <!-- ============ Behaviour ============ -->
      <section class="wf-section">
        <div class="wf-section-head">
          <h2 class="v2-section">{m.settings_webforms_behaviour_title()}</h2>
          <p class="v2-sub wf-section-sub">
            {isTicket
              ? m.settings_webforms_behaviour_sub_ticket()
              : m.settings_webforms_behaviour_sub_lead()}
          </p>
        </div>

        <div class="wf-grid">
          <div class="v2-field">
            <label for="name">{m.common_name()}</label>
            <input
              id="name"
              name="name"
              class="v2-input"
              required
              maxlength="255"
              disabled={!canManage}
              value={wf.name}
            />
            <p class="v2-hint">{m.settings_webforms_name_hint()}</p>
          </div>

          <div class="v2-field">
            <label for="submit_button_label">{m.settings_webforms_submit_button()}</label>
            <input
              id="submit_button_label"
              name="submit_button_label"
              class="v2-input"
              maxlength="64"
              disabled={!canManage}
              value={wf.submit_button_label}
            />
          </div>

          <div class="v2-field">
            <label for="success_mode">{m.settings_webforms_success_mode_label()}</label>
            <select
              id="success_mode"
              name="success_mode"
              class="v2-input"
              disabled={!canManage}
              bind:value={successMode}
            >
              <option value="message">{m.settings_webforms_success_mode_message()}</option>
              <option value="redirect">{m.settings_webforms_success_mode_redirect()}</option>
            </select>
          </div>

          {#if successMode === 'redirect'}
            <div class="v2-field">
              <label for="redirect_url">{m.settings_webforms_redirect_url_label()}</label>
              <input
                id="redirect_url"
                name="redirect_url"
                class="v2-input"
                type="url"
                maxlength="500"
                disabled={!canManage}
                value={wf.redirect_url}
                placeholder="https://example.com/thanks"
              />
              <p class="v2-hint">
                {m.settings_webforms_redirect_hint()}
              </p>
            </div>
          {:else}
            <div class="v2-field wf-wide">
              <label for="success_message">{m.settings_webforms_success_message_label()}</label>
              <textarea
                id="success_message"
                name="success_message"
                class="v2-input"
                rows="2"
                disabled={!canManage}>{wf.success_message}</textarea
              >
            </div>
          {/if}

          {#if !isTicket}
            <div class="v2-field">
              <label for="assignment_mode">{m.settings_webforms_assignment_mode_label()}</label>
              <select
                id="assignment_mode"
                name="assignment_mode"
                class="v2-input"
                disabled={!canManage}
                bind:value={assignmentMode}
              >
                <option value="person">{m.settings_webforms_mode_person()}</option>
                <option value="rotation">{m.settings_webforms_mode_rotation()}</option>
              </select>
              <p class="v2-hint">
                {m.settings_webforms_assignment_hint()}
              </p>
            </div>
          {/if}

          <!-- Hidden rather than removed in rotation mode, so the stored person
               still travels with every save and switching back restores them. -->
          <div class="v2-field" hidden={!isTicket && assignmentMode === 'rotation'}>
            <label for="assign_to"
              >{isTicket
                ? m.settings_webforms_assign_to_ticket()
                : m.settings_webforms_assign_to_lead()}</label
            >
            <select
              id="assign_to"
              name="assign_to"
              class="v2-input"
              disabled={!canManage}
              value={wf.assign_to ?? ''}
            >
              <option value="">{m.settings_webforms_nobody()}</option>
              {#if data.missingAssignee}
                <!-- The stored assignee, deactivated since, so absent from the
                     people list. Without this option the select matches nothing
                     and saving any other change would clear the assignee. -->
                <option value={data.missingAssignee.id}>
                  {data.missingAssignee.is_active === false
                    ? inactiveOptionLabel(data.missingAssignee.name)
                    : data.missingAssignee.name}
                </option>
              {/if}
              {#each data.profiles as p (p.id)}
                <option value={p.id}>{p.name}</option>
              {/each}
            </select>
            {#if data.missingAssignee?.is_active === false}
              <p class="v2-hint">
                {isTicket
                  ? m.settings_webforms_deactivated_hint_ticket()
                  : m.settings_webforms_deactivated_hint_lead()}
              </p>
            {/if}
          </div>

          {#if !isTicket}
            <!-- Hidden rather than removed in person mode, for the same reason
                 as the person select above. -->
            <div class="v2-field" hidden={assignmentMode !== 'rotation'}>
              <label for="rotation_members">{m.settings_webforms_rotate_between()}</label>
              <select
                id="rotation_members"
                name="rotation_members"
                class="v2-input wf-multi"
                multiple
                size="4"
                disabled={!canManage}
              >
                {#each data.missingRotationMembers ?? [] as member (member.id)}
                  <!-- A stored member the people list cannot offer. Without it
                       the next save would drop them from the rotation. -->
                  <option value={member.id} selected>
                    {member.is_active === false ? inactiveOptionLabel(member.name) : member.name}
                  </option>
                {/each}
                {#each data.profiles as p (p.id)}
                  <option value={p.id} selected={wf.rotation_members?.includes(p.id)}
                    >{p.name}</option
                  >
                {/each}
              </select>
              <p class="v2-hint">
                {m.settings_webforms_rotation_hint()}
                {#if wf.assignment_mode === 'rotation'}
                  {wf.rotation_last_assigned_details
                    ? m.settings_webforms_rotation_last({
                        name:
                          wf.rotation_last_assigned_details.name ||
                          wf.rotation_last_assigned_details.email
                      })
                    : m.settings_webforms_rotation_last_nobody()}
                {/if}
              </p>
            </div>

            <div class="v2-field" hidden={assignmentMode !== 'rotation'}>
              <label for="rotation_cap">{m.settings_webforms_rotation_cap_label()}</label>
              <input
                id="rotation_cap"
                name="rotation_cap"
                class="v2-input"
                type="number"
                min="1"
                step="1"
                inputmode="numeric"
                placeholder={m.settings_webforms_rotation_cap_placeholder()}
                disabled={!canManage}
                value={wf.rotation_cap ?? ''}
              />
              <p class="v2-hint">
                {m.settings_webforms_rotation_cap_hint()}
              </p>
            </div>
          {/if}

          {#if isTicket}
            <div class="v2-field">
              <label for="ticket_priority">{m.settings_webforms_ticket_priority_label()}</label>
              <select
                id="ticket_priority"
                name="ticket_priority"
                class="v2-input"
                disabled={!canManage}
                value={wf.ticket_priority}
              >
                {#each CASE_PRIORITIES as p (p)}
                  <option value={p}>{CASE_PRIORITY_LABEL[p] ?? p}</option>
                {/each}
              </select>
              <p class="v2-hint">{m.settings_webforms_priority_hint()}</p>
            </div>

            <div class="v2-field">
              <label for="ticket_type">{m.settings_webforms_ticket_type_label()}</label>
              <select
                id="ticket_type"
                name="ticket_type"
                class="v2-input"
                disabled={!canManage}
                value={wf.ticket_type ?? ''}
              >
                <option value="">{m.settings_webforms_no_type()}</option>
                {#each CASE_TYPES as t (t)}
                  <option value={t}>{CASE_TYPE_LABEL[t] ?? t}</option>
                {/each}
              </select>
            </div>
          {:else}
            <div class="v2-field">
              <label for="lead_source">{m.settings_webforms_lead_source_label()}</label>
              <select
                id="lead_source"
                name="lead_source"
                class="v2-input"
                disabled={!canManage}
                value={wf.lead_source}
              >
                {#each sourceOptions(data.sources, wf.lead_source) as s (s.key)}
                  <option value={s.key}>{s.label}</option>
                {/each}
              </select>
              <p class="v2-hint">
                {m.settings_webforms_lead_source_hint()}
              </p>
            </div>
          {/if}

          <div class="v2-field">
            <label for="notify_profiles"
              >{isTicket
                ? m.settings_webforms_notify_label_ticket()
                : m.settings_webforms_notify_label_lead()}</label
            >
            <select
              id="notify_profiles"
              name="notify_profiles"
              class="v2-input wf-multi"
              multiple
              size="4"
              disabled={!canManage}
            >
              {#each data.profiles as p (p.id)}
                <option value={p.id} selected={wf.notify_profiles?.includes(p.id)}>{p.name}</option>
              {/each}
            </select>
            <p class="v2-hint">
              {isTicket
                ? m.settings_webforms_notify_hint_ticket()
                : m.settings_webforms_notify_hint_lead()}
            </p>
          </div>

          <div class="v2-field">
            <label for="tags"
              >{isTicket
                ? m.settings_webforms_tag_label_ticket()
                : m.settings_webforms_tag_label_lead()}</label
            >
            <select
              id="tags"
              name="tags"
              class="v2-input wf-multi"
              multiple
              size="4"
              disabled={!canManage}
            >
              {#each data.tags as t (t.id)}
                <option value={t.id} selected={wf.tags?.includes(t.id)}>{t.name}</option>
              {/each}
            </select>
          </div>
        </div>
      </section>

      <!-- ============ Spam ============ -->
      <section class="wf-section">
        <div class="wf-section-head">
          <h2 class="v2-section">{m.settings_webforms_spam_title()}</h2>
          <p class="v2-sub wf-section-sub">
            {m.settings_webforms_spam_sub()}
          </p>
        </div>

        <div class="wf-grid">
          <div class="v2-field wf-wide">
            <label for="allowed_origins">{m.settings_webforms_origins_label()}</label>
            <textarea
              id="allowed_origins"
              name="allowed_origins"
              class="v2-input"
              rows="3"
              disabled={!canManage}
              placeholder="https://example.com">{(wf.allowed_origins ?? []).join('\n')}</textarea
            >
            <p class="v2-hint">
              {m.settings_webforms_origins_hint()}
              {#each originsScript as p, i (i)}{#if p.key}<strong
                    >{m.settings_webforms_origins_hint_script_strong()}</strong
                  >{:else}{p.text}{/if}{/each}
            </p>
          </div>

          <div class="v2-field wf-wide">
            <label class="wf-check">
              <input
                type="checkbox"
                name="reject_disposable_email"
                disabled={!canManage}
                checked={wf.reject_disposable_email}
              />
              {m.settings_webforms_reject_disposable()}
            </label>
          </div>

          <div class="v2-field">
            <label for="captcha_provider">{m.settings_webforms_challenge_label()}</label>
            <select
              id="captcha_provider"
              name="captcha_provider"
              class="v2-input"
              disabled={!canManage}
              bind:value={captchaProvider}
            >
              <option value="">{m.settings_webforms_none()}</option>
              <option value="turnstile">Cloudflare Turnstile</option>
            </select>
          </div>

          {#if captchaProvider === 'turnstile'}
            <div class="v2-field">
              <label for="captcha_site_key">{m.settings_webforms_turnstile_site_key()}</label>
              <input
                id="captcha_site_key"
                name="captcha_site_key"
                class="v2-input"
                maxlength="255"
                disabled={!canManage}
                value={wf.captcha_site_key}
              />
            </div>

            <div class="v2-field wf-wide">
              <label for="captcha_secret">{m.settings_webforms_turnstile_secret()}</label>
              <input
                id="captcha_secret"
                name="captcha_secret"
                class="v2-input"
                type="password"
                autocomplete="off"
                maxlength="255"
                disabled={!canManage}
                placeholder={wf.has_captcha_secret
                  ? m.settings_webforms_secret_stored_placeholder()
                  : m.settings_webforms_secret_paste_placeholder()}
              />
              <p class="v2-hint">
                {m.settings_webforms_secret_hint()}
                {#if !wf.has_captcha_secret}
                  <strong>
                    {m.settings_webforms_secret_missing()}
                  </strong>
                {/if}
              </p>
            </div>
          {/if}
        </div>
      </section>

      {#if canManage}
        <div class="wf-save">
          <button class="v2-btn v2-btn-primary" disabled={busy}
            >{m.settings_webforms_save_changes()}</button
          >
        </div>
      {/if}
    </form>

    <!-- ============ Embed ============ -->
    <section class="wf-section">
      <div class="wf-section-head">
        <h2 class="v2-section">{m.settings_webforms_embed_title()}</h2>
        <p class="v2-sub wf-section-sub">
          {m.settings_webforms_embed_sub()}
        </p>
      </div>

      <div class="wf-snippet">
        <div class="wf-snippet-head">
          <b>iframe</b>
          <span class="v2-sub">{m.settings_webforms_iframe_hint()}</span>
          <button
            type="button"
            class="v2-btn v2-btn-sm"
            onclick={() => copy(wf.embed_html, 'html')}
          >
            {#if copied === 'html'}<Check size={13} />{m.settings_webforms_copied()}{:else}<Copy
                size={13}
              />{m.settings_webforms_copy()}{/if}
          </button>
        </div>
        <pre>{wf.embed_html}</pre>
      </div>

      <div class="wf-snippet">
        <div class="wf-snippet-head">
          <b>script</b>
          <span class="v2-sub">{m.settings_webforms_script_hint()}</span>
          <button type="button" class="v2-btn v2-btn-sm" onclick={() => copy(wf.embed_js, 'js')}>
            {#if copied === 'js'}<Check size={13} />{m.settings_webforms_copied()}{:else}<Copy
                size={13}
              />{m.settings_webforms_copy()}{/if}
          </button>
        </div>
        <pre>{wf.embed_js}</pre>
        {#if !(wf.allowed_origins ?? []).length}
          <p class="v2-hint wf-warn">
            {m.settings_webforms_script_warn()}
          </p>
        {/if}
      </div>
    </section>

    <!-- ============ Activity ============ -->
    <section class="wf-section">
      <div class="wf-section-head">
        <h2 class="v2-section">{m.settings_webforms_activity_title()}</h2>
        <p class="v2-sub wf-section-sub">
          {m.settings_webforms_activity_sub()}
        </p>
      </div>

      {#if totals}
        <div class="v2-stats" style="margin-bottom:16px">
          <StatCard
            label={m.settings_webforms_stat_views()}
            value={count(totals.views)}
            tone="slate"
          />
          <StatCard
            label={isTicket ? m.settings_webforms_stat_tickets() : m.settings_webforms_stat_leads()}
            value={count(totals.submissions)}
            tone="ink"
          />
          <StatCard
            label={m.settings_webforms_stat_conversion()}
            value={totals.views ? `${Math.round(totals.conversion_rate * 100)}%` : '-'}
            tone="slate"
            detail={totals.views ? null : m.settings_webforms_no_views()}
          />
          <StatCard
            label={m.settings_webforms_stat_spam()}
            value={count(totals.spam)}
            tone="slate"
            detail={totals.spam
              ? isTicket
                ? m.settings_webforms_spam_detail_ticket()
                : m.settings_webforms_spam_detail_lead()
              : m.settings_webforms_none()}
          />
        </div>
      {/if}

      {#if !submissions.length}
        <p class="v2-sub wf-empty">
          {m.settings_webforms_activity_empty()}
        </p>
      {:else}
        <div class="v2-table-wrap">
          <table class="v2-table">
            <thead>
              <tr>
                <th>{m.settings_webforms_col_submitted()}</th>
                <th>{m.settings_webforms_col_outcome()}</th>
                <th data-m="hide"
                  >{isTicket
                    ? m.settings_webforms_col_ticket()
                    : m.settings_webforms_col_lead()}</th
                >
                <th data-m="hide">{m.settings_webforms_col_from()}</th>
              </tr>
            </thead>
            <tbody>
              {#each submissions as s (s.id)}
                <tr>
                  <td>
                    <div class="v2-table-primary">{relativeTime(s.created_at)}</div>
                    <div class="v2-table-secondary">{shortDate(s.created_at)}</div>
                  </td>
                  <td data-m="tag"
                    ><Pill tone={statusTone(s.status)}>{statusLabel(s.status)}</Pill></td
                  >
                  <td data-m="meta">
                    {#if s.case}
                      <a href={resolve(`tickets/${s.case}`)}>{s.case_name}</a>
                    {:else if s.lead}
                      <a href={resolve(`leads/${s.lead}`)}>{s.lead_name}</a>
                    {:else}
                      <span class="v2-muted"
                        >{isTicket
                          ? m.settings_webforms_no_ticket()
                          : m.settings_webforms_no_lead()}</span
                      >
                    {/if}
                  </td>
                  <td data-m="hide" class="v2-muted">{s.referer || s.submitted_ip || '—'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
        {#if data.count > submissions.length}
          <p class="v2-sub" style="margin-top:10px;font-size:12px">
            {#each messageParts(m.settings_webforms_showing_recent( { shown: submissions.length, total: slot('total') } )) as p, i (i)}{#if p.key}<span
                  class="v2-num">{count(data.count)}</span
                >{:else}{p.text}{/if}{/each}
          </p>
        {/if}
      {/if}
    </section>

    {#if canManage}
      <section class="wf-section wf-danger">
        <div>
          <b>{m.settings_webforms_delete_title()}</b>
          <p class="v2-sub" style="font-size:12px;margin:4px 0 0;max-width:60ch">
            {isTicket
              ? m.settings_webforms_delete_body_ticket()
              : m.settings_webforms_delete_body_lead()}
          </p>
        </div>
        <ConfirmAction
          action="?/delete"
          label={m.common_delete()}
          confirmLabel={m.settings_webforms_delete_confirm()}
          explain={m.settings_webforms_delete_explain_detail()}
        />
      </section>
    {/if}
  </div>
</div>

<style>
  .wf-body {
    padding-top: 16px;
    padding-bottom: 40px;
    max-width: 900px;
  }

  .wf-section {
    margin-bottom: 30px;
  }

  .wf-section-head {
    margin-bottom: 12px;
  }

  .wf-section-sub {
    font-size: 12px;
    margin: 4px 0 0;
    max-width: 70ch;
  }

  .wf-ok {
    color: var(--v2-moss);
    font-weight: 550;
    font-size: 12.5px;
    margin: 0 0 16px;
  }

  .wf-empty {
    font-size: 12.5px;
    padding: 14px 15px;
    border: 1px dashed var(--v2-line);
    border-radius: var(--v2-radius);
    margin: 0;
  }

  /* ---- field editor ---- */

  .wf-fields {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  /* Stacked, because that is what fits a phone. At 390px the four controls in
     a row share about 190px once the action column is subtracted, which turned
     "Company name" into "Comp" and every placeholder into "Placeholc". The
     side-by-side arrangement is added back at 768px, where there is room for
     it. Mobile-first: the wide layout is the enhancement. */
  .wf-row {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 12px 13px;
    border: 1px solid var(--v2-line);
    border-radius: var(--v2-radius);
    background: var(--v2-card);
    margin-bottom: 8px;
  }

  .wf-row.is-dragging {
    opacity: 0.5;
  }

  .wf-row-body {
    min-width: 0;
  }

  .wf-row-line {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-bottom: 8px;
  }

  .wf-row-line > .v2-input {
    min-width: 0;
  }

  .wf-multi {
    padding: 4px;
  }

  .wf-check {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    font-size: 12.5px;
    font-weight: 500;
  }

  /* Its own line on a phone, pushed right so the reorder and remove controls
     sit under the thumb rather than beside a truncated select. */
  .wf-row-actions {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 4px;
  }

  .wf-move {
    display: flex;
  }

  /* An explicit minimum rather than padding: these are icon-only, and an empty
     button has nothing to pad around. */
  .wf-move-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 44px;
    min-height: 44px;
    border: 1px solid var(--v2-line);
    border-radius: 8px;
    background: var(--v2-card);
    color: var(--v2-slate);
    cursor: pointer;
  }

  .wf-move-btn:hover:not(:disabled) {
    color: var(--v2-ink);
  }

  .wf-move-btn:disabled {
    opacity: 0.35;
    cursor: not-allowed;
  }

  /* Hidden by default, shown from 768px up. Mobile-first: the phone gets the
     buttons, and the pointer-only affordance is what is added on the way up,
     rather than the phone getting a desktop control taken away. */
  .wf-drag {
    display: none;
    color: var(--v2-slate);
  }

  .wf-add {
    margin-top: 4px;
  }

  /* Labels for the selects and inputs in a field row. The row's own layout
     carries the meaning visually; screen readers still need the words. */
  .wf-sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
    white-space: nowrap;
  }

  /* ---- settings grids ---- */

  .wf-grid {
    display: grid;
    grid-template-columns: 1fr;
    gap: 14px;
  }

  .wf-save {
    margin-bottom: 30px;
  }

  /* ---- embed snippets ---- */

  .wf-snippet {
    border: 1px solid var(--v2-line);
    border-radius: var(--v2-radius);
    margin-bottom: 10px;
    overflow: hidden;
  }

  .wf-snippet-head {
    display: flex;
    align-items: center;
    gap: 9px;
    flex-wrap: wrap;
    padding: 9px 12px;
    border-bottom: 1px solid var(--v2-line);
    font-size: 12.5px;
  }

  .wf-snippet-head .v2-sub {
    font-size: 11.5px;
  }

  .wf-snippet-head button {
    margin-left: auto;
  }

  /* Scrolls inside its own box. Without this a long absolute URL widens the
     page and every section beside it inherits a sideways swipe. */
  .wf-snippet pre {
    margin: 0;
    padding: 11px 12px;
    overflow-x: auto;
    font-size: 12px;
    background: var(--v2-bg-sunk);
  }

  .wf-warn {
    padding: 0 12px 11px;
    color: var(--v2-clay);
  }

  .wf-danger {
    display: flex;
    gap: 14px;
    align-items: flex-start;
    justify-content: space-between;
    flex-wrap: wrap;
    padding: 14px 15px;
    border: 1px solid color-mix(in srgb, var(--v2-rust) 28%, var(--v2-line));
    border-radius: var(--v2-radius);
  }

  @media (min-width: 768px) {
    /* The pointer affordance, added at the width where a pointer is likely.
       Below this the up/down buttons are the only reorder, because a drag
       handle on a touch screen competes with the scroll gesture and loses. */
    .wf-drag {
      display: inline-flex;
      align-items: center;
      min-height: 44px;
      cursor: grab;
    }

    .wf-move {
      display: none;
    }

    /* Side by side, now that there is room for the words to fit inside the
       controls. */
    .wf-row {
      flex-direction: row;
      gap: 10px;
      align-items: flex-start;
    }

    .wf-row-body {
      flex: 1;
    }

    .wf-row-line {
      flex-direction: row;
    }

    .wf-row-line > .v2-input {
      flex: 1;
    }

    .wf-narrow {
      flex: 0 1 auto;
    }

    .wf-row-actions {
      flex: none;
    }

    .wf-grid {
      grid-template-columns: 1fr 1fr;
    }

    .wf-wide {
      grid-column: 1 / -1;
    }
  }
</style>
