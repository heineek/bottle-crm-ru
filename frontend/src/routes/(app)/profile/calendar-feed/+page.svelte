<script>
  /**
   * Your task calendar feed (G14).
   *
   * A private URL that Google Calendar, Outlook or Apple Calendar polls for
   * your open tasks with a due date, each shown as an all-day event carrying
   * the title, the priority and a link back here. Never notes, and never a
   * contact, account or other record name.
   *
   * THE URL IS SHOWN ONCE
   * The server stores only a hash of it, so there is nothing to show again on
   * a later visit. The reveal below is the action's response, and it is gone
   * on the next load. Lost it? Regenerate, which also retires the old one.
   */
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import { relativeDays, shortDate } from '#lib/v2/format.js';
  import { resolve } from '$app/paths';
  import { enhance } from '$app/forms';
  import { CalendarDays, Copy, Check, ShieldAlert } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();

  let feed = $derived(data.feed);
  let busy = $state(false);
  let copied = $state(false);

  /** @param {string} value */
  async function copyUrl(value) {
    try {
      await navigator.clipboard.writeText(value);
      copied = true;
      setTimeout(() => (copied = false), 1600);
    } catch {
      // Clipboard blocked (no https or no permission). The URL is on screen to
      // select by hand.
    }
  }
</script>

<PageHeader title={m.profile_feed_title()}>
  {#snippet crumb()}<a href={resolve('profile')}>{m.profile_tokens_crumb()}</a> ›{/snippet}
  {#snippet sub()}
    {#if feed.enabled}
      {m.profile_feed_sub_on({ date: shortDate(feed.created_at) })}
    {:else}
      {m.profile_feed_sub_off()}
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad feed" style="padding-top:18px;padding-bottom:32px;max-width:720px">
    {#if form?.url}
      <!-- The one and only time this URL is shown. -->
      <div
        class="v2-card"
        style="padding:15px 16px;margin-bottom:18px;border-color:color-mix(in srgb, var(--v2-moss) 40%, var(--v2-line))"
      >
        <div style="font-weight:650;font-size:13px">{m.profile_feed_url_title()}</div>
        <p class="v2-sub" style="font-size:12px;margin:4px 0 10px">
          {m.profile_feed_url_body()}
        </p>
        <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
          <code
            class="v2-num"
            style="flex:1;min-width:0;background:var(--v2-bg-sunk);border:1px solid var(--v2-line);border-radius:var(--v2-radius);padding:9px 11px;font-size:12.5px;word-break:break-all"
          >
            {form.url}
          </code>
          <button class="v2-btn" type="button" onclick={() => copyUrl(form.url)}>
            {#if copied}<Check size={13} />{m.profile_tokens_copied()}{:else}<Copy
                size={13}
              />{m.profile_tokens_copy()}{/if}
          </button>
        </div>
      </div>
    {/if}

    {#if form?.error}
      <div style="margin-bottom:16px">
        <NextAction label={m.profile_tokens_error_label()} text={form.error} tone="rust" />
      </div>
    {/if}

    <div class="v2-card" style="overflow:hidden;margin-bottom:20px">
      <div class="v2-setting">
        <CalendarDays size={16} style="color:var(--v2-slate);flex:none" />
        <div class="v2-setting-body">
          <b>{m.profile_feed_intro_title()}</b>
          <span class="v2-sub" style="font-size:11.5px">
            {m.profile_feed_intro_body()}
          </span>
        </div>
        {#if feed.enabled}
          <Pill tone="moss" dot>{m.profile_feed_on()}</Pill>
        {:else}
          <Pill>{m.profile_feed_off()}</Pill>
        {/if}
      </div>
      {#if feed.enabled}
        <div class="v2-setting">
          <div class="v2-setting-body">
            <b>{m.profile_feed_last_fetched()}</b>
            <span class="v2-sub" style="font-size:11.5px">
              {#if feed.last_used_at}
                {m.profile_feed_read_at({ when: relativeDays(feed.last_used_at) })}
              {:else}
                {m.profile_feed_never_read()}
              {/if}
            </span>
          </div>
        </div>
        <div class="v2-setting feed-actions">
          <div class="v2-setting-body">
            <b>{m.profile_feed_regen_title()}</b>
            <span class="v2-sub" style="font-size:11.5px">
              {m.profile_feed_regen_body()}
            </span>
          </div>
          <ConfirmAction
            action="?/issue"
            label={m.profile_feed_regen_label()}
            confirmLabel={m.profile_feed_regen_confirm()}
            explain={m.profile_feed_regen_explain()}
          />
          <ConfirmAction
            action="?/disable"
            label={m.profile_feed_off_label()}
            confirmLabel={m.profile_feed_off_label()}
            explain={m.profile_feed_off_explain()}
          />
        </div>
      {:else}
        <form
          method="POST"
          action="?/issue"
          class="v2-setting feed-actions"
          use:enhance={() => {
            busy = true;
            return async (/** @type {any} */ { update }) => {
              await update();
              busy = false;
            };
          }}
        >
          <div class="v2-setting-body">
            <b>{m.profile_feed_on_title()}</b>
            <span class="v2-sub" style="font-size:11.5px">
              {m.profile_feed_on_body()}
            </span>
          </div>
          <button class="v2-btn v2-btn-primary" type="submit" disabled={busy}>
            {m.profile_feed_on_button()}
          </button>
        </form>
      {/if}
    </div>

    <div class="v2-label" style="margin-bottom:10px">{m.profile_feed_subscribe()}</div>
    <div class="v2-card" style="overflow:hidden;margin-bottom:20px">
      <div class="v2-setting">
        <div class="v2-setting-body">
          <b>{m.profile_feed_google()}</b>
          <span class="v2-sub" style="font-size:11.5px">
            {m.profile_feed_google_body()}
          </span>
        </div>
      </div>
      <div class="v2-setting">
        <div class="v2-setting-body">
          <b>{m.profile_feed_outlook()}</b>
          <span class="v2-sub" style="font-size:11.5px">
            {m.profile_feed_outlook_body()}
          </span>
        </div>
      </div>
      <div class="v2-setting">
        <div class="v2-setting-body">
          <b>{m.profile_feed_apple()}</b>
          <span class="v2-sub" style="font-size:11.5px">
            {m.profile_feed_apple_body()}
          </span>
        </div>
      </div>
    </div>

    <div
      style="display:flex;gap:10px;align-items:flex-start;padding:14px 16px;border:1px solid var(--v2-line);border-radius:var(--v2-radius)"
    >
      <ShieldAlert size={16} style="color:var(--v2-clay);flex:none;margin-top:1px" />
      <div>
        <div style="font-weight:600;font-size:13px">{m.profile_feed_key_title()}</div>
        <p class="v2-sub" style="font-size:12px;margin:4px 0 0">
          {m.profile_feed_key_body()}
        </p>
      </div>
    </div>
  </div>
</div>

<style>
  .feed-actions {
    flex-wrap: wrap;
  }
  @media (max-width: 768px) {
    /* A thumb's tap target. The two-step buttons are small by default. */
    .feed :global(.v2-btn) {
      min-height: 44px;
    }
    /* The explanation takes the row and the buttons wrap under it, rather
       than squeezing the text into a column a few words wide. */
    .feed-actions .v2-setting-body {
      flex-basis: 100%;
    }
  }
</style>
