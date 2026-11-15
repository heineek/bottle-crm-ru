<script>
  /**
   * Two steps, one page: ask for the email, then ask for the code that was
   * emailed. The first step's confirmation is deliberately unconditional. It
   * says the same thing whether or not the address belongs to a contact here,
   * because saying anything else would let a stranger test which of their
   * customers work with this company.
   */
  import { enhance } from '$app/forms';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import PortalShell from '#lib/v2/components/PortalShell.svelte';

  let { form } = $props();

  let stage = $derived(form?.stage ?? 'request');
  let email = $derived(form?.email ?? '');

  let sent = $derived(messageParts(m.public_portal_login_code_sent({ email: slot('email') })));
</script>

<svelte:head>
  <title>{m.public_portal_login_title()}</title>
</svelte:head>

<PortalShell>
  <div class="card">
    <h1>{m.public_portal_login_heading()}</h1>

    {#if stage === 'code'}
      <p class="lede">
        {#each sent as p, i (i)}{#if p.key}<strong>{email}</strong>{:else}{p.text}{/if}{/each}
      </p>

      <form method="POST" action="?/verify" use:enhance>
        <input type="hidden" name="email" value={email} />
        <label for="code">{m.public_portal_login_code_label()}</label>
        <input
          id="code"
          name="code"
          inputmode="numeric"
          autocomplete="one-time-code"
          pattern="[0-9]*"
          maxlength="6"
          placeholder="000000"
          required
        />
        {#if form?.error}<p class="err">{form.error}</p>{/if}
        <button type="submit">{m.public_portal_login_sign_in()}</button>
      </form>

      <form method="POST" action="?/request" use:enhance class="again">
        <input type="hidden" name="email" value={email} />
        <button type="submit" class="link">{m.public_portal_login_resend()}</button>
      </form>
    {:else}
      <p class="lede">
        {m.public_portal_login_lede()}
      </p>

      <form method="POST" action="?/request" use:enhance>
        <label for="email">{m.common_email()}</label>
        <input
          id="email"
          name="email"
          type="email"
          autocomplete="email"
          placeholder="you@company.com"
          required
        />
        {#if form?.error}<p class="err">{form.error}</p>{/if}
        <button type="submit">{m.public_portal_login_send_code()}</button>
      </form>
    {/if}
  </div>
</PortalShell>

<style>
  .card {
    background: var(--v2-card, #fff);
    border: 1px solid var(--v2-rule, #e5e7eb);
    border-radius: 10px;
    padding: 28px 24px;
  }
  h1 {
    margin: 0 0 6px;
    font-size: 21px;
    font-weight: 600;
  }
  .lede {
    margin: 0 0 20px;
    color: var(--v2-slate, #6b7280);
    font-size: 14px;
  }
  label {
    display: block;
    margin-bottom: 6px;
    font-size: 13px;
    font-weight: 500;
  }
  input {
    width: 100%;
    box-sizing: border-box;
    /* 16px keeps iOS Safari from zooming the viewport on focus, which on a
       phone reads as the page jumping when you tap the field. */
    font-size: 16px;
    padding: 12px;
    border: 1px solid var(--v2-rule, #d1d5db);
    border-radius: 8px;
  }
  #code {
    letter-spacing: 8px;
    text-align: center;
    font-variant-numeric: tabular-nums;
  }
  button {
    margin-top: 16px;
    width: 100%;
    /* Comfortably over the 44px tap target floor. */
    min-height: 46px;
    font-size: 15px;
    border: 0;
    border-radius: 8px;
    background: var(--v2-ink, #111827);
    color: #fff;
    cursor: pointer;
  }
  .again {
    margin-top: 4px;
  }
  button.link {
    background: none;
    color: var(--v2-slate, #6b7280);
    text-decoration: underline;
    min-height: 44px;
    font-size: 13px;
  }
  .err {
    margin: 10px 0 0;
    color: var(--v2-rust, #b91c1c);
    font-size: 13px;
  }
</style>
