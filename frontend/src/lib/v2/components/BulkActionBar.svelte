<script>
  import { m } from '#lib/paraglide/messages.js';
  import { enhance } from '$app/forms';
  import {
    CASE_STATUSES,
    CASE_PRIORITIES,
    CASE_TYPES,
    CASE_STATUS_LABEL,
    CASE_PRIORITY_LABEL,
    CASE_TYPE_LABEL
  } from '#lib/v2/enums.js';

  /**
   * @type {{
   *   ids: string[],
   *   people: {id:string,name:string}[],
   *   tags: {id:string,name:string}[],
   *   onclear: () => void,
   *   ondone: () => void
   * }}
   */
  let { ids, people, tags, onclear, ondone } = $props();

  // Which action the agent picked in the menu. '' means the menu is showing.
  let action = $state('');
  // The status select's live value, so the Close date field can appear the
  // moment "Closed" is picked, before Apply is pressed. Starts blank so
  // Apply cannot fire on an unmade choice.
  let statusValue = $state('');
  // Delete is a two-click confirm, armed by the first click. Kept separate
  // from `action` so leaving and re-entering the delete branch through Back
  // does not skip the confirm on the next attempt.
  let armed = $state(false);
  // Duplicate is reached only by merging; the bulk endpoint refuses it.
  const SETTABLE_STATUSES = CASE_STATUSES.filter((v) => v !== 'Duplicate');

  let ACTIONS = $derived([
    { key: 'assigned_to', label: m.app_bulk_reassign() },
    { key: 'priority', label: m.app_bulk_set_priority() },
    { key: 'status', label: m.app_bulk_set_status() },
    { key: 'case_type', label: m.app_bulk_set_type() },
    { key: 'tags', label: m.app_bulk_add_tags() },
    { key: 'delete', label: m.common_delete() }
  ]);

  /** @type {Record<string, string>} */
  const OPTION_LABEL = { ...CASE_STATUS_LABEL, ...CASE_PRIORITY_LABEL, ...CASE_TYPE_LABEL };
  const optionLabel = (/** @type {string} */ v) => OPTION_LABEL[v] ?? v;

  function reset() {
    action = '';
    armed = false;
    ondone();
  }
</script>

<div class="v2-bulkbar" role="region" aria-label={m.app_bulk_region()}>
  <span class="v2-num">{m.app_bulk_selected({ count: ids.length })}</span>
  <button type="button" class="v2-btn" onclick={onclear}>{m.app_bulk_clear()}</button>

  {#if action === ''}
    <select class="v2-input" bind:value={action} aria-label={m.app_bulk_choose_action()}>
      <option value="">{m.common_actions()}</option>
      {#each ACTIONS as a (a.key)}
        <option value={a.key}>{a.label}</option>
      {/each}
    </select>
  {:else if action === 'delete'}
    <form
      method="POST"
      action="?/bulkDelete"
      use:enhance={() =>
        async ({ update }) => {
          await update({ reset: false });
          reset();
        }}
    >
      {#each ids as id (id)}<input type="hidden" name="ids" value={id} />{/each}
      {#if !armed}
        <button type="button" class="v2-btn" onclick={() => (armed = true)}>
          {m.app_bulk_delete_count({ count: ids.length })}
        </button>
      {:else}
        <button type="submit" class="v2-btn v2-btn-primary">{m.common_confirm()}</button>
        <button type="button" class="v2-btn" onclick={() => (armed = false)}
          >{m.common_cancel()}</button
        >
      {/if}
      <button type="button" class="v2-btn" onclick={() => ((action = ''), (armed = false))}>
        {m.common_back()}
      </button>
    </form>
  {:else}
    <form
      method="POST"
      action="?/bulkUpdate"
      use:enhance={() =>
        async ({ update }) => {
          await update({ reset: false });
          reset();
        }}
    >
      {#each ids as id (id)}<input type="hidden" name="ids" value={id} />{/each}
      <input type="hidden" name="field" value={action} />

      {#if action === 'assigned_to'}
        <select class="v2-input" name="value" required>
          <option value="">{m.app_bulk_choose_person()}</option>
          {#each people as p (p.id)}<option value={p.id}>{p.name}</option>{/each}
        </select>
      {:else if action === 'tags'}
        <select class="v2-input" name="value" multiple required>
          {#each tags as t (t.id)}<option value={t.id}>{t.name}</option>{/each}
        </select>
      {:else if action === 'priority'}
        <select class="v2-input" name="value" required>
          <option value="">{m.app_bulk_choose_priority()}</option>
          {#each CASE_PRIORITIES as v (v)}<option value={v}>{optionLabel(v)}</option>{/each}
        </select>
      {:else if action === 'case_type'}
        <select class="v2-input" name="value" required>
          <option value="">{m.app_bulk_choose_type()}</option>
          {#each CASE_TYPES as v (v)}<option value={v}>{optionLabel(v)}</option>{/each}
        </select>
      {:else if action === 'status'}
        <select class="v2-input" name="value" bind:value={statusValue} required>
          <option value="">{m.app_bulk_choose_status()}</option>
          {#each SETTABLE_STATUSES as v (v)}<option value={v}>{optionLabel(v)}</option>{/each}
        </select>
        {#if statusValue === 'Closed'}
          <!-- Optional. Left empty, nothing is sent and the API dates each
               close today in the org's timezone. -->
          <input
            class="v2-input"
            type="date"
            name="closed_on"
            aria-label={m.app_bulk_closed_on()}
            aria-describedby="bulk-closed-hint"
          />
          <span class="v2-hint" id="bulk-closed-hint">{m.app_bulk_closed_hint()}</span>
        {/if}
      {/if}

      <button type="submit" class="v2-btn v2-btn-primary">{m.common_apply()}</button>
      <button type="button" class="v2-btn" onclick={() => (action = '')}>{m.common_back()}</button>
    </form>
  {/if}
</div>

<style>
  .v2-bulkbar {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
    padding: 10px 12px;
    border: 1px solid var(--v2-line);
    border-radius: 10px;
    background: var(--v2-card);
  }
  /* Phone: dock above the tab bar, full width, comfortable tap targets. */
  @media (max-width: 768px) {
    .v2-bulkbar {
      position: fixed;
      left: 8px;
      right: 8px;
      bottom: calc(var(--v2-tabbar-h, 56px) + 8px);
      z-index: 40;
      box-shadow: 0 2px 12px rgba(0, 0, 0, 0.12);
    }
    .v2-bulkbar :global(.v2-btn),
    .v2-bulkbar .v2-input {
      min-height: 44px;
    }
  }
</style>
