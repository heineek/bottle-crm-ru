<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * Your own account.
   *
   * The fields that are NOT editable here are the interesting ones. Role is
   * shown and cannot be changed from this page. The API refuses to let anyone
   * change their own role (ProfileSelfUpdateSerializer names only name and
   * phone), and an input that always fails is worse than no input. Same for the
   * organisation: which org you are in decides which rows you can see at all,
   * and it comes from the JWT, not from a form.
   *
   * Two things you CAN do: edit your name and phone (PATCH /profile/), and
   * switch org, a real action that re-issues the token rather than editing a
   * field, so it goes through its own action and the copy says so.
   */
  import { enhance, type SubmitFunction } from '$app/forms';
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import Avatar from '#lib/v2/components/Avatar.svelte';
  import { relativeDays, shortDate, count } from '#lib/v2/format.js';
  import { ROLE_LABEL, ROLE_TONE } from '#lib/v2/enums.js';
  import { KeyRound, Lock, ArrowLeftRight, CalendarDays } from '@lucide/svelte';
  import { isOn, labelOf } from '#lib/v2/modules.js';
  import { asInternalPath } from '#lib/utils/paths.js';
  import { m } from '#lib/paraglide/messages.js';
  import { locales } from '#lib/paraglide/runtime.js';
  import { DOCS_LEAD_ALERTS } from '#lib/v2/lead-alerts.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  let p = $derived(data.profile);

  // Only the modules that are on: each row opens its module's page.
  let workRows = $derived(
    [
      { key: 'goals', path: '/goals', body: m.profile_page_work_goals() },
      { key: 'timesheet', path: '/timesheet', body: m.profile_page_work_timesheet() },
      { key: 'tasks', path: '/tasks', body: m.profile_page_work_tasks() }
    ].filter((row) => isOn(data.modules, row.key))
  );
  let name = $derived(`${p.user_details.first_name} ${p.user_details.last_name}`.trim());

  // Editing name + phone. The backend stores one `name` on User, so the form
  // offers a single full-name field rather than the split the header renders.
  let editing = $state(false);
  let editName = $state('');
  let editPhone = $state('');

  function openEdit() {
    editName = name;
    editPhone = p.phone || '';
    editing = true;
  }

  const onEdit: SubmitFunction = ({ formData }) => {
    // Only send the field the person actually changed. The PATCH treats an
    // absent field as "leave it alone", so an untouched phone is not
    // re-validated, which matters because some seeded numbers carry an
    // extension the validator rejects, and re-sending one would block a plain
    // name change. Same rule the leads form uses for its owner select.
    if ((formData.get('name') ?? '') === name) formData.delete('name');
    if ((formData.get('phone') ?? '') === (p.phone || '')) formData.delete('phone');

    return async ({ result, update }) => {
      if (result.type === 'success') {
        editing = false;
        await update(); // reloads the profile with the saved values
      } else {
        await update({ reset: false }); // keep what they typed, show the message
      }
    };
  };

  // `form` is shared by both actions; the switch action tags its failures.
  let editError = $derived(
    form?.scope === 'switch' || form?.scope === 'language' || form?.scope === 'alerts'
      ? ''
      : (form?.message ?? '')
  );
  let languageError = $derived(form?.scope === 'language' ? (form?.message ?? '') : '');
  let alertsError = $derived(form?.scope === 'alerts' ? (form?.message ?? '') : '');
  let alertsSaved = $derived(form?.scope === 'alerts' && form?.saved === true);
  let switchError = $derived(form?.scope === 'switch' ? (form?.message ?? '') : '');
</script>

<PageHeader title={name} record>
  {#snippet sub()}
    {m.profile_page_sub({
      role: ROLE_LABEL[p.role],
      org: data.org.name,
      date: shortDate(p.joined_at)
    })}
  {/snippet}
  {#snippet actions()}
    {#if !editing}
      <button class="v2-btn v2-btn-primary" onclick={openEdit}
        >{m.profile_page_edit_details()}</button
      >
    {/if}
  {/snippet}
</PageHeader>

<div class="v2-scroll">
  <div class="v2-pad" style="padding-top:18px;padding-bottom:32px">
    <div class="v2-split">
      <div>
        <div class="v2-label" style="margin-bottom:10px">{m.profile_page_you()}</div>

        {#if editing}
          <form
            class="v2-card"
            method="POST"
            action="?/edit"
            use:enhance={onEdit}
            style="padding:17px 18px;margin-bottom:20px"
          >
            <div class="v2-field">
              <label for="f-name">{m.profile_page_full_name()}</label>
              <input
                id="f-name"
                name="name"
                class="v2-input"
                bind:value={editName}
                maxlength="255"
              />
            </div>
            <div class="v2-field" style="margin-top:12px">
              <label for="f-phone">{m.profile_page_phone()}</label>
              <input
                id="f-phone"
                name="phone"
                class="v2-input"
                bind:value={editPhone}
                placeholder={m.profile_page_phone_placeholder()}
              />
              <p class="v2-hint">{m.profile_page_phone_hint()}</p>
            </div>
            {#if editError}
              <p class="v2-error" style="margin-top:10px">{editError}</p>
            {/if}
            <div style="display:flex;gap:8px;margin-top:16px">
              <button class="v2-btn v2-btn-primary" type="submit">{m.common_save()}</button>
              <button class="v2-btn" type="button" onclick={() => (editing = false)}
                >{m.common_cancel()}</button
              >
            </div>
          </form>
        {:else}
          <div class="v2-card" style="padding:17px 18px;margin-bottom:20px">
            <div style="display:flex;gap:13px;align-items:center;margin-bottom:16px">
              <Avatar {name} size={46} />
              <div style="min-width:0">
                <div style="font-weight:640;font-size:15px">{name}</div>
                <div class="v2-sub" style="font-size:12.5px">{p.user_details.email}</div>
              </div>
            </div>
            <dl class="v2-kv">
              <dt>{m.profile_page_phone()}</dt>
              <dd class="v2-num" style="font-size:12px">{p.phone || '—'}</dd>
              <dt>{m.profile_page_teams()}</dt>
              <dd>{p.teams.join(', ') || '—'}</dd>
              <dt>{m.profile_page_joined()}</dt>
              <dd>{shortDate(p.joined_at)}</dd>
              <dt>{m.profile_page_last_login()}</dt>
              <dd>{relativeDays(p.last_login)}</dd>
            </dl>
          </div>
        {/if}

        <div class="v2-label" style="margin-bottom:10px">{m.profile_page_orgs()}</div>
        <div class="v2-card" style="overflow:hidden">
          {#each p.orgs as o (o.id)}
            <div class="v2-setting">
              <div class="v2-setting-body">
                <b>{o.name}</b>
                <span class="v2-sub" style="font-size:11.5px">
                  {o.role === 'ADMIN' ? m.profile_page_org_admin() : m.profile_page_org_member()}
                </span>
              </div>
              {#if o.is_current}
                <Pill tone="ink" dot>{m.profile_page_current()}</Pill>
              {:else}
                <!-- Switching org re-issues the token; it does not edit a field
                     on this page. The action swaps the cookies and reloads. -->
                <form method="POST" action="?/switchOrg" use:enhance class="v2-inline-form">
                  <input type="hidden" name="org_id" value={o.id} />
                  <button class="v2-btn v2-btn-sm" type="submit">
                    <ArrowLeftRight size={12} />{m.profile_page_switch()}
                  </button>
                </form>
              {/if}
            </div>
          {/each}
        </div>
        {#if switchError}
          <p class="v2-error" style="margin-top:9px">{switchError}</p>
        {/if}
        <p class="v2-sub" style="font-size:11.5px;margin-top:11px">
          {m.profile_page_switch_note()}
        </p>

        <div class="v2-label" style="margin:20px 0 10px">{m.profile_language_title()}</div>
        <!-- No use:enhance: the reload renders the whole document in the new
             language, <html lang> included. -->
        <form class="v2-card" method="POST" action="?/language" style="padding:17px 18px">
          <div class="v2-field">
            <label for="f-language">{m.profile_language_label()}</label>
            <select id="f-language" name="language" class="v2-input" value={p.language}>
              <option value="">{m.profile_language_automatic()}</option>
              {#each locales as code (code)}
                <option value={code} lang={code}>{m.language_name({}, { locale: code })}</option>
              {/each}
            </select>
            <p class="v2-hint">{m.profile_language_hint()}</p>
          </div>
          {#if languageError}
            <p class="v2-error" style="margin-top:10px">{languageError}</p>
          {/if}
          <button class="v2-btn v2-btn-primary" type="submit" style="margin-top:14px">
            {m.common_save()}
          </button>
        </form>
      </div>

      <div>
        <div class="v2-label" style="margin-bottom:10px">{m.profile_page_access()}</div>
        <div class="v2-card" style="overflow:hidden;margin-bottom:20px">
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.profile_page_role()}</b>
              <!-- Displayed, never editable from here. -->
              <span class="v2-sub" style="font-size:11.5px">
                {m.profile_page_role_hint()}
              </span>
            </div>
            <Lock size={14} style="color:var(--v2-slate);flex:none" />
            <Pill tone={ROLE_TONE[p.role]}>{ROLE_LABEL[p.role]}</Pill>
          </div>
          <!-- /profile/tokens, not /settings/api-tokens. The settings page is
               the org-wide oversight list and 403s a member, so this count used
               to lead most of the people who clicked it to "Admins only". -->
          <a class="v2-setting" href={resolve('profile/tokens')}>
            <div class="v2-setting-body">
              <b>{m.profile_page_api_tokens()}</b>
              <span class="v2-sub" style="font-size:11.5px">
                {m.profile_page_api_tokens_hint()}
              </span>
            </div>
            <KeyRound size={14} style="color:var(--v2-slate);flex:none" />
            <span class="v2-num" style="font-size:13px;font-weight:600">
              {count(p.active_token_count)}
            </span>
          </a>
          {#if isOn(data.modules, 'tasks')}
            <a class="v2-setting" href={resolve('profile/calendar-feed')}>
              <div class="v2-setting-body">
                <b>{m.profile_page_calendar_feed()}</b>
                <span class="v2-sub" style="font-size:11.5px">
                  {m.profile_page_calendar_feed_hint()}
                </span>
              </div>
              <CalendarDays size={14} style="color:var(--v2-slate);flex:none" />
            </a>
          {/if}
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{m.profile_page_sign_in_method()}</b>
              <!-- It used to say "Google, on <email>", which is false for
                   anyone who signed in with an emailed code. Nothing in the
                   payload says which was used, so this states what holds for
                   both rather than guessing. -->
              <span class="v2-sub" style="font-size:11.5px">
                {m.profile_page_sign_in_method_body({ email: p.user_details.email })}
              </span>
            </div>
          </div>
        </div>

        {#if isOn(data.modules, 'leads')}
          <div class="v2-label" style="margin-bottom:10px">{m.profile_alerts_label()}</div>
          <form
            class="v2-card"
            method="POST"
            action="?/alerts"
            use:enhance={() =>
              async ({ update }) =>
                update({ reset: false })}
            style="overflow:hidden;margin-bottom:20px"
          >
            <label class="v2-setting">
              <div class="v2-setting-body">
                <b>{m.profile_alerts_email_title()}</b>
                <span class="v2-sub" style="font-size:11.5px">
                  {m.profile_alerts_email_hint()}
                </span>
              </div>
              <input type="checkbox" name="lead_alerts_email" checked={p.lead_alerts_email} />
            </label>
            <label class="v2-setting">
              <div class="v2-setting-body">
                <b>{m.profile_alerts_push_title()}</b>
                <span class="v2-sub" style="font-size:11.5px">
                  {m.profile_alerts_push_hint()}
                  <a href={DOCS_LEAD_ALERTS} target="_blank" rel="noopener noreferrer"
                    >{m.profile_alerts_read_more()}</a
                  >
                </span>
              </div>
              <input type="checkbox" name="lead_alerts_push" checked={p.lead_alerts_push} />
            </label>
            <div style="padding:12px 16px;display:flex;gap:10px;align-items:center">
              <button class="v2-btn v2-btn-primary" type="submit">{m.profile_alerts_save()}</button>
              {#if alertsSaved}<span class="v2-sub" style="font-size:12px"
                  >{m.profile_alerts_saved()}</span
                >{/if}
              {#if alertsError}<span class="v2-error">{alertsError}</span>{/if}
            </div>
          </form>
        {/if}

        {#if workRows.length}
          <div class="v2-label" style="margin-bottom:10px">{m.profile_page_work_title()}</div>
          <div class="v2-card" style="overflow:hidden">
            {#each workRows as row (row.key)}
              <a class="v2-setting" href={resolve(asInternalPath(row.path))}>
                <div class="v2-setting-body">
                  <b>{labelOf(data.modules, row.key)}</b>
                  <span class="v2-sub" style="font-size:11.5px">{row.body}</span>
                </div>
              </a>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  </div>
</div>

<style>
  /* The Switch button sits in a form so it can POST; keep it laid out exactly
     as the bare button was (the row uses flex; the form must not add a box). */
  .v2-inline-form {
    display: contents;
  }
</style>
