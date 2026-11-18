<script lang="ts">
  /**
   * Canned replies.
   *
   * The body is the whole point of a macro, so it is on the page. V1 hides it
   * behind an edit dialog and lists titles, which means you cannot tell two
   * similarly-named macros apart without opening both.
   *
   * Placeholders are marked inline. `%customer_name%` is substituted by the
   * server; anything outside its seven supported tokens is left literal and
   * goes to the customer exactly as typed. That is the failure this page
   * exists to make visible: `%custmer_name%` has shipped twelve times.
   *
   * The body is org-authored text and is rendered as TEXT, split into
   * segments and placed in elements, never through {@html}. A canned reply is
   * a string a colleague wrote; putting it in the DOM as markup would make the
   * macro editor a stored-XSS form.
   *
   * PERMISSIONS, WHICH ARE NOT ROLE-GATED THE WAY THE REST OF SETTINGS IS
   * Every signed-in member may create, edit and delete their own `personal`
   * macros; only an admin may do any of that to an `org`-scope one.
   * `data.can_create_org` and `data.my_profile_id` are display hints decoded
   * server-side from the JWT (see `macros.js`'s `getMacros`), never the
   * authorization: the backend re-derives both and is what actually decides
   * whether a write succeeds. `canWrite` below mirrors that split so a row
   * only offers Edit/Delete when the click would not just come back as an
   * error.
   */
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import SettingsFormPanel from '#lib/v2/components/SettingsFormPanel.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import { count, relativeDays } from '#lib/v2/format.js';
  import {
    MACRO_SCOPE_LABEL,
    CASE_PRIORITIES,
    CASE_PRIORITY_LABEL,
    CASE_STATUS_LABEL
  } from '#lib/v2/enums.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { Plus, TriangleAlert } from '@lucide/svelte';
  import type { PageProps } from './$types';
  import type { MacroRow } from '#lib/server/v2/macros.js';

  let { data, form }: PageProps = $props();

  // `null` when the panel is closed, `'new'` when adding, or the macro
  // object when editing that row. One panel, two modes, so two rows can
  // never be open for edit at once.
  let editing = $state<'new' | MacroRow | null>(null);

  // The scope currently selected in the form. Bound separately from `editing`
  // so the select works the same way in both modes: seeded from the row on
  // edit, defaulted to 'personal' on create, since every member can make a
  // personal macro but not every member can make an org one.
  let scope = $state('personal');

  function openCreate() {
    editing = 'new';
    scope = 'personal';
  }

  function openEdit(m: MacroRow) {
    editing = m;
    scope = m.scope;
  }

  /**
   * May the signed-in viewer write this row. An org macro is writable only
   * by an admin (`data.can_create_org`); a personal macro is writable only
   * by its owner, compared by Profile id (`m.owner.id`, from `getMacros`'s
   * reshape, against `data.my_profile_id`). This is a display decision, not
   * an authorization one: the backend enforces the same split independently
   * (403 on someone else's org macro, 404 on someone else's personal one)
   * and would refuse the write even if this returned true by mistake.
   */
  function canWrite(m: MacroRow) {
    return m.scope === 'org' ? data.can_create_org : m.owner?.id === data.my_profile_id;
  }

  let totals = $derived(data.totals);
  let subParts = $derived(
    messageParts(m.settings_macros_sub({ shared: slot('shared'), yours: slot('yours') }))
  );
  let byUse = $derived([...data.macros].sort((a, b) => b.usage_count - a.usage_count));
  let orgMacros = $derived(byUse.filter((mac) => mac.scope === 'org'));
  let personalMacros = $derived(byUse.filter((mac) => mac.scope === 'personal'));

  /**
   * Split a body into text and placeholder segments for rendering.
   *
   * Whether a token is real is decided by the server's `unknown_placeholders`,
   * not by matching against a list kept here. The supported set lives in
   * `macros/render.py` precisely so clients cannot drift from it. A copy in
   * this file would eventually mark a working macro as broken.
   */
  function segments(macro: { body: string; unknown_placeholders: string[] }) {
    const re = /%[a-zA-Z_][a-zA-Z0-9_]*%/g;
    const out = [];
    let last = 0;
    let match;
    while ((match = re.exec(macro.body)) !== null) {
      if (match.index > last) out.push({ text: macro.body.slice(last, match.index), token: false });
      out.push({
        text: match[0],
        token: true,
        known: !macro.unknown_placeholders.includes(match[0])
      });
      last = match.index + match[0].length;
    }
    if (last < macro.body.length) out.push({ text: macro.body.slice(last), token: false });
    return out;
  }
</script>

<PageHeader title={m.settings_macros_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#each subParts as p, i (i)}{#if p.key === 'shared'}<span class="v2-num"
          >{count(totals.org)}</span
        >{:else if p.key === 'yours'}<span class="v2-num">{count(totals.personal)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    {#if !editing}
      <button class="v2-btn v2-btn-primary" onclick={openCreate}
        ><Plus />{m.settings_macros_new()}</button
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-pad" style="padding-top:16px;flex:none">
  <div class="v2-stats">
    <StatCard label={m.settings_macros_stat_shared()} value={count(totals.org)} tone="ink" />
    <StatCard label={m.settings_macros_stat_yours()} value={count(totals.personal)} tone="slate" />
    <StatCard
      label={m.settings_macros_stat_broken()}
      value={count(totals.with_unknown_placeholders)}
      tone={totals.with_unknown_placeholders > 0 ? 'rust' : 'slate'}
      detail={m.settings_macros_stat_broken_detail()}
    />
    <StatCard label={m.settings_macros_stat_off()} value={count(totals.inactive)} tone="slate" />
  </div>
</div>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-bottom:32px">
    {#if editing}
      {@const current = editing}
      <SettingsFormPanel
        title={current === 'new'
          ? m.settings_macros_new()
          : m.settings_macros_edit_title({ title: current.title })}
        action={current === 'new' ? '?/create' : '?/update'}
        error={current === 'new' ? form?.create?.error : form?.update?.error}
        submitLabel={current === 'new' ? m.settings_macros_add() : m.settings_macros_save()}
        oncancel={() => (editing = null)}
        ondone={() => (editing = null)}
      >
        {#snippet fields()}
          {#if current !== 'new'}
            <input type="hidden" name="id" value={current.id} />
          {/if}

          <div class="v2-field">
            <label for="m-title">{m.settings_macros_title_label()}</label>
            <input
              id="m-title"
              class="v2-input"
              name="title"
              maxlength="255"
              required
              value={current === 'new' ? '' : current.title}
            />
          </div>

          <div class="v2-field">
            <label for="m-scope">{m.settings_macros_scope_label()}</label>
            <select id="m-scope" class="v2-input" name="scope" bind:value={scope}>
              <option value="personal">{m.settings_macros_scope_me()}</option>
              {#if data.can_create_org}
                <option value="org">{m.settings_macros_scope_org()}</option>
              {/if}
            </select>
            {#if !data.can_create_org}
              <p class="v2-hint">{m.settings_macros_scope_hint()}</p>
            {/if}
          </div>

          <div class="v2-field v2-sfp-wide">
            <label for="m-body">{m.settings_macros_body_label()}</label>
            <textarea id="m-body" class="v2-input" name="body" rows="5"
              >{current === 'new' ? '' : current.body}</textarea
            >
            <p class="v2-hint">
              {m.settings_macros_body_hint()}
            </p>
          </div>

          <!-- The actions, applied to the ticket right after the reply is
               sent. Blank or nothing selected means "leave it alone". -->
          <div class="v2-field">
            <label for="m-status">{m.settings_macros_set_status()}</label>
            <select id="m-status" class="v2-input" name="set_status">
              <option value="">{m.settings_macros_no_change()}</option>
              {#each data.statuses as s (s)}
                <option value={s} selected={current !== 'new' && current.set_status === s}
                  >{s}</option
                >
              {/each}
            </select>
          </div>

          <div class="v2-field">
            <label for="m-priority">{m.settings_macros_set_priority()}</label>
            <select id="m-priority" class="v2-input" name="set_priority">
              <option value="">{m.settings_macros_no_change()}</option>
              {#each CASE_PRIORITIES as p (p)}
                <option value={p} selected={current !== 'new' && current.set_priority === p}
                  >{p}</option
                >
              {/each}
            </select>
          </div>

          <div class="v2-field">
            <label for="m-assignees">{m.settings_macros_assign_label()}</label>
            <select
              id="m-assignees"
              class="v2-input m-multi"
              name="set_assignees"
              multiple
              size="4"
            >
              {#each current === 'new' ? data.people : current.assignee_options as p (p.id)}
                <option
                  value={p.id}
                  selected={current !== 'new' && current.set_assignees.includes(p.id)}
                  >{p.name}</option
                >
              {/each}
            </select>
            <p class="v2-hint">{m.settings_macros_assign_hint()}</p>
          </div>

          <div class="v2-field">
            <label for="m-tags">{m.settings_macros_tags_label()}</label>
            <select id="m-tags" class="v2-input m-multi" name="add_tags" multiple size="4">
              {#each current === 'new' ? data.tags : current.tag_options as t (t.id)}
                <option value={t.id} selected={current !== 'new' && current.add_tags.includes(t.id)}
                  >{t.name}</option
                >
              {/each}
            </select>
            <p class="v2-hint">{m.settings_macros_tags_hint()}</p>
          </div>
        {/snippet}
      </SettingsFormPanel>
    {/if}

    {#if form?.delete?.error}
      <p class="v2-error" style="margin-bottom:12px">{form.delete.error}</p>
    {/if}
    {#if form?.activate?.error}
      <p class="v2-error" style="margin-bottom:12px">{form.activate.error}</p>
    {/if}

    <div class="v2-split-wide">
      <div>
        <div class="v2-label" style="margin-bottom:10px">{m.settings_macros_stat_shared()}</div>
        <div style="display:flex;flex-direction:column;gap:9px;margin-bottom:24px">
          {#each orgMacros as mac (mac.id)}
            {@render macro(mac)}
          {/each}
        </div>

        <div class="v2-label" style="margin-bottom:10px">{m.settings_macros_stat_yours()}</div>
        <div style="display:flex;flex-direction:column;gap:9px">
          {#each personalMacros as mac (mac.id)}
            {@render macro(mac)}
          {/each}
        </div>
        <p class="v2-sub" style="font-size:11.5px;margin-top:11px">
          {m.settings_macros_personal_note()}
        </p>
      </div>

      <div>
        <div class="v2-label" style="margin-bottom:10px">
          {m.settings_macros_placeholders_heading()}
        </div>
        <div class="v2-card" style="overflow:hidden">
          {#each data.placeholders as p (p.token)}
            <div class="v2-setting" style="padding:10px 15px">
              <div class="v2-setting-body">
                <code class="v2-token">{p.token}</code>
              </div>
              <span class="v2-sub" style="font-size:11.5px;text-align:right">{p.resolves}</span>
            </div>
          {/each}
        </div>
        <p class="v2-sub" style="font-size:11.5px;margin-top:11px;line-height:1.5">
          {m.settings_macros_placeholders_note()}
        </p>
      </div>
    </div>
  </div>
</div>

{#snippet macro(mac: MacroRow)}
  <div class="v2-card" style="padding:14px 16px;opacity:{mac.is_active ? 1 : 0.62}">
    <div style="display:flex;gap:10px;align-items:baseline;flex-wrap:wrap">
      <b style="font-size:13.5px">{mac.title}</b>
      {#if !mac.is_active}<Pill tone="slate">{m.settings_macros_off()}</Pill>{/if}
      {#if mac.unknown_placeholders.length}<Pill tone="rust">{m.settings_macros_broken()}</Pill
        >{/if}
      <span class="v2-sub" style="font-size:11.5px;margin-left:auto">
        {#each messageParts(m.settings_macros_used( { count: mac.usage_count, shown: slot('shown'), when: relativeDays(mac.updated_at) } )) as p, i (i)}{#if p.key}<span
              class="v2-num">{count(mac.usage_count)}</span
            >{:else}{p.text}{/if}{/each}
      </span>
    </div>

    <!--
      Text nodes and spans, never {@html}.

      Written on one line and held there by prettier-ignore. Svelte collapses
      the newline and indentation between two inline children into a single
      space, so a formatted version of this block renders "%customer_name% ,".
      A space the macro does not contain, in a preview whose whole job is to
      show exactly what the customer receives.
    -->
    <!-- prettier-ignore -->
    <p class="v2-macro-body">{#each segments(mac) as seg, i (i)}{#if seg.token}<span class="v2-token" class:v2-token-bad={!seg.known}>{seg.text}</span>{:else}{seg.text}{/if}{/each}</p>

    {#if mac.unknown_placeholders.length}
      <div class="v2-macro-flag">
        <TriangleAlert size={14} style="color:var(--v2-rust);flex:none" />
        <span>
          {(mac.unknown_placeholders.length === 1
            ? m.settings_macros_unknown_one
            : m.settings_macros_unknown_many)({
            tokens: mac.unknown_placeholders.join(m.settings_macros_and())
          })}
          {#if mac.usage_count > 0}
            {#each messageParts(m.settings_macros_sent_times( { count: mac.usage_count, shown: slot('shown') } )) as p, i (i)}{#if p.key}<span
                  class="v2-num">{count(mac.usage_count)}</span
                >{:else}{p.text}{/if}{/each}
          {/if}
        </span>
      </div>
    {/if}

    {#if mac.chips.length}
      <div class="v2-macro-acts">
        <span class="v2-sub">{m.settings_macros_on_send()}</span>
        {#each mac.chips as chip (chip.key)}
          <Pill tone="slate">{chip.label}</Pill>
        {/each}
      </div>
    {/if}

    {#if mac.owner}
      <div class="v2-sub" style="font-size:11px;margin-top:8px">
        {MACRO_SCOPE_LABEL[mac.scope]} · {mac.owner.name}
      </div>
    {/if}

    {#if canWrite(mac)}
      <div style="display:flex;gap:6px;align-items:center;justify-content:flex-end;margin-top:10px">
        <button class="v2-btn v2-btn-sm" type="button" onclick={() => openEdit(mac)}
          >{m.settings_macros_edit()}</button
        >
        {#if !mac.is_active}
          <!-- Turning a macro back on restores nothing that was destroyed, so
               unlike "Turn off"/"Delete" this doesn't need the two-click
               confirm. A plain enhanced form posting just the id keeps the
               request to `{ is_active: true }`; see `activateMacro`'s
               comment for why that has to bypass `updateMacro` rather than
               reuse it. Offered for both scopes on purpose: an org row gets
               here by "Turn off" (soft), a personal row can only be inactive
               from data written before the edit form stopped carrying
               `is_active`, and either way `_get_writable` still enforces
               admin-only for org / owner-only for personal server-side, so
               this can never write a row `canWrite` above disagrees with. -->
          <form method="POST" action="?/activate" use:enhance>
            <input type="hidden" name="id" value={mac.id} />
            <button class="v2-btn v2-btn-sm" type="submit">{m.settings_macros_turn_on()}</button>
          </form>
        {:else if mac.scope === 'org'}
          <!-- `MacroDetailView.delete` soft-deletes an org macro: it flips
               `is_active` and leaves the row (and its usage count) in place.
               "Turn off", not "Delete", says what actually happens. -->
          <ConfirmAction
            action="?/delete"
            label={m.settings_macros_turn_off()}
            confirmLabel={m.settings_macros_turn_off()}
            explain={m.settings_macros_turn_off_explain()}
            hidden={{ id: mac.id }}
          />
        {:else}
          <!-- A personal macro is hard-deleted, not soft-deactivated: this
               button removes the row outright, so once it's gone there is
               nothing left to turn back on. -->
          <ConfirmAction
            action="?/delete"
            label={m.settings_macros_delete()}
            confirmLabel={m.settings_macros_delete()}
            explain={m.settings_macros_delete_explain()}
            hidden={{ id: mac.id }}
          />
        {/if}
      </div>
    {/if}
  </div>
{/snippet}

<style>
  .v2-macro-body {
    font-size: 12.5px;
    color: var(--v2-slate);
    line-height: 1.55;
    white-space: pre-wrap;
    margin: 9px 0 0;
  }
  .v2-token {
    font-family: var(--v2-mono);
    font-size: 11.5px;
    background: var(--v2-hover);
    border-radius: 3px;
    padding: 1px 4px;
    color: var(--v2-ink);
  }
  /* No side padding inside a body preview. Four pixels either side renders
     "%customer_name% ,". A space the macro does not contain, on a screen
     whose only job is to show exactly what the customer will receive. The
     background alone is enough to mark it. */
  .v2-macro-body .v2-token {
    padding: 1px 0;
  }
  /* Rust, not ember: a broken placeholder is a fact about the macro, not a
     button. Ember stays reserved for things you act on. */
  .v2-token-bad {
    color: var(--v2-rust);
    text-decoration: underline wavy;
    text-underline-offset: 2px;
  }
  .v2-macro-acts {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px;
    margin-top: 10px;
    font-size: 11.5px;
  }
  /* A pill never wraps; an assignee list has to, or it pushes the card wider
     than a phone. */
  .v2-macro-acts :global(.v2-pill) {
    white-space: normal;
    max-width: 100%;
    overflow-wrap: anywhere;
  }
  /* A select that shows several rows at once; the default single-row height
     would hide all but one person. */
  .m-multi {
    min-height: 96px;
  }
  .v2-macro-flag {
    display: flex;
    gap: 7px;
    align-items: flex-start;
    margin-top: 10px;
    font-size: 12px;
    color: var(--v2-slate);
    line-height: 1.45;
  }
</style>
