<script lang="ts">
  /**
   * Web forms: the list.
   *
   * WHAT A FORM IS, AND WHY THIS PAGE IS CAREFUL
   * A published web form is an endpoint anyone on the internet can post to,
   * and every accepted post writes a lead or a ticket into this organisation. That is
   * closer to a credential than to a record, which is why creating, editing,
   * publishing and deleting are all admin-only, and why a member sees this
   * list read-only rather than not at all: knowing which forms are live is
   * ordinary operational knowledge, minting one is not.
   *
   * The controls below are hidden from a member as a courtesy, not as the
   * boundary. `is_org_admin(request.profile)` in `webforms/views.py` is the
   * boundary, and the page's actions turn its 403 into a sentence, because a
   * member can still post to them directly.
   *
   * PUBLISHED IS THE COLUMN WORTH SCANNING
   * A draft collects nothing, so the pill answers the only question anyone
   * opens this page with. Draft is `slate`, the absence of a problem, not
   * `clay`: an unfinished form is a normal state, not a fault. The one thing
   * flagged in clay is a published form with no submissions in 30 days, which
   * is the shape of an embed that was removed from the customer's site.
   *
   * COUNTS COME FROM `totals`, WHICH THE SERVER COMPUTES
   * The list is paginated. Counting the rows on screen would be right until
   * the org's eleventh form and quietly wrong afterwards, so every figure in
   * the stat strip comes from a server-side count over every form.
   */
  import { resolve } from '$app/paths';
  import { asInternalPath } from '#lib/utils/paths.js';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import SettingsCrumb from '#lib/v2/components/SettingsCrumb.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import EmptyState from '#lib/v2/components/EmptyState.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import { count, shortDate } from '#lib/v2/format.js';
  import { enhance } from '$app/forms';
  import { Plus, ShieldAlert } from '@lucide/svelte';
  import { WEBFORM_TARGETS } from '#lib/v2/webform-fields.js';
  import { isOn, OBJECT_MODULES } from '#lib/v2/modules.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps, SubmitFunction } from './$types';

  let { data, form }: PageProps = $props();

  let totals = $derived(data.totals);
  let drafts = $derived(Math.max(totals.count - totals.published, 0));

  let targets = $derived(
    WEBFORM_TARGETS.filter((t) => isOn(data.modules, OBJECT_MODULES[t.value]))
  );

  let creating = $state(false);
  let busy = $state(false);

  /** A submit handler that flips `busy` while the action runs. */
  const working: SubmitFunction = () => {
    busy = true;
    return async ({ update }) => {
      await update();
      busy = false;
    };
  };

  /**
   * The one error surface. Every action reports under its own key so a failed
   * publish cannot be mistaken for a failed delete, and this reads whichever
   * one came back.
   */
  let actionError = $derived(
    form?.create?.error ??
      form?.publish?.error ??
      form?.unpublish?.error ??
      form?.delete?.error ??
      null
  );
</script>

<PageHeader title={m.settings_webforms_title()}>
  {#snippet crumb()}<SettingsCrumb />{/snippet}
  {#snippet sub()}
    {#each messageParts(m.settings_webforms_list_sub( { published: slot('published'), total: slot('total') } )) as p, i (i)}{#if p.key === 'published'}<span
          class="v2-num">{count(totals.published)}</span
        >{:else if p.key === 'total'}<span class="v2-num">{count(totals.count)}</span
        >{:else}{p.text}{/if}{/each}
  {/snippet}
  {#snippet actions()}
    {#if data.canManage}
      <button class="v2-btn v2-btn-primary" onclick={() => (creating = !creating)}>
        <Plus />{m.settings_webforms_new_form()}
      </button>
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-pad" style="padding-top:16px;flex:none">
  <div class="v2-stats">
    <StatCard
      label={m.settings_webforms_stat_published()}
      value={count(totals.published)}
      tone="ink"
    />
    <StatCard
      label={m.settings_webforms_stat_drafts()}
      value={count(drafts)}
      tone="slate"
      detail={drafts ? m.settings_webforms_stat_drafts_detail() : m.settings_webforms_none()}
    />
    <StatCard
      label={m.settings_webforms_stat_accepted_30d()}
      value={count(totals.submissions_30d)}
      tone="ink"
    />
    <StatCard
      label={m.settings_webforms_stat_spam_30d()}
      value={count(totals.spam_30d)}
      tone="slate"
      detail={totals.spam_30d ? m.settings_webforms_stat_spam_detail() : m.settings_webforms_none()}
    />
  </div>
</div>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-bottom:32px">
    {#if actionError}
      <div style="margin-bottom:16px">
        <NextAction label={m.settings_webforms_error_label()} text={actionError} tone="rust" />
      </div>
    {/if}

    {#if creating && !targets.length}
      <div style="margin-bottom:18px">
        <NextAction
          label={m.settings_webforms_nothing_to_create_label()}
          text={m.settings_webforms_nothing_to_create_text()}
        />
      </div>
    {:else if creating}
      <!-- A name and a target. The fields are chosen on the form's own
           page: a form with no email field cannot be published at all, so
           asking for the field list from a one-line panel would put the
           editor on two pages. This redirects straight there. The target is
           asked here because it decides which fields that editor offers, and
           it is fixed once the form has submissions. -->
      <form
        method="POST"
        action="?/create"
        use:enhance={working}
        class="v2-card"
        style="padding:14px 15px;margin-bottom:18px;display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap"
      >
        <div style="flex:1;min-width:220px">
          <label class="v2-label" for="form-name" style="display:block;margin-bottom:4px">
            {m.settings_webforms_create_name_label()}
          </label>
          <input
            id="form-name"
            name="name"
            required
            maxlength="255"
            class="v2-input"
            style="width:100%"
            placeholder={m.settings_webforms_create_name_placeholder()}
          />
        </div>
        <div style="min-width:160px">
          <label class="v2-label" for="form-target" style="display:block;margin-bottom:4px">
            {m.settings_webforms_create_target_label()}
          </label>
          <select id="form-target" name="target" class="v2-input" style="width:100%">
            {#each targets as t (t.value)}
              <option value={t.value}
                >{t.value === 'ticket'
                  ? m.settings_webforms_target_option_ticket()
                  : m.settings_webforms_target_option_lead()}</option
              >
            {/each}
          </select>
        </div>
        <button class="v2-btn v2-btn-primary" disabled={busy}
          >{m.settings_webforms_create_submit()}</button
        >
        <button type="button" class="v2-btn" disabled={busy} onclick={() => (creating = false)}>
          {m.common_cancel()}
        </button>
      </form>
    {/if}

    {#if !data.forms.length}
      <EmptyState
        title={m.settings_webforms_empty_title()}
        body={data.canManage
          ? m.settings_webforms_empty_body_admin()
          : m.settings_webforms_empty_body_member()}
      >
        {#snippet actions()}
          {#if data.canManage}
            <button class="v2-btn v2-btn-primary" onclick={() => (creating = true)}>
              <Plus />{m.settings_webforms_new_form()}
            </button>
          {/if}
        {/snippet}
      </EmptyState>
    {:else}
      <div class="v2-table-wrap">
        <table class="v2-table">
          <thead>
            <tr>
              <th>{m.settings_webforms_col_form()}</th>
              <th>{m.settings_webforms_col_state()}</th>
              <th class="v2-r">{m.settings_webforms_col_submissions()}</th>
              <th data-m="hide">{m.common_created()}</th>
              {#if data.canManage}<th class="v2-r">{m.common_actions()}</th>{/if}
            </tr>
          </thead>
          <tbody>
            {#each data.forms as f (f.id)}
              <!-- Published, embedded, and silent for the whole window. The
                   usual cause is the snippet having been taken off the page it
                   was pasted onto, which nothing else here would ever tell you. -->
              {@const quiet = f.is_published && f.submission_count === 0}
              <tr>
                <td>
                  <a
                    class="v2-row-link"
                    href={resolve(asInternalPath(`/settings/web-forms/${f.id}`))}
                  >
                    <div class="v2-table-primary">{f.name}</div>
                    <!-- The silent-form note sits here, on the descriptive
                         line, rather than under the count it describes. The
                         count cell is `.v2-num`, and mono is numerals only;
                         prose inheriting that face reads as a typo. -->
                    <div class="v2-table-secondary">
                      {f.target === 'ticket'
                        ? m.settings_webforms_row_meta_ticket({ count: f.field_count })
                        : m.settings_webforms_row_meta_lead({ count: f.field_count })}
                      {#if quiet}
                        <span style="color:var(--v2-clay);font-weight:600">
                          {m.settings_webforms_live_silent()}
                        </span>
                      {/if}
                    </div>
                  </a>
                </td>
                <td data-m="tag">
                  <Pill tone={f.is_published ? 'moss' : 'slate'}>
                    {f.is_published
                      ? m.settings_webforms_pill_published()
                      : m.settings_webforms_pill_draft()}
                  </Pill>
                </td>
                <td
                  class="v2-r v2-num"
                  data-m="meta"
                  data-l={m.settings_webforms_col_submissions()}
                >
                  {count(f.submission_count)}
                </td>
                <td data-m="hide" class="v2-muted">{shortDate(f.created_at)}</td>
                {#if data.canManage}
                  <td class="v2-r">
                    <span style="display:inline-flex;gap:7px;align-items:center;flex-wrap:wrap">
                      {#if f.is_published}
                        <!-- Two clicks. Unpublishing takes a live form off a
                             customer's site: the embed keeps rendering and every
                             submission from then on is refused. -->
                        <ConfirmAction
                          action="?/unpublish"
                          label={m.settings_webforms_unpublish()}
                          confirmLabel={m.settings_webforms_unpublish_confirm()}
                          explain={m.settings_webforms_unpublish_explain_list()}
                          hidden={{ id: f.id }}
                        />
                      {:else}
                        <form method="POST" action="?/publish" use:enhance={working}>
                          <input type="hidden" name="id" value={f.id} />
                          <button class="v2-btn v2-btn-sm" disabled={busy}
                            >{m.settings_webforms_publish()}</button
                          >
                        </form>
                      {/if}
                      <ConfirmAction
                        action="?/delete"
                        label={m.common_delete()}
                        confirmLabel={m.settings_webforms_delete_confirm()}
                        explain={m.settings_webforms_delete_explain_list()}
                        hidden={{ id: f.id }}
                      />
                    </span>
                  </td>
                {/if}
              </tr>
            {/each}
          </tbody>
        </table>
      </div>

      {#if data.truncated}
        <p class="v2-sub" style="font-size:12px;margin:12px 0 0">
          {#each messageParts(m.settings_webforms_truncated( { shown: data.forms.length, total: slot('total') } )) as p, i (i)}{#if p.key === 'total'}<span
                class="v2-num">{count(totals.count)}</span
              >{:else}{p.text}{/if}{/each}
        </p>
      {/if}
    {/if}

    <div
      style="display:flex;gap:10px;align-items:flex-start;margin-top:20px;padding:14px 16px;border:1px solid var(--v2-line);border-radius:var(--v2-radius)"
    >
      <ShieldAlert size={16} style="color:var(--v2-clay);flex:none;margin-top:1px" />
      <div>
        <div style="font-weight:600;font-size:13px">{m.settings_webforms_warning_title()}</div>
        <p class="v2-sub" style="font-size:12px;margin:4px 0 0">
          {m.settings_webforms_warning_body()}
        </p>
      </div>
    </div>
  </div>
</div>
