<script>
  /**
   * The public help center: one switch and one address.
   *
   * Turning it on publishes this org's approved, published articles to anyone
   * with the link, and to search engines. That is the whole consequence, so the
   * page says it next to the switch rather than leaving it to be discovered.
   *
   * Any member can see whether it is on and open the public page; only an
   * admin gets the form. The API enforces that regardless of what is shown.
   */
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import SettingsFormPanel from '#lib/v2/components/SettingsFormPanel.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import { ExternalLink, Globe } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';

  const publishesBody = $derived(
    messageParts(m.settings_helpcenter_publishes_body({ path: slot('path') }))
  );

  /** @type {{ data: any, form: any }} */
  let { data, form } = $props();

  let editing = $state(false);

  let s = $derived(data.settings);
  let live = $derived(s.help_center_enabled && !!s.public_url);

  // A refused save re-renders the form with what was typed, not what is stored.
  let draft = $derived(form?.update?.values ?? null);
</script>

<PageHeader title={m.settings_helpcenter_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {live ? m.settings_helpcenter_sub_live() : m.settings_helpcenter_sub_off()}
  {/snippet}
  {#snippet actions()}
    {#if s.can_edit && !editing}
      <button class="v2-btn v2-btn-primary" onclick={() => (editing = true)}
        >{m.settings_helpcenter_edit()}</button
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:16px;padding-bottom:32px">
    {#if editing}
      <SettingsFormPanel
        title={m.settings_helpcenter_title()}
        action="?/update"
        error={form?.update?.error}
        submitLabel={m.settings_helpcenter_save()}
        oncancel={() => (editing = false)}
        ondone={() => (editing = false)}
      >
        {#snippet fields()}
          <div class="v2-field v2-sfp-wide">
            <label for="hc-enabled">{m.settings_helpcenter_public_label()}</label>
            <label class="hc-check">
              <input
                id="hc-enabled"
                type="checkbox"
                name="help_center_enabled"
                value="true"
                checked={draft ? draft.enabled : s.help_center_enabled}
              />
              {m.settings_helpcenter_public_check()}
            </label>
          </div>

          <div class="v2-field v2-sfp-wide">
            <label for="hc-slug">{m.settings_helpcenter_address_label()}</label>
            <div class="hc-slug">
              <span class="v2-sub">/help-center/</span>
              <input
                id="hc-slug"
                class="v2-input"
                name="help_center_slug"
                value={draft ? draft.slug : (s.help_center_slug ?? '')}
                maxlength="50"
                autocomplete="off"
                autocapitalize="none"
                spellcheck="false"
                placeholder={m.settings_helpcenter_slug_placeholder()}
              />
            </div>
            <p class="v2-hint">
              {m.settings_helpcenter_slug_hint()}
            </p>
          </div>
        {/snippet}
      </SettingsFormPanel>
    {/if}

    <div class="v2-label" style="margin-bottom:10px">{m.settings_helpcenter_current_heading()}</div>
    <div class="v2-card" style="overflow:hidden;margin-bottom:22px">
      <div class="v2-setting">
        <div class="v2-setting-body">
          <b>{m.settings_helpcenter_public_label()}</b>
          <span class="v2-sub" style="font-size:11.5px">
            {m.settings_helpcenter_off_hint()}
          </span>
        </div>
        <Pill tone={s.help_center_enabled ? 'moss' : 'slate'}>
          {s.help_center_enabled ? m.settings_helpcenter_on() : m.settings_helpcenter_off()}
        </Pill>
      </div>
      <div class="v2-setting">
        <div class="v2-setting-body">
          <b>{m.settings_helpcenter_address_label()}</b>
          <span class="v2-sub hc-wrap" style="font-size:11.5px">
            {s.public_url ?? m.settings_helpcenter_not_chosen()}
          </span>
        </div>
      </div>
      {#if live}
        <!-- eslint-disable svelte/no-navigation-without-resolve -- an absolute URL
             the API builds from FRONTEND_URL, opened in a new tab -->
        <a class="v2-setting hc-open" href={s.public_url} target="_blank" rel="noopener noreferrer">
          <div class="v2-setting-body">
            <b>{m.settings_helpcenter_open_page()}</b>
            <span class="v2-sub" style="font-size:11.5px"
              >{m.settings_helpcenter_open_page_hint()}</span
            >
          </div>
          <ExternalLink size={15} style="color:var(--v2-slate);flex:none" />
        </a>
        <!-- eslint-enable svelte/no-navigation-without-resolve -->
      {/if}
    </div>

    <div class="v2-label" style="margin-bottom:10px">
      {m.settings_helpcenter_publishes_heading()}
    </div>
    <div class="v2-card" style="padding:15px 16px">
      <div style="display:flex;gap:10px;align-items:flex-start">
        <Globe size={16} style="color:var(--v2-slate);flex:none;margin-top:2px" />
        <p class="v2-sub" style="font-size:12.5px;margin:0;line-height:1.5">
          {#each publishesBody as p, i (i)}{#if p.key}<span class="v2-num">/sitemap.xml</span
              >{:else}{p.text}{/if}{/each}
        </p>
      </div>
    </div>
  </div>
</div>

<style>
  .hc-check {
    display: flex;
    gap: 8px;
    align-items: center;
    font-weight: 400;
    min-height: 44px;
  }
  .hc-slug {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }
  .hc-slug input {
    flex: 1;
    min-width: 0;
    min-height: 44px;
    /* 16px stops iOS Safari zooming the viewport on focus. */
    font-size: 16px;
  }
  .hc-wrap {
    overflow-wrap: anywhere;
  }
  .hc-open {
    text-decoration: none;
    color: inherit;
  }
</style>
