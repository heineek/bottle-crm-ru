<script lang="ts">
  /**
   * A webhook key, shown in the one response that carries it (a create or a
   * replace) and gone on the next load: reads only carry `key_hint`.
   */
  import CopyValue from './CopyValue.svelte';
  import { m } from '#lib/paraglide/messages.js';

  let {
    title,
    url = '',
    secret,
    replaced = false
  }: { title: string; url?: string; secret: string; replaced?: boolean } = $props();
</script>

<div
  class="v2-card"
  style="padding:15px 16px;margin-bottom:18px;border-color:color-mix(in srgb, var(--v2-moss) 40%, var(--v2-line))"
>
  <div style="font-weight:650;font-size:13px">{title}</div>
  <p class="v2-sub" style="font-size:12px;margin:4px 0 12px;line-height:1.5">
    {m.settings_lead_capture_key_once()}
    {#if replaced}
      {m.settings_lead_capture_key_old_works()}
    {/if}
  </p>
  <div style="display:flex;flex-direction:column;gap:12px">
    {#if url}
      <CopyValue label={m.settings_lead_capture_webhook_url()} value={url} id="once-url" />
    {/if}
    <CopyValue label={m.settings_lead_capture_key()} value={secret} id="once-key" />
  </div>
</div>
