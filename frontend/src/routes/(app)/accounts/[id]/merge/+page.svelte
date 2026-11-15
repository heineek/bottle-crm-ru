<script>
  import MergeCompare from '#lib/v2/components/MergeCompare.svelte';
  import { m } from '#lib/paraglide/messages.js';

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();
</script>

<svelte:head>
  <title>{m.accounts_merge_title({ singular: data.singular })}</title>
</svelte:head>

<MergeCompare {data} {form} />
