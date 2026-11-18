<script lang="ts">
  import MergeCompare from '#lib/v2/components/MergeCompare.svelte';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();
</script>

<svelte:head>
  <title>{m.contacts_merge_title()}</title>
</svelte:head>

<MergeCompare {data} {form} />
