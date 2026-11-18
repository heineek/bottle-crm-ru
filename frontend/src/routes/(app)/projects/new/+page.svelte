<script lang="ts">
  import { resolve } from '$app/paths';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import ProjectForm from '#lib/v2/components/ProjectForm.svelte';
  import { isOrgAdmin } from '#lib/admin.js';
  import { ChevronRight } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  /** Only a refused save carries per-field messages; a form that would not build has none. */
  let fieldErrors = $derived(
    form && 'fieldErrors' in form
      ? (form.fieldErrors as Record<string, string> | undefined)
      : undefined
  );
</script>

<PageHeader title={m.projects_new_title()} record center width="62ch">
  {#snippet crumb()}
    <a href={resolve('projects')}>{m.projects_title()}</a>
    <ChevronRight size={12} />
    <span>{m.projects_crumb_new()}</span>
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad">
    {#if data.fromDeal}
      <p class="v2-sub note">
        {#each messageParts(m.projects_from_deal_note({ deal: slot('deal') })) as p, i (i)}{#if p.key === 'deal'}{data
              .fromDeal.name}{:else}{p.text}{/if}{/each}
      </p>
    {:else if data.draftMissed}
      <p class="v2-sub note">
        {m.projects_draft_missed()}
      </p>
    {/if}
    <ProjectForm
      action="?/create"
      submitLabel={m.projects_create_button()}
      values={data.values}
      typed={form?.values}
      error={form?.error}
      accounts={data.accounts}
      deals={data.deals}
      people={data.people}
      peopleFailed={data.peopleFailed}
      stored={data.stored}
      customFields={data.customFields}
      isAdmin={isOrgAdmin(data)}
      {fieldErrors}
      cancelHref={data.fromDeal?.id ? `/pipeline/${data.fromDeal.id}` : '/projects'}
    />
  </div>
</div>

<style>
  .note {
    max-width: 62ch;
    margin: 16px auto 0;
    font-size: 12.5px;
  }
</style>
