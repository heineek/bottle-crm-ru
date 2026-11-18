<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * How an invoice looks when it reaches a customer.
   *
   * `is_default` is a singleton, `InvoiceTemplate.save()` clears the flag on
   * every other row inside a transaction, so exactly one template can hold it.
   * That makes "make this the default" a swap and not a toggle, and the button
   * says so: turning this one on turns another one off, and the copy names
   * which.
   *
   * SECURITY: `template_html` and `template_css` are never rendered.
   * They are org-authored blobs that WeasyPrint turns into a PDF server-side.
   * This page reports that a template carries custom markup and roughly how
   * much; it does not fetch the markup and there is no preview. Putting an
   * arbitrary HTML blob into this app's DOM would turn a PDF setting into
   * stored XSS, and the backend list serializer now strips both fields, so the
   * markup never reaches the wire at all.
   *
   * Writes are admin-only. `data.can_manage` decides whether the write controls
   * are drawn; the API enforces the rule regardless (a forged POST gets a 403,
   * surfaced in the banner below).
   */
  import { enhance } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SectionTabs from '#lib/v2/components/SectionTabs.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import { count, relativeDays } from '#lib/v2/format.js';
  import { Plus, FileCode, ShieldAlert } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  let canManage = $derived(data.can_manage);
  let totals = $derived(data.totals);
  let templates = $derived(
    [...data.templates].sort(
      (a, b) =>
        Number(b.is_default) - Number(a.is_default) || b.used_on_invoices - a.used_on_invoices
    )
  );
  let current = $derived(templates.find((t) => t.is_default));
</script>

<PageHeader title={m.invoices_title()}>
  {#snippet sub()}
    {#each messageParts(current ? m.invoices_templates_sub_default( { count: slot('count'), name: current.name } ) : m.invoices_templates_sub_none( { count: slot('count') } )) as p, i (i)}{#if p.key === 'count'}<span
          class="v2-num">{count(totals.count)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    {#if canManage}
      <a class="v2-btn v2-btn-primary" href={resolve('invoices/templates/new')}
        ><Plus />{m.invoices_templates_new_button()}</a
      >
    {/if}
  {/snippet}
</PageHeader>

<SectionTabs set="invoices" />

{#if form?.error}
  <div class="v2-pad" style="padding-top:12px">
    <p class="tpl-error" role="alert">{form.error}</p>
  </div>
{/if}

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    {#if !current}
      <p class="v2-sub" style="font-size:12.5px;margin:0 0 16px">
        {m.invoices_templates_no_default()}
      </p>
    {/if}

    <div class="v2-tpl-grid">
      {#each templates as t (t.id)}
        <div class="v2-card" style="padding:0;overflow:hidden">
          <!-- The two colours are the only fields that reach the customer as
               design, so they are shown as real swatches. Not a v2 palette
               violation: these paint a PDF, not this application's chrome. -->
          <div class="v2-tpl-swatch">
            <span style="background:{t.primary_color}"></span>
            <span style="background:{t.secondary_color}"></span>
          </div>

          <div style="padding:14px 16px 15px">
            <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
              <b style="font-size:13.5px">{t.name}</b>
              {#if t.is_default}<Pill tone="moss" dot>{m.invoices_templates_default()}</Pill>{/if}
              {#if t.has_custom_html}<Pill tone="clay">{m.invoices_templates_custom_layout()}</Pill
                >{/if}
            </div>

            <div class="v2-sub" style="font-size:11.5px;margin-top:5px">
              {#if t.used_on_invoices}
                {#each messageParts(m.invoices_templates_used_on( { count: t.used_on_invoices, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
                      class="v2-num">{count(t.used_on_invoices)}</span
                    >{:else}{p.text}{/if}{/each}
              {:else}
                {m.invoices_templates_never_used()}
              {/if}
              · {t.has_logo ? m.invoices_templates_logo_set() : m.invoices_templates_no_logo()} ·
              {m.invoices_templates_edited({ when: relativeDays(t.updated_at), who: t.updated_by })}
            </div>

            <dl class="v2-kv" style="margin-top:12px">
              <dt>{m.invoices_form_terms()}</dt>
              <dd>{t.default_terms || '—'}</dd>
              <dt>{m.common_notes()}</dt>
              <dd>{t.default_notes || '—'}</dd>
              <dt>{m.invoices_templates_footer()}</dt>
              <dd>{t.footer_text || '—'}</dd>
            </dl>

            {#if t.has_custom_html}
              <!-- Reported, never rendered. There is no preview here on
                   purpose; see the file header. -->
              <div class="v2-tpl-flag">
                <FileCode size={13} style="flex:none;margin-top:1px" />
                <span>
                  {#each messageParts(m.invoices_templates_custom_flag( { size: slot('size') } )) as p, i (i)}{#if p.key === 'size'}<span
                        class="v2-num">{(t.custom_html_bytes / 1024).toFixed(1)}</span
                      >{:else}{p.text}{/if}{/each}
                </span>
              </div>
            {/if}

            {#if canManage}
              <div style="display:flex;gap:7px;margin-top:14px;flex-wrap:wrap;align-items:center">
                <!-- Live since `GET /invoices/templates/<id>/editor/` landed.
                     This button was disabled for a real reason, not an
                     unfinished one: the detail GET answers with
                     `InvoiceTemplateListSerializer`, same as the list, which
                     never returns `template_html` or `template_css`, so a form
                     could not show what was saved and saving would have
                     blanked it. The editor route serves those two fields on an
                     admin-only path, leaving this page's own fetch unchanged. -->
                <a class="v2-btn v2-btn-sm" href={resolve(`invoices/templates/${t.id}/edit`)}
                  >{m.common_edit()}</a
                >
                {#if !t.is_default}
                  <!-- Named as the swap it is: one default exists at a time.
                       `is_default` is a singleton the model enforces, so this
                       one PUT both sets this default and clears the old one. -->
                  <form method="POST" action="?/setDefault" use:enhance>
                    <input type="hidden" name="id" value={t.id} />
                    <button type="submit" class="v2-btn v2-btn-sm">
                      {current
                        ? m.invoices_templates_use_instead({ name: current.name })
                        : m.invoices_templates_use_instead_builtin()}
                    </button>
                  </form>
                {/if}
              </div>
            {/if}
          </div>
        </div>
      {/each}
    </div>

    {#if totals.unused > 0}
      <p class="v2-sub" style="font-size:11.5px;margin-top:16px">
        {#each messageParts(m.invoices_templates_unused( { count: totals.unused, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
              class="v2-num">{count(totals.unused)}</span
            >{:else}{p.text}{/if}{/each}
      </p>
    {/if}

    <div class="v2-card" style="padding:15px 16px;margin-top:18px">
      <div style="display:flex;gap:10px;align-items:flex-start">
        <ShieldAlert size={16} style="color:var(--v2-slate);flex:none;margin-top:2px" />
        <div>
          <div style="font-weight:600;font-size:13px">
            {m.invoices_templates_no_preview_title()}
          </div>
          <p class="v2-sub" style="font-size:12.5px;margin:5px 0 0;line-height:1.5">
            {m.invoices_templates_no_preview_body()}
          </p>
        </div>
      </div>
    </div>
  </div>
</div>

<style>
  .v2-tpl-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 14px;
    align-items: start;
  }
  .v2-tpl-swatch {
    display: flex;
    height: 6px;
  }
  .v2-tpl-swatch span {
    flex: 1;
  }
  .v2-tpl-flag {
    display: flex;
    gap: 7px;
    align-items: flex-start;
    margin-top: 12px;
    font-size: 11.5px;
    color: var(--v2-clay);
    line-height: 1.45;
  }
  .tpl-error {
    margin: 0;
    padding: 9px 12px;
    font-size: 12.5px;
    color: var(--v2-clay);
    background: color-mix(in srgb, var(--v2-clay) 8%, transparent);
    border: 1px solid color-mix(in srgb, var(--v2-clay) 25%, transparent);
    border-radius: 7px;
  }
  form {
    display: contents;
  }
</style>
