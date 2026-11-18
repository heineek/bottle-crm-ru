<script lang="ts">
  import '../../../app.css';
  import '#lib/v2/styles/v2.css';
  import { onMount } from 'svelte';
  import { m } from '#lib/paraglide/messages.js';

  onMount(() => {
    setTimeout(() => {
      window.location.href = '/org';
    });
  });
</script>

<svelte:head>
  <title>{m.public_bounce_title()}</title>
</svelte:head>

<div class="v2-root v2-auth">
  <div class="v2-auth-box" style="text-align:center">
    <div class="v2-spin" style="width:24px;height:24px;margin:0 auto;color:var(--v2-ember)"></div>
    <p class="v2-sub" style="margin-top:12px">{m.public_bounce_signing_in()}</p>
  </div>
</div>
