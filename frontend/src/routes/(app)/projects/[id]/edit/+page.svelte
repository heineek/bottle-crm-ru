<script lang="ts">
  import { resolve } from '$app/paths';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import ProjectForm from '#lib/v2/components/ProjectForm.svelte';
  import { isOrgAdmin } from '#lib/admin.js';
  import { ChevronRight } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  /** Only a refused save carries per-field messages; a form that would not build has none. */
  let fieldErrors = $derived(
    form && 'fieldErrors' in form
      ? (form.fieldErrors as Record<string, string> | undefined)
      : undefined
  );
</script>

<PageHeader title={m.projects_edit_title()} record center width="62ch">
  {#snippet crumb()}
    <a href={resolve('projects')}>{m.projects_title()}</a>
    <ChevronRight size={12} />
    <a href={resolve(`projects/${data.project.id}`)}>{data.project.name}</a>
    <ChevronRight size={12} />
    <span>{m.common_edit()}</span>
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad">
    <ProjectForm
      action="?/save"
      submitLabel={m.projects_save_changes()}
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
      edit
      cancelHref={`/projects/${data.project.id}`}
    />
  </div>
</div>
