<script lang="ts">
  import { enhance } from '$app/forms';
  import { resolve } from '$app/paths';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();
  let submitting = $state(false);
</script>

<PageHeader title={m.help_new_title()} center width="720px">
  {#snippet sub()}{m.help_new_subtitle()}{/snippet}
</PageHeader>

<div class="v2-scroll">
  <div
    class="v2-pad"
    style="padding-top:18px;padding-bottom:32px;max-width:720px;margin-inline:auto"
  >
    {#if form?.error}
      <p class="v2-card error">{form.error}</p>
    {/if}

    <form
      method="POST"
      enctype="multipart/form-data"
      class="v2-card form"
      use:enhance={() => {
        submitting = true;
        return async ({ update }) => {
          await update();
          submitting = false;
        };
      }}
    >
      <div class="v2-field">
        <label for="subject">{m.help_new_subject()}</label>
        <input
          id="subject"
          class="v2-input"
          name="subject"
          maxlength="200"
          required
          value={form?.subject ?? ''}
          placeholder={m.help_new_subject_placeholder()}
        />
      </div>

      <div class="v2-field">
        <label for="category">{m.help_new_category()}</label>
        <select id="category" class="v2-input" name="category" required>
          <option value="">{m.help_new_category_choose()}</option>
          {#each data.categories as category (category.value)}
            <option value={category.value} selected={form?.category === category.value}
              >{category.label}</option
            >
          {/each}
        </select>
      </div>

      <div class="v2-field">
        <label for="body">{m.help_new_body()}</label>
        <textarea
          id="body"
          class="v2-input"
          name="body"
          rows="8"
          maxlength="10000"
          required
          placeholder={m.help_new_body_placeholder()}>{form?.body ?? ''}</textarea
        >
      </div>

      <div class="v2-field">
        <label for="attachment">{m.help_new_attachment()}</label>
        <input id="attachment" class="v2-input" type="file" name="attachment" />
        <span class="v2-sub" style="font-size:11.5px">{m.help_new_attachment_hint()}</span>
      </div>

      <div class="actions">
        <button class="v2-btn v2-btn-primary" type="submit" disabled={submitting}
          >{submitting ? m.help_new_opening() : m.help_new_submit()}</button
        >
        <a class="v2-btn" href={resolve('help')}>{m.common_cancel()}</a>
      </div>
    </form>
  </div>
</div>

<style>
  .form {
    padding: 18px;
    display: grid;
    gap: 18px;
  }
  .error {
    padding: 10px 13px;
    margin-bottom: 16px;
    color: var(--v2-rust);
    font-size: 13px;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
</style>
