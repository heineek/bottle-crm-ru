<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * Editing a catalogue product, or retiring it.
   *
   * Retire vs delete: a product on historic invoices should be *retired*
   * (Availability → Retired), which pulls it from the line-item picker but keeps
   * the record. Deleting is also safe: line items store their own name and
   * price, so nothing historic is rewritten, but retiring is the honest default
   * for something with a past, so the form leads with it and puts delete behind
   * a confirm. Both are admin-only, enforced by the API.
   */
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import { enhance } from '$app/forms';
  import { ChevronRight, Lock, Trash2 } from '@lucide/svelte';
  import { isOn } from '#lib/v2/modules.js';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  /**
   * What the form is filled from: the echoed values of a refused save, else
   * the stored product.
   */
  type ProductValues = {
    name?: string;
    sku?: string;
    price?: string | number;
    currency?: string | null;
    category?: string;
    description?: string;
    is_active?: boolean;
  };

  let values: ProductValues = $derived(form?.values ?? data.product ?? {});
  let invoicesOn = $derived(isOn(data.modules, 'invoices'));
  let usedOn = $derived(data.product?.used_on ?? 0);
  let confirming = $state(false);
</script>

<PageHeader title={m.invoices_products_edit_page_title()} record center width="62ch">
  {#snippet crumb()}
    <a href={resolve('invoices/products')}>{m.invoices_products_title()}</a>
    <ChevronRight size={12} />
    <span>{data.product?.name ?? m.common_edit()}</span>
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  {#if !data.can_edit}
    <div class="v2-pad" style="padding-top:24px;max-width:56ch;margin-left:auto;margin-right:auto">
      <div class="v2-next" role="note">
        <Lock size={17} style="flex:none" />
        <div class="v2-next-body">
          <div style="font-weight:600">{m.common_admins_only()}</div>
          <div class="v2-sub" style="margin-top:2px">
            {m.invoices_products_change_admin_note()}
          </div>
        </div>
      </div>
      <a class="v2-btn" href={resolve('invoices/products')} style="margin-top:16px"
        >{m.invoices_products_back()}</a
      >
    </div>
  {:else}
    <form
      method="POST"
      action="?/save"
      use:enhance
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
        <input class="v2-input" name="name" required maxlength="255" value={values.name ?? ''} />
      </label>

      <div style="display:flex;gap:12px;flex-wrap:wrap">
        <label class="v2-field" style="flex:2;min-width:180px">
          <span class="v2-label">{m.invoices_products_list_price()}</span>
          <input
            class="v2-input"
            name="price"
            type="number"
            min="0"
            step="0.01"
            required
            value={values.price ?? ''}
          />
        </label>
        <label class="v2-field" style="flex:1;min-width:130px">
          <span class="v2-label">{m.invoices_currency()}</span>
          <select class="v2-input" name="currency" value={values.currency ?? 'USD'}>
            {#each data.currencies as c (c.code)}
              <option value={c.code}>{c.label}</option>
            {/each}
          </select>
        </label>
      </div>

      <div style="display:flex;gap:12px;flex-wrap:wrap">
        <label class="v2-field" style="flex:1;min-width:160px">
          <span class="v2-label">{m.invoices_products_category()}</span>
          <input class="v2-input" name="category" maxlength="100" value={values.category ?? ''} />
        </label>
        <label class="v2-field" style="flex:1;min-width:160px">
          <span class="v2-label">{m.invoices_products_sku()}</span>
          <input class="v2-input" name="sku" maxlength="100" value={values.sku ?? ''} />
        </label>
      </div>

      <label class="v2-field">
        <span class="v2-label">{m.invoices_products_availability()}</span>
        <select
          class="v2-input"
          name="is_active"
          value={values.is_active === false ? 'false' : 'true'}
        >
          <option value="true">{m.invoices_products_sellable_option()}</option>
          <option value="false">{m.invoices_products_retired_option()}</option>
        </select>
        {#if invoicesOn && usedOn > 0}
          <span class="v2-sub" style="font-size:11.5px">
            {#each messageParts(m.invoices_products_used_on_already( { count: usedOn, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
                  class="v2-num">{usedOn}</span
                >{:else}{p.text}{/if}{/each}
          </span>
        {/if}
      </label>

      <label class="v2-field">
        <span class="v2-label">{m.common_description()}</span>
        <textarea class="v2-input" name="description" rows="3">{values.description ?? ''}</textarea>
      </label>

      <div style="display:flex;gap:9px;margin-top:6px;align-items:center">
        <button class="v2-btn v2-btn-primary" type="submit">{m.invoices_save_changes()}</button>
        <a class="v2-btn" href={resolve('invoices/products')}>{m.common_cancel()}</a>
      </div>
    </form>

    <!-- Delete lives in its own form so it never carries the edit fields. -->
    <div
      class="v2-pad"
      style="padding-top:0;padding-bottom:40px;max-width:62ch;margin-left:auto;margin-right:auto"
    >
      <div class="danger">
        {#if !confirming}
          <button class="v2-btn danger-btn" type="button" onclick={() => (confirming = true)}>
            <Trash2 size={14} />
            {m.invoices_products_delete_permanently()}
          </button>
          {#if invoicesOn}
            <span class="v2-sub" style="font-size:11.5px">
              {usedOn > 0
                ? m.invoices_products_delete_used_hint()
                : m.invoices_products_delete_unused_hint()}
            </span>
          {/if}
        {:else}
          <form
            method="POST"
            action="?/delete"
            use:enhance
            style="display:flex;gap:8px;align-items:center"
          >
            <span class="v2-sub" style="font-size:12px">{m.invoices_products_delete_confirm()}</span
            >
            <button class="v2-btn danger-btn" type="submit"
              ><Trash2 size={14} /> {m.common_delete()}</button
            >
            <button class="v2-btn" type="button" onclick={() => (confirming = false)}
              >{m.invoices_keep_it()}</button
            >
          </form>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  .danger {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
    border-top: 1px solid var(--v2-line-soft);
    padding-top: 16px;
  }
  .danger-btn {
    color: var(--v2-rust);
    border-color: color-mix(in srgb, var(--v2-rust) 32%, transparent);
  }
  .danger-btn:hover {
    background: color-mix(in srgb, var(--v2-rust) 9%, transparent);
  }
</style>
