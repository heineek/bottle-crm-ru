<script lang="ts">
  import MergeCompare from '#lib/v2/components/MergeCompare.svelte';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();
</script>

<svelte:head>
  <title>{m.accounts_merge_title({ singular: data.singular })}</title>
</svelte:head>

<MergeCompare {data} {form} />
