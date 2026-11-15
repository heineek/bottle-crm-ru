<script>
  import { resolve } from '$app/paths';
  import '../../../../app.css';
  import '#lib/v2/styles/v2.css';
  import imgLogo from '#lib/assets/images/logo.png';
  import { m } from '#lib/paraglide/messages.js';

  let { data, form } = $props();

  const error = $derived(form?.error ?? data.error);
  let submitting = $state(false);
</script>

<svelte:head>
  <title>{m.public_login_title()}</title>
  <!-- same-origin, not no-referrer: under no-referrer the browser sends
       `Origin: null` on the form POST, and SvelteKit's CSRF check refuses it
       as cross-site (403). same-origin still keeps the token in this URL out of
       any Referer sent to another site. -->
  <meta name="referrer" content="same-origin" />
</svelte:head>

<div class="v2-root v2-auth">
  <div class="v2-auth-box">
    <a href={resolve('')} class="v2-auth-brand">
      <img src={imgLogo} alt="" />
      <b>BottleCRM</b>
    </a>

    <div class="v2-auth-card" style="text-align:center">
      {#if error}
        <div class="v2-auth-head" style="margin-bottom:16px">
          <h1>{m.public_verify_invalid_title()}</h1>
          <p>{error}</p>
        </div>
        <a href={resolve('login')} class="v2-btn v2-btn-block"
          >{m.public_verify_back_to_sign_in()}</a
        >
      {:else}
        <div class="v2-auth-head" style="margin-bottom:16px">
          <h1>{m.public_verify_heading()}</h1>
          <p>{m.public_verify_hint()}</p>
        </div>
        <!-- A plain submit, never an automatic one: see +page.server.js. No
             `action` attribute, so it posts back to this URL, token included. -->
        <form method="POST" onsubmit={() => (submitting = true)}>
          <button type="submit" class="v2-btn v2-btn-primary v2-btn-block" disabled={submitting}>
            {#if submitting}
              <span class="v2-spin"></span>
              <span>{m.public_verify_signing_in()}</span>
            {:else}
              <span>{m.public_verify_continue()}</span>
            {/if}
          </button>
        </form>
      {/if}
    </div>
  </div>
</div>
