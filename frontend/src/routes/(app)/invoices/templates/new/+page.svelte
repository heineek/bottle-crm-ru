<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * A new invoice template: name, the two brand colours, an optional logo, and
   * the boilerplate text (notes, terms, footer) new invoices start with.
   *
   * SCOPE, ON PURPOSE. No `template_html` / `template_css` input anywhere on
   * this page, and no `{@html}` anywhere in this app. Both fields are org-
   * authored markup that WeasyPrint renders into a PDF server-side. A new
   * template starts from the built-in layout, and replacing that whole
   * document is a deliberate follow-up on an existing template rather than
   * part of naming a new one, so the edit page owns those two fields. See
   * `templates.js` for the full reasoning, including the older reason this
   * page gave, which the editor route made obsolete.
   *
   * VALIDATION HERE IS A UX HINT, NOT A RULE. `POST /api/invoices/templates/`
   * is admin-gated (`_forbid_non_admin_template`) and enforces that
   * regardless of what this page shows; curl and the mobile client reach the
   * API without passing through here. The two colour inputs use
   * `type="color"` so the browser can only ever submit a valid six-digit hex
   * value, and `_validate_hex_color` in the serializer refuses anything else,
   * which is the check that counts.
   */
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import { ChevronRight, Lock } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  /** What the form is filled from: the echoed values of a refused save. */
  type TemplateValues = {
    name?: string;
    primary_color?: string;
    secondary_color?: string;
    default_notes?: string;
    default_terms?: string;
    footer_text?: string;
    is_default?: boolean;
  };

  let values: TemplateValues = $derived(form?.values ?? {});

  /* True from submit until the response lands, so a second press during a
     slow save cannot post the template again and create two templates. */
  let saving = $state(false);
</script>

<PageHeader title={m.invoices_templates_new_title()} record center width="62ch">
  {#snippet crumb()}
    <a href={resolve('invoices/templates')}>{m.invoices_templates_title()}</a>
    <ChevronRight size={12} />
    <span>{m.common_new()}</span>
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  {#if !data.can_manage}
    <div class="v2-pad" style="padding-top:24px;max-width:56ch;margin-left:auto;margin-right:auto">
      <div class="v2-next" role="note">
        <Lock size={17} style="flex:none" />
        <div class="v2-next-body">
          <div style="font-weight:600">{m.common_admins_only()}</div>
          <div class="v2-sub" style="margin-top:2px">
            {m.invoices_templates_create_admin_note()}
          </div>
        </div>
      </div>
      <a class="v2-btn" href={resolve('invoices/templates')} style="margin-top:16px"
        >{m.invoices_templates_back()}</a
      >
    </div>
  {:else}
    <form
      method="POST"
      action="?/create"
      enctype="multipart/form-data"
      use:enhance={({ cancel }) => {
        if (saving) return cancel();
        saving = true;
        return async ({ update }) => {
          await update();
          saving = false;
        };
      }}
      class="v2-pad"
      style="padding-top:18px;padding-bottom:36px;max-width:62ch;margin-left:auto;margin-right:auto"
    >
      {#if form?.error}
        <p style="color:var(--v2-rust);font-size:12.5px;margin:0 0 14px" role="alert">
          {form.error}
        </p>
      {/if}

      <label class="v2-field">
        <span class="v2-label">{m.common_name()}</span>
        <input
          class="v2-input"
          name="name"
          required
          maxlength="100"
          value={values.name ?? ''}
          placeholder={m.invoices_templates_name_placeholder()}
        />
      </label>

      <div class="color-row">
        <label class="color-field">
          <span class="v2-label">{m.invoices_templates_primary_colour()}</span>
          <input
            class="color-swatch"
            type="color"
            name="primary_color"
            defaultValue={values.primary_color || '#3B82F6'}
          />
        </label>
        <label class="color-field">
          <span class="v2-label">{m.invoices_templates_secondary_colour()}</span>
          <input
            class="color-swatch"
            type="color"
            name="secondary_color"
            defaultValue={values.secondary_color || '#1E40AF'}
          />
        </label>
      </div>
      <p class="v2-sub" style="font-size:11.5px;margin:-6px 0 16px">
        {m.invoices_templates_colour_hint()}
      </p>

      <label class="v2-field">
        <span class="v2-label"
          >{m.invoices_templates_logo()} <span class="opt">{m.invoices_form_optional()}</span></span
        >
        <input class="v2-input" type="file" name="logo" accept="image/*" />
      </label>

      <label class="v2-field">
        <span class="v2-label"
          >{m.invoices_templates_default_notes()}
          <span class="opt">{m.invoices_form_optional()}</span></span
        >
        <textarea
          class="v2-input"
          name="default_notes"
          rows="3"
          placeholder={m.invoices_templates_notes_placeholder()}
          >{values.default_notes ?? ''}</textarea
        >
      </label>

      <label class="v2-field">
        <span class="v2-label"
          >{m.invoices_templates_default_terms()}
          <span class="opt">{m.invoices_form_optional()}</span></span
        >
        <textarea
          class="v2-input"
          name="default_terms"
          rows="3"
          placeholder={m.invoices_templates_terms_placeholder()}
          >{values.default_terms ?? ''}</textarea
        >
      </label>

      <label class="v2-field">
        <span class="v2-label"
          >{m.invoices_templates_footer_text()}
          <span class="opt">{m.invoices_form_optional()}</span></span
        >
        <textarea class="v2-input" name="footer_text" rows="2">{values.footer_text ?? ''}</textarea>
      </label>

      <label class="flag">
        <input type="checkbox" name="is_default" checked={values.is_default === true} />
        <span>
          <strong>{m.invoices_templates_make_default()}</strong>
          <span class="v2-sub">
            {m.invoices_templates_make_default_hint()}
          </span>
        </span>
      </label>

      <div style="display:flex;gap:9px;margin-top:6px">
        <button class="v2-btn v2-btn-primary" type="submit" disabled={saving}>
          {saving ? m.invoices_templates_creating() : m.invoices_templates_create()}
        </button>
        <a class="v2-btn" href={resolve('invoices/templates')}>{m.common_cancel()}</a>
      </div>
    </form>
  {/if}
</div>

<style>
  .opt {
    text-transform: none;
    font-weight: 500;
    letter-spacing: 0;
    color: var(--v2-slate);
  }
  .color-row {
    display: flex;
    gap: 16px;
  }
  .color-field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .color-swatch {
    width: 56px;
    height: 38px;
    padding: 3px;
    border: 1px solid var(--v2-line);
    border-radius: 8px;
    background: var(--v2-card);
    cursor: pointer;
  }
  .flag {
    display: flex;
    gap: 9px;
    align-items: flex-start;
    font-size: 13px;
    margin: 4px 0 18px;
  }
  .flag span {
    display: block;
  }
  .flag .v2-sub {
    display: block;
    font-size: 11.5px;
    margin-top: 2px;
  }
</style>
