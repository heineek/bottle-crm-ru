<script lang="ts">
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import AdminsOnly from '#lib/v2/components/automation/AdminsOnly.svelte';
  import AutomationCrumb from '#lib/v2/components/automation/AutomationCrumb.svelte';
  import RuleEditor from '#lib/v2/components/automation/RuleEditor.svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { billingHref } from '#lib/v2/billing.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();
</script>

{#if data.forbidden}
  <PageHeader title={m.settings_automation_new_rule()}>
    {#snippet crumb()}<AutomationCrumb />{/snippet}
  </PageHeader>
  <div class="v2-scroll">
    <div class="v2-pad" style="padding-top:16px">
      <AdminsOnly />
    </div>
  </div>
{:else}
  <RuleEditor catalogue={data.catalogue} {form} plansHref={billingHref(data)} />
{/if}
