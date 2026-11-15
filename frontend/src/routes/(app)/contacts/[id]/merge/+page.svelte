<script>
  import MergeCompare from '#lib/v2/components/MergeCompare.svelte';
  import { m } from '#lib/paraglide/messages.js';

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();
</script>

<svelte:head>
  <title>{m.contacts_merge_title()}</title>
</svelte:head>

<MergeCompare {data} {form} />
