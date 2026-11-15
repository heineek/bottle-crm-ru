<script>
  import { resolve } from '$app/paths';
  import '../../../app.css';
  import '#lib/v2/styles/v2.css';
  import { enhance } from '$app/forms';

  import imgGoogle from '#lib/assets/images/google.svg';
  import imgLogo from '#lib/assets/images/logo.png';
  import { Mail, Check } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';

  let { data = {} } = $props();

  let isLoading = $state(false);
  let email = $state('');
  let magicLinkSent = $state(false);
  let isSendingLink = $state(false);
  let magicLinkError = $state('');

  function handleGoogleLogin() {
    isLoading = true;
  }

  function handleMagicLink() {
    isSendingLink = true;
    magicLinkError = '';
    return async ({ result }) => {
      isSendingLink = false;
      if (result?.type === 'success') {
        magicLinkSent = true;
      } else if (result?.type === 'failure') {
        magicLinkError = result.data?.error || m.public_login_generic_error();
      } else if (!result) {
        magicLinkError = m.public_login_generic_error();
      }
    };
  }
</script>

<svelte:head>
  <title>{m.public_login_title()}</title>
  <meta name="description" content={m.public_login_meta_description()} />
</svelte:head>

<div class="v2-root v2-auth">
  <div class="v2-auth-box">
    <a href={resolve('')} class="v2-auth-brand">
      <img src={imgLogo} alt="" />
      <b>BottleCRM</b>
    </a>

    <div class="v2-auth-card">
      <div class="v2-auth-head">
        <h1>{m.public_login_heading()}</h1>
        <p>{m.public_login_subtitle()}</p>
      </div>

      <!-- Primary path. Google's mark keeps a white tile so it stays legible on
           Ember; the whole button is the one Ember action on this screen. -->
      <a
        href={data['google_url']}
        rel="external"
        onclick={handleGoogleLogin}
        class="v2-btn v2-btn-primary v2-btn-block"
        style:pointer-events={isLoading ? 'none' : null}
        style:opacity={isLoading ? '0.85' : null}
      >
        {#if isLoading}
          <span class="v2-spin"></span>
          <span>{m.public_login_redirecting()}</span>
        {:else}
          <img src={imgGoogle} alt="" class="v2-auth-gicon" />
          <span>{m.public_login_google()}</span>
        {/if}
      </a>

      <div class="v2-auth-divider">{m.public_login_or()}</div>

      {#if magicLinkSent}
        <div class="v2-auth-note v2-auth-note-ok">
          <Check />
          <div>
            <b>{m.public_login_check_email()}</b>
            <div style="font-weight:400;margin-top:2px">
              {m.public_login_link_sent()}
            </div>
          </div>
        </div>
      {:else}
        <form
          method="POST"
          use:enhance={handleMagicLink}
          style="display:flex;flex-direction:column;gap:9px"
        >
          <label for="email" class="v2-sr-only">{m.public_login_email_label()}</label>
          <input
            id="email"
            type="email"
            name="email"
            class="v2-input"
            placeholder="you@company.com"
            required
            bind:value={email}
            disabled={isSendingLink}
          />
          <button type="submit" class="v2-btn v2-btn-block" disabled={isSendingLink}>
            {#if isSendingLink}
              <span class="v2-spin"></span>
              <span>{m.public_login_sending()}</span>
            {:else}
              <Mail size={15} />
              <span>{m.public_login_email_button()}</span>
            {/if}
          </button>
        </form>
        {#if magicLinkError}
          <div class="v2-auth-note v2-auth-note-bad" style="margin-top:11px">
            <span>{magicLinkError}</span>
          </div>
        {/if}
      {/if}
    </div>

    <p class="v2-sub" style="text-align:center;margin:14px 0 0">
      {m.public_login_new_here()}
    </p>

    <div class="v2-auth-foot">
      <a href="https://bottlecrm.io/privacy-policy">{m.public_login_privacy()}</a>
      <span class="v2-auth-dot"></span>
      <a href="https://bottlecrm.io/terms-of-service">{m.public_login_terms()}</a>
      <span class="v2-auth-dot"></span>
      <a href="https://github.com/django-crm/Django-CRM" target="_blank" rel="noopener">GitHub</a>
    </div>
  </div>
</div>
