<script>
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  /**
   * Two leads, contacts or accounts side by side, to pick which one to keep.
   *
   * The rule the API applies is shown before it runs: the kept record's values
   * stay, its blank fields take the other's, and the other record is deleted
   * once its links, notes and files have moved. There is no undo, so the
   * confirmation is a box the person ticks, not a second click on the same
   * spot.
   *
   * Keeping one record means deleting the other, so a record can only be kept
   * when the other is one the person may delete (`can_delete`, from the API).
   * That is a hint to spare a refusal; the API decides.
   *
   * Stacked at phone width, side by side above 768px.
   */
  import { untrack } from 'svelte';
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import { mergeSideLabel } from '#lib/v2/merge-label.js';
  import { ChevronRight, TriangleAlert } from '@lucide/svelte';

  /** @typedef {{ id: string, name: string, can_delete: boolean, fields: Array<{ label: string, value: string }> }} Side */
  /** @type {{ data: { module: 'leads' | 'contacts' | 'accounts', singular: string, current: Side, other: Side }, form: any }} */
  let { data, form } = $props();

  let { module, current, other } = $derived(data);

  let keep = $state(
    untrack(() =>
      data.other.can_delete || !data.current.can_delete ? data.current.id : data.other.id
    )
  );
  let confirmed = $state(false);
  let busy = $state(false);

  let kept = $derived(keep === current.id ? current : other);
  let dropped = $derived(keep === current.id ? other : current);
  /** @param {Side} side */
  const keepable = (side) => (side.id === current.id ? other : current).can_delete;
  let possible = $derived(keepable(current) || keepable(other));
  /** How the copy names a record; see `mergeSideLabel`. @param {Side} side */
  const label = (side) => mergeSideLabel(side, current, other);
  /** @type {Record<string, { title: () => string, crumb: () => string, which: () => string, impossible: () => string }>} */
  const TEXT = {
    leads: {
      title: m.app_merge_title_leads,
      crumb: m.app_merge_crumb_leads,
      which: m.app_merge_which_leads,
      impossible: m.app_merge_impossible_leads
    },
    contacts: {
      title: m.app_merge_title_contacts,
      crumb: m.app_merge_crumb_contacts,
      which: m.app_merge_which_contacts,
      impossible: m.app_merge_impossible_contacts
    },
    accounts: {
      title: m.app_merge_title_accounts,
      crumb: m.app_merge_crumb_accounts,
      which: m.app_merge_which_accounts,
      impossible: m.app_merge_impossible_accounts
    }
  };
  let text = $derived(TEXT[module]);
  // Split on a marker so the translated sentence stays whole around the bold name.
  let confirmParts = $derived(messageParts(m.app_merge_confirm({ label: slot('label') })));
  let result = $derived(
    kept.fields.map((field, i) => ({
      label: field.label,
      value: field.value || dropped.fields[i].value,
      filled: !field.value && Boolean(dropped.fields[i].value)
    }))
  );
</script>

<PageHeader title={text.title()} center width="820px">
  {#snippet crumb()}
    <a href={resolve(`${module}`)}>{text.crumb()}</a>
    <ChevronRight size={12} />
    <a href={resolve(`${module}/${current.id}`)}>{current.name}</a>
    <ChevronRight size={12} />
    <span>{m.app_merge_crumb()}</span>
  {/snippet}
  {#snippet sub()}
    {m.app_merge_sub()}
  {/snippet}
</PageHeader>

<div class="v2-scroll v2-pad" style="padding-top:18px">
  <form
    class="merge"
    method="POST"
    action="?/merge"
    use:enhance={() => {
      busy = true;
      return async ({ update }) => {
        await update();
        busy = false;
      };
    }}
  >
    <input type="hidden" name="other" value={other.id} />

    {#if form?.error}
      <div class="v2-next refusal" role="alert">
        <TriangleAlert size={17} style="color:var(--v2-rust);flex:none" />
        <div class="v2-next-body">
          <div style="font-weight:600">{m.app_merge_nothing_merged()}</div>
          <div class="v2-sub" style="margin-top:2px">{form.error}</div>
        </div>
      </div>
    {/if}

    <fieldset class="sides">
      <legend class="v2-sr-only">{text.which()}</legend>
      {#each [current, other] as side (side.id)}
        <label class="v2-card side" class:chosen={keep === side.id} class:off={!keepable(side)}>
          <span class="pick">
            <input
              type="radio"
              name="keep"
              value={side.id}
              bind:group={keep}
              disabled={!keepable(side)}
            />
            <span style="font-weight:600">{m.app_merge_keep({ label: label(side) })}</span>
          </span>
          {#if !keepable(side)}
            <span class="v2-sub" style="font-size:11.5px">
              {m.app_merge_not_keepable()}
            </span>
          {/if}
          <dl>
            {#each side.fields as field (field.label)}
              <dt>{field.label}</dt>
              <dd>{field.value || '—'}</dd>
            {/each}
          </dl>
        </label>
      {/each}
    </fieldset>

    {#if possible}
      <section class="v2-card after" aria-labelledby="after-title">
        <div id="after-title" class="v2-label" style="margin-bottom:6px">{m.app_merge_after()}</div>
        <dl>
          {#each result as field (field.label)}
            <dt>{field.label}</dt>
            <dd>
              {field.value || '—'}
              {#if field.filled}<span class="v2-sub">
                  {m.app_merge_from({ label: label(dropped) })}</span
                >{/if}
            </dd>
          {/each}
        </dl>
        <p class="v2-sub" style="margin:8px 0 0;font-size:12px;line-height:1.55">
          {m.app_merge_moves({ dropped: label(dropped), kept: label(kept) })}
        </p>
      </section>

      <label class="confirm">
        <input type="checkbox" name="confirm" bind:checked={confirmed} />
        <span>
          {#each confirmParts as p, i (i)}{#if p.key === 'label'}<strong>{label(dropped)}</strong
              >{:else}{p.text}{/if}{/each}
        </span>
      </label>

      <div class="actions">
        <button class="v2-btn v2-btn-primary" type="submit" disabled={!confirmed || busy}>
          {m.app_merge_into({ label: label(kept) })}
        </button>
        <a class="v2-btn" href={resolve(`${module}/${current.id}`)}>{m.common_cancel()}</a>
      </div>
    {:else}
      <p class="v2-sub" style="font-size:12.5px">
        {text.impossible()}
      </p>
      <div class="actions">
        <a class="v2-btn" href={resolve(`${module}/${current.id}`)}>{m.common_back()}</a>
      </div>
    {/if}
  </form>
</div>

<style>
  .merge {
    max-width: 820px;
    margin: 0 auto;
    padding-bottom: 40px;
  }
  .refusal {
    background: color-mix(in srgb, var(--v2-rust) 9%, transparent);
    border-color: color-mix(in srgb, var(--v2-rust) 28%, transparent);
    margin-bottom: 18px;
  }
  .sides {
    border: 0;
    margin: 0;
    padding: 0;
    display: grid;
    grid-template-columns: 1fr;
    gap: 12px;
  }
  .side {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 14px 16px;
    cursor: pointer;
    min-width: 0;
  }
  .side.chosen {
    border-color: var(--v2-ink);
    box-shadow: inset 0 0 0 1px var(--v2-ink);
  }
  .side.off {
    cursor: default;
    opacity: 0.75;
  }
  .pick {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    font-size: 14px;
    overflow-wrap: anywhere;
  }
  .pick input {
    width: 20px;
    height: 20px;
    flex: none;
  }
  dl {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 5px 12px;
    margin: 0;
    font-size: 12.5px;
  }
  dt {
    color: var(--v2-slate);
  }
  dd {
    margin: 0;
    min-width: 0;
    overflow-wrap: anywhere;
  }
  .after {
    margin-top: 14px;
    padding: 14px 16px;
  }
  .confirm {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    margin: 16px 0 4px;
    font-size: 13px;
    line-height: 1.5;
    min-height: 44px;
  }
  .confirm input {
    width: 20px;
    height: 20px;
    flex: none;
    margin-top: 1px;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 9px;
    margin-top: 16px;
  }
  .actions .v2-btn {
    min-height: 44px;
    max-width: 100%;
    white-space: normal;
    overflow-wrap: anywhere;
  }
  /* 769, so exactly one layout applies at 768: the app's phone rules run up
     to and including 768px. */
  @media (min-width: 769px) {
    .sides {
      grid-template-columns: 1fr 1fr;
    }
  }
</style>
