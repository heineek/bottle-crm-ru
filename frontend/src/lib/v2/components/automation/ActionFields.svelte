<script lang="ts">
  import { m } from '#lib/paraglide/messages.js';
  import {
    fieldOf,
    targetsFor,
    recipientsFor,
    taskAudience,
    withStored,
    applyTarget,
    applyField,
    applyAssignTo,
    applyClear,
    applyMode,
    isClearing,
    setActionValue,
    shownValue,
    recipientLabel,
    replacePerson,
    type Catalogue,
    type CatalogueObject,
    type RuleAction,
    type RuleValue
  } from '#lib/v2/automation.js';
  import { TASK_PRIORITY_LABEL } from '#lib/v2/enums.js';
  import RuleValueInput from './RuleValueInput.svelte';

  /**
   * The fields of one action, by its type. A stored target, field, person,
   * recipient or endpoint the catalogue lost stays selected and marked.
   */
  let {
    catalogue,
    object,
    action = $bindable(),
    errorId = undefined
  }: {
    catalogue: Catalogue;
    object: CatalogueObject | null;
    action: RuleAction;
    errorId?: string;
  } = $props();

  const uid = $props.id();
  const people = $derived(catalogue?.people ?? []);

  // What the action held before "Clear it instead" was ticked.
  let previous: RuleValue | undefined = $state();
  let clear = $derived(isClearing(action));

  let targets = $derived(targetsFor(catalogue, object));
  let target = $derived(targets.find((t) => t.value === action.target) ?? null);
  let fieldOptions = $derived(
    (target?.object?.fields ?? [])
      .filter((f) => f.settable)
      .map((f) => ({ value: f.key, label: f.label }))
  );
  let field = $derived(fieldOf(target?.object, action.field));

  let recipients = $derived(recipientsFor(object));
  let recipientField = $derived({
    key: 'to',
    label: m.app_automation_who(),
    type: 'choice',
    settable: true,
    choices: recipients.map((r) => ({ ...r, group: '', settable: true }))
  });
  let audience = $derived(taskAudience(object));
  let one = $derived(replacePerson(action));
  let endpoints = $derived(
    (catalogue?.endpoints ?? []).map((e) => ({ value: e.id, label: e.description ?? '' }))
  );

  /** The single person of a replace, as the list the API stores. */
  function setOne(id: string) {
    action.people = id ? [id] : [];
  }

  function setClear(on: boolean) {
    if (on) previous = action.value;
    applyClear(action, on, previous);
  }
</script>

{#if action.type === 'set_field'}
  <div class="af-grid">
    <div class="v2-field">
      <label for="{uid}-target">{m.app_automation_on()}</label>
      <select
        id="{uid}-target"
        class="v2-input"
        value={action.target}
        aria-describedby={errorId}
        onchange={(e) => applyTarget(action, e.currentTarget.value)}
      >
        {#each withStored( targets.map( (t) => ({ value: t.value, label: t.label }) ), action.target, { label: () => m.app_automation_removed_link() } ) as o (o.value)}
          <option value={o.value}>{o.label}</option>
        {/each}
      </select>
    </div>
    <div class="v2-field">
      <label for="{uid}-field">{m.app_automation_set()}</label>
      <select
        id="{uid}-field"
        class="v2-input"
        value={action.field}
        aria-describedby={errorId}
        onchange={(e) => applyField(action, e.currentTarget.value)}
      >
        {#if !action.field}<option value="">{m.app_automation_choose_field()}</option>{/if}
        {#each withStored(fieldOptions, action.field) as o (o.value)}
          <option value={o.value}>{o.label}</option>
        {/each}
      </select>
    </div>
    {#if action.field}
      <div class="v2-field af-wide">
        {#if !field}
          <p class="v2-muted">{m.app_automation_field_gone()}</p>
        {:else}
          {#if !clear}
            {#if field.type === 'people'}
              <span class="af-label">{m.app_automation_to()}</span>
            {:else}
              <label for="{uid}-value">{m.app_automation_to()}</label>
            {/if}
            <RuleValueInput
              {field}
              kind={field.type}
              bind:value={() => shownValue(action), (v) => setActionValue(action, v)}
              {people}
              settableOnly
              id="{uid}-value"
              label={m.app_automation_value_to_set()}
              describedby={errorId}
            />
          {/if}
          <label class="af-check">
            <input
              type="checkbox"
              checked={clear}
              onchange={(e) => setClear(e.currentTarget.checked)}
            />
            <span>{m.app_automation_clear_instead()}</span>
          </label>
        {/if}
      </div>
    {/if}
  </div>
{:else if action.type === 'assign'}
  <div class="af-grid">
    <div class="v2-field">
      <label for="{uid}-mode">{m.app_automation_who()}</label>
      <select
        id="{uid}-mode"
        class="v2-input"
        value={action.mode}
        aria-describedby={errorId}
        onchange={(e) => applyMode(action, e.currentTarget.value)}
      >
        <option value="replace">{m.app_automation_one_person()}</option>
        <option value="rotate">{m.app_automation_in_turn()}</option>
      </select>
    </div>
    <div class="v2-field">
      {#if action.mode === 'rotate'}
        <RuleValueInput
          field={null}
          kind="people"
          bind:value={action.people}
          {people}
          id="{uid}-people"
          label={m.app_automation_people_in_turn()}
          describedby={errorId}
        />
        <p class="v2-hint">{m.app_automation_rotate_hint()}</p>
      {:else}
        <label for="{uid}-one">{m.app_automation_person()}</label>
        <select
          id="{uid}-one"
          class="v2-input"
          value={one.id}
          aria-describedby={errorId}
          onchange={(e) => setOne(e.currentTarget.value)}
        >
          <option value="">{m.app_automation_choose_person()}</option>
          {#each withStored( people.map( (p) => ({ value: p.id, label: p.name }) ), action.people, { person: true } ) as o (o.value)}
            <option value={o.value}>{o.label}</option>
          {/each}
        </select>
        {#if one.several}
          <p class="v2-hint">{m.app_automation_one_person_hint()}</p>
        {/if}
      {/if}
    </div>
    <p class="v2-hint af-wide">{m.app_automation_replaces_assignees()}</p>
  </div>
{:else if action.type === 'create_task'}
  <div class="af-grid">
    <div class="v2-field af-wide">
      <label for="{uid}-title">{m.app_automation_title()}</label>
      <input
        id="{uid}-title"
        class="v2-input"
        maxlength="200"
        autocomplete="off"
        bind:value={action.title}
        aria-describedby={errorId}
      />
      <p class="v2-hint">{m.app_automation_name_token_hint({ token: '{name}' })}</p>
    </div>
    <div class="v2-field">
      <label for="{uid}-due">{m.app_automation_due_in_days()}</label>
      <input
        id="{uid}-due"
        class="v2-input"
        type="number"
        min="0"
        max="365"
        step="1"
        inputmode="numeric"
        bind:value={action.due_in_days}
        aria-describedby={errorId}
      />
      <p class="v2-hint">{m.app_automation_no_due_hint()}</p>
    </div>
    <div class="v2-field">
      <label for="{uid}-priority">{m.common_priority()}</label>
      <select
        id="{uid}-priority"
        class="v2-input"
        bind:value={action.priority}
        aria-describedby={errorId}
      >
        {#each withStored([{ value: 'Low', label: TASK_PRIORITY_LABEL.Low }, { value: 'Medium', label: TASK_PRIORITY_LABEL.Medium }, { value: 'High', label: TASK_PRIORITY_LABEL.High }], action.priority) as o (o.value)}
          <option value={o.value}>{o.label}</option>
        {/each}
      </select>
    </div>
    <div class="v2-field">
      <label for="{uid}-for">{m.app_automation_for()}</label>
      <select
        id="{uid}-for"
        class="v2-input"
        value={action.assign_to}
        aria-describedby={errorId}
        onchange={(e) => applyAssignTo(action, e.currentTarget.value)}
      >
        {#each withStored(audience, action.assign_to, { label: recipientLabel }) as o (o.value)}
          <option value={o.value}>{o.label}</option>
        {/each}
      </select>
    </div>
    {#if action.assign_to === 'person'}
      <div class="v2-field">
        <label for="{uid}-person">{m.app_automation_person()}</label>
        <RuleValueInput
          field={null}
          kind="person"
          bind:value={action.person}
          {people}
          id="{uid}-person"
          label={m.app_automation_task_for()}
          describedby={errorId}
        />
      </div>
    {/if}
  </div>
{:else if action.type === 'notify'}
  <div class="af-grid">
    <div class="v2-field">
      <span class="af-label">{m.app_automation_who()}</span>
      <RuleValueInput
        field={recipientField}
        kind="choices"
        lostLabel={recipientLabel}
        bind:value={action.to}
        {people}
        id="{uid}-to"
        label={m.app_automation_who_to_notify()}
        describedby={errorId}
      />
    </div>
    <div class="v2-field">
      <span class="af-label">{m.app_automation_and_these_people()}</span>
      <RuleValueInput
        field={null}
        kind="people"
        bind:value={action.people}
        {people}
        id="{uid}-people"
        label={m.app_automation_and_these_people()}
        describedby={errorId}
      />
    </div>
    <div class="v2-field af-wide">
      <label for="{uid}-message">{m.app_automation_message()}</label>
      <textarea
        id="{uid}-message"
        class="v2-input"
        rows="3"
        maxlength="500"
        bind:value={action.message}
        aria-describedby={errorId}></textarea>
      <p class="v2-hint">{m.app_automation_name_token_hint({ token: '{name}' })}</p>
    </div>
    <p class="v2-hint af-wide">{m.app_automation_notify_hint()}</p>
  </div>
{:else if action.type === 'webhook'}
  <div class="af-grid">
    <div class="v2-field">
      <label for="{uid}-endpoint">{m.app_automation_endpoint()}</label>
      <select
        id="{uid}-endpoint"
        class="v2-input"
        bind:value={action.endpoint}
        aria-describedby={errorId}
      >
        {#if !action.endpoint}<option value="">{m.app_automation_choose_endpoint()}</option>{/if}
        {#each withStored( endpoints, action.endpoint, { label: () => m.app_automation_endpoint_gone() } ) as o (o.value)}
          <option value={o.value}>{o.label}</option>
        {/each}
      </select>
    </div>
  </div>
{:else}
  <p class="v2-muted">{m.app_automation_action_gone()}</p>
{/if}

<style>
  .af-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px 12px;
    align-items: start;
  }
  .af-grid :global(.v2-field) {
    margin: 0;
    min-width: 0;
  }
  .af-wide {
    grid-column: 1 / -1;
  }
  .af-label {
    display: block;
    font-size: 12px;
    font-weight: 600;
    margin-bottom: 4px;
  }
  .af-check {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 44px;
    font-size: 13px;
  }
  .af-check input {
    width: 18px;
    height: 18px;
    flex: none;
  }
  @media (max-width: 768px) {
    .af-grid {
      grid-template-columns: minmax(0, 1fr);
    }
    .af-grid :global(.v2-input) {
      min-height: 44px;
    }
  }
</style>
