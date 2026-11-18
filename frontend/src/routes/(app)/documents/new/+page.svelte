<script lang="ts">
  import { resolve } from '$app/paths';
  import { untrack, tick } from 'svelte';
  import { SvelteSet } from 'svelte/reactivity';
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import { TriangleAlert, Upload, Users, Lock } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps, SubmitFunction } from './$types';

  let { data, form: result }: PageProps = $props();

  /**
   * A document is a file, a title, and an audience. This asks for exactly that.
   *
   * VALIDATION HERE IS A UX HINT, NOT A RULE. The serializer requires a title
   * and a file, rejects a duplicate title within the org, and re-scopes every
   * share to the caller's org. Curl and the mobile client reach the API
   * without passing through this page. See CLAUDE.md, "API Validation &
   * Authorization". Note what is NOT on this form: org and created_by, both
   * server-derived from the session.
   *
   * The share pickers only list people and teams in this org because that is
   * all the options endpoint returns; the view enforces the same boundary when
   * it saves. An unshared upload is not an error. It is a document only the
   * uploader and admins can open, which the form says plainly.
   */
  const previous = untrack(() => result?.values);

  let title = $state(previous?.title ?? '');
  // A rejected submit cannot re-fill a file input (browsers forbid it), so the
  // file is always chosen fresh. We only track whether one is currently picked.
  let fileName = $state('');
  // SvelteSet is reactive on mutation, so `.add()`/`.delete()` below re-render
  // the checkboxes and the reach line without reassigning the whole set.
  let sharedTo = new SvelteSet((previous?.shared_to ?? []).map(String));
  let sharedTeams = new SvelteSet((previous?.teams ?? []).map(String));

  let touched = $state({} as Record<string, boolean>);
  let submitted = $state(false);

  const REQUIRED = ['title', 'file'];

  let errors = $derived.by(() => {
    const e: Record<string, string> = {};
    if (!title.trim()) e.title = m.documents_new_error_title();
    if (!fileName) e.file = m.documents_error_file();
    return e;
  });

  let valid = $derived(Object.keys(errors).length === 0);
  const show = (field: string) => (touched[field] || submitted) && errors[field];

  let reach = $derived(sharedTo.size + sharedTeams.size);

  function onFile(ev: Event) {
    const input = ev.currentTarget as HTMLInputElement;
    fileName = input.files?.[0]?.name ?? '';
    touched.file = true;
  }

  function toggle(set: SvelteSet<string>, id: string) {
    if (set.has(id)) set.delete(id);
    else set.add(id);
  }

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

<PageHeader title={m.documents_new_title()} center>
  {#snippet crumb()}<a href={resolve('documents')}>{m.documents_crumb()}</a> ›{/snippet}
  {#snippet sub()}
    {m.documents_new_sub()}
  {/snippet}
</PageHeader>

<div class="v2-scroll v2-pad" style="padding-top:18px">
  <form
    class="v2-form"
    method="POST"
    action="?/create"
    enctype="multipart/form-data"
    use:enhance={check}
    novalidate
  >
    {#if result?.error}
      <div
        class="v2-next"
        style="background:color-mix(in srgb, var(--v2-rust) 9%, transparent);border-color:color-mix(in srgb, var(--v2-rust) 28%, transparent);margin-bottom:18px"
        role="alert"
      >
        <TriangleAlert size={17} style="color:var(--v2-rust);flex:none" />
        <div class="v2-next-body">
          <div style="font-weight:600">{m.documents_new_refused()}</div>
          <div class="v2-sub" style="margin-top:2px">{result.error}</div>
        </div>
      </div>
    {/if}

    <div class="v2-field">
      <label for="f-title">{m.documents_field_title()}</label>
      <input
        id="f-title"
        name="title"
        class="v2-input"
        bind:value={title}
        onblur={() => (touched.title = true)}
        aria-invalid={show('title') ? 'true' : undefined}
        aria-describedby={show('title') ? 'e-title' : 'h-title'}
        placeholder={m.documents_new_title_placeholder()}
      />
      {#if show('title')}
        <p class="v2-error" id="e-title">{errors.title}</p>
      {:else}
        <p class="v2-hint" id="h-title">
          {m.documents_new_title_hint()}
        </p>
      {/if}
    </div>

    <div class="v2-field">
      <label for="f-file">{m.documents_field_file()}</label>
      <input
        id="f-file"
        name="document_file"
        class="v2-input v2-file"
        type="file"
        onchange={onFile}
        aria-invalid={show('file') ? 'true' : undefined}
        aria-describedby={show('file') ? 'e-file' : 'h-file'}
      />
      {#if show('file')}
        <p class="v2-error" id="e-file">{errors.file}</p>
      {:else}
        <p class="v2-hint" id="h-file">
          {fileName
            ? m.documents_new_file_selected({ name: fileName })
            : m.documents_new_file_hint()}
        </p>
      {/if}
    </div>

    <fieldset class="v2-field share">
      <legend>{m.documents_share_legend()}</legend>
      <p class="v2-hint" style="margin-top:0">
        {#if reach === 0}
          <span class="unshared"
            ><Lock size={11} />
            {m.documents_new_unshared()}</span
          >
        {:else}
          {#each messageParts(m.documents_share_reach( { count: reach, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
                class="v2-num">{reach}</span
              >{:else}{p.text}{/if}{/each}
        {/if}
      </p>

      {#if data.people?.length}
        <div class="share-label">{m.documents_share_people()}</div>
        <div class="share-grid">
          {#each data.people as p (p.id)}
            <label class="share-opt">
              <input
                type="checkbox"
                name="shared_to"
                value={p.id}
                checked={sharedTo.has(String(p.id))}
                onchange={() => toggle(sharedTo, String(p.id))}
              />
              <span>{p.name}</span>
            </label>
          {/each}
        </div>
      {/if}

      {#if data.teams?.length}
        <div class="share-label"><Users size={12} /> {m.documents_share_teams()}</div>
        <div class="share-grid">
          {#each data.teams as t (t.id)}
            <label class="share-opt">
              <input
                type="checkbox"
                name="teams"
                value={t.id}
                checked={sharedTeams.has(String(t.id))}
                onchange={() => toggle(sharedTeams, String(t.id))}
              />
              <span>{t.name}</span>
            </label>
          {/each}
        </div>
      {/if}

      {#if !data.people?.length && !data.teams?.length}
        <p class="v2-sub" style="font-size:12px">
          {m.documents_new_nobody_to_share()}
        </p>
      {/if}
    </fieldset>

    <div style="display:flex;gap:8px;align-items:center;margin-top:22px">
      <button class="v2-btn v2-btn-primary" type="submit"
        ><Upload size={15} /> {m.documents_new_submit()}</button
      >
      <a class="v2-btn" href={resolve('documents')}>{m.documents_cancel()}</a>
      <span class="v2-sub" style="margin-left:auto;font-size:12px">
        {#each messageParts(m.documents_new_required_done( { done: slot('done'), total: slot('total') } )) as p, i (i)}{#if p.key === 'done'}<span
              class="v2-num">{REQUIRED.filter((f) => !errors[f]).length}</span
            >{:else if p.key === 'total'}<span class="v2-num">{REQUIRED.length}</span
            >{:else}{p.text}{/if}{/each}
      </span>
    </div>
  </form>
</div>

<style>
  .share {
    border: 1px solid var(--v2-line-soft);
    border-radius: 8px;
    padding: 14px 16px;
  }
  .share legend {
    font-weight: 600;
    padding: 0 6px;
  }
  .unshared {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    color: var(--v2-clay);
  }
  .share-label {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 12px;
    font-weight: 600;
    color: var(--v2-slate);
    margin: 12px 0 6px;
  }
  .share-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 6px 14px;
  }
  @media (max-width: 560px) {
    .share-grid {
      grid-template-columns: 1fr;
    }
  }
  .share-opt {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13.5px;
    cursor: pointer;
  }
  .share-opt input {
    flex: none;
  }
</style>
