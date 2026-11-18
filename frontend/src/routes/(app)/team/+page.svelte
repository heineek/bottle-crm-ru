<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * Who can get in, and how much they can do.
   *
   * ROLE IS DISPLAYED HERE, DECIDED ON THE SERVER.
   * `role` comes from the Profile the API returned. This page renders it and
   * offers to change it; the server decides whether the change is allowed. Two
   * rules the endpoint enforces and this page mirrors as hints only, nobody
   * changes their own role, and the org keeps at least one admin. Mirroring
   * them is a courtesy so a button does not 400; it is not the control. The
   * real enforcement is in common/views/user_views.py, because anyone can skip
   * this page entirely with curl, which is exactly how a member used to PATCH
   * themselves to admin before that path was closed.
   *
   * The row that matters most is the quiet one: a deactivated account with a
   * not-yet-revoked API token. Deactivating a login already stops that token at
   * the door; resolve_valid_pat rejects a token whose profile.is_active is
   * false, but it is dormant, not revoked, and would authenticate again the
   * moment the account is reactivated. That is why the count is here: an
   * offboarding to-do, not a live breach.
   */
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import StatCard from '#lib/v2/components/StatCard.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import Avatar from '#lib/v2/components/Avatar.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import { count, relativeDays } from '#lib/v2/format.js';
  import { ROLE_LABEL, ROLE_TONE } from '#lib/v2/enums.js';
  import { enhance, type SubmitFunction } from '$app/forms';
  import { UserPlus, KeyRound } from '@lucide/svelte';
  import { m } from '#lib/paraglide/messages.js';
  import { messageParts, slot } from '#lib/utils/message-parts.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  let inviting = $state(false);
  let busy = $state(false);

  /** A submit handler that flips `busy` while the action runs. */
  const working: SubmitFunction = () => {
    busy = true;
    return async ({ update }) => {
      await update();
      busy = false;
    };
  };

  /** The invite form both submits and, on success, closes itself. */
  const inviteSubmit: SubmitFunction = () => {
    busy = true;
    return async ({ update, result }) => {
      await update();
      busy = false;
      if (result?.type === 'success' && result?.data?.invited) inviting = false;
    };
  };
</script>

{#if data.forbidden}
  <PageHeader title={m.team_title()} />
  <div class="v2-pad" style="padding-top:40px">
    <NextAction label={m.team_forbidden_label()} text={m.team_forbidden_text()} />
  </div>
{:else}
  <PageHeader title={m.team_title()}>
    {#snippet sub()}
      {#each messageParts(m.team_sub_people( { count: data.totals.count, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
            class="v2-num">{count(data.totals.count)}</span
          >{:else}{p.text}{/if}{/each}
      ·
      {#each messageParts(m.team_sub_admins( { count: data.totals.admins, shown: slot('shown') } )) as p, i (i)}{#if p.key === 'shown'}<span
            class="v2-num">{count(data.totals.admins)}</span
          >{:else}{p.text}{/if}{/each}
    {/snippet}
    {#snippet actions()}
      <button class="v2-btn v2-btn-primary" onclick={() => (inviting = !inviting)}>
        <UserPlus />{m.team_invite_button()}
      </button>
    {/snippet}
  </PageHeader>

  <div class="v2-pad" style="padding-top:16px;flex:none">
    <div class="v2-stats">
      <StatCard label={m.team_stat_active()} value={count(data.totals.count)} tone="ink" />
      <StatCard
        label={m.team_stat_admins()}
        value={count(data.totals.admins)}
        tone="clay"
        detail={m.team_stat_admins_detail()}
      />
      <StatCard
        label={m.team_stat_never()}
        value={count(data.totals.never_signed_in)}
        tone={data.totals.never_signed_in ? 'clay' : 'slate'}
        detail={data.totals.never_signed_in ? m.team_stat_never_some() : m.team_stat_never_none()}
      />
      <StatCard
        label={m.team_stat_deactivated()}
        value={count(data.totals.deactivated)}
        tone="slate"
      />
    </div>
  </div>

  <div class="v2-scroll">
    <div class="v2-pad" style="padding-bottom:32px">
      {#if inviting}
        <form
          method="POST"
          action="?/invite"
          use:enhance={inviteSubmit}
          class="v2-card"
          style="padding:14px 15px;margin-bottom:18px;display:flex;gap:10px;align-items:flex-end;flex-wrap:wrap"
        >
          <div style="flex:1;min-width:220px">
            <label class="v2-label" for="invite-email" style="display:block;margin-bottom:4px">
              {m.team_invite_label()}
            </label>
            <input
              id="invite-email"
              name="email"
              type="email"
              required
              class="v2-input"
              style="width:100%"
              placeholder={m.team_invite_placeholder()}
            />
          </div>
          <div>
            <label class="v2-label" for="invite-role" style="display:block;margin-bottom:4px">
              {m.team_role_label()}
            </label>
            <select id="invite-role" name="role" class="v2-input" style="width:130px">
              <option value="USER">{m.team_role_member()}</option>
              <option value="ADMIN">{m.team_role_admin()}</option>
            </select>
          </div>
          <button class="v2-btn v2-btn-primary" disabled={busy}>{m.team_send_invite()}</button>
          <button type="button" class="v2-btn" disabled={busy} onclick={() => (inviting = false)}>
            {m.common_cancel()}
          </button>
          {#if form?.invite?.error}
            <p
              class="v2-sub"
              style="color:var(--v2-rust);font-size:12px;flex-basis:100%;margin:2px 0 0"
            >
              {form.invite.error}
            </p>
          {/if}
        </form>
      {/if}

      {#if form?.invited}
        <p
          class="v2-sub"
          style="color:var(--v2-moss);font-size:12.5px;margin:0 0 16px;font-weight:550"
        >
          {m.team_invited({ email: form.invited })}
        </p>
      {:else if form?.error}
        <div style="margin-bottom:16px">
          <NextAction label={m.team_error_label()} text={form.error} tone="rust" />
        </div>
      {/if}

      {#if data.totals.tokens_on_deactivated}
        <!--
          A dormant liability, not a live one. Deactivating a profile already
          stops its tokens at login (resolve_valid_pat checks profile.is_active),
          but it does not revoke the PersonalAccessToken rows. They would
          authenticate again if the account were reactivated. Worth clearing as
          part of offboarding, hence clay rather than rust.
        -->
        <div style="margin-bottom:20px">
          <NextAction
            label={m.team_loose_end_label()}
            text={m.team_loose_end_text({ count: data.totals.tokens_on_deactivated })}
            action={m.team_review_tokens()}
            href="/settings/api-tokens"
          />
        </div>
      {/if}

      <div class="v2-label" style="margin-bottom:10px">{m.team_people()}</div>
      <div class="v2-table-wrap" style="margin-bottom:26px">
        <table class="v2-table">
          <thead>
            <tr>
              <th>{m.team_col_person()}</th>
              <th>{m.team_col_role()}</th>
              <th>{m.team_col_teams()}</th>
              <th data-m="hide">{m.team_col_tokens()}</th>
              <th class="v2-r">{m.team_col_last_login()}</th>
              <th class="v2-r">{m.team_col_manage()}</th>
            </tr>
          </thead>
          <tbody>
            {#each [...data.active, ...data.inactive] as member (member.id)}
              {@const isLastAdmin = member.user_id === data.last_admin_id}
              <tr style={member.is_active ? '' : 'opacity:.62'}>
                <td>
                  <span style="display:flex;gap:9px;align-items:center">
                    <Avatar name={member.name} size={27} />
                    <span style="min-width:0">
                      <span class="v2-table-primary">
                        {member.name}{#if member.is_you}<span class="v2-sub" style="font-weight:400"
                            >{m.team_you_suffix()}</span
                          >{/if}
                      </span>
                      <span class="v2-table-secondary" style="display:block">{member.email}</span>
                    </span>
                  </span>
                </td>
                <td data-m="tag">
                  <Pill tone={member.is_active ? ROLE_TONE[member.role] : 'slate'}
                    >{ROLE_LABEL[member.role]}</Pill
                  >
                  {#if !member.is_active}
                    <span class="v2-table-secondary" style="display:block"
                      >{m.team_deactivated()}</span
                    >
                  {/if}
                </td>
                <td>
                  {#if member.teams.length}
                    {member.teams.join(', ')}
                  {:else}
                    <span class="v2-muted">—</span>
                  {/if}
                </td>
                <td data-m="hide">
                  {#if member.active_token_count}
                    <a
                      href={resolve('settings/api-tokens')}
                      style="display:inline-flex;gap:5px;align-items:center;color:{member.is_active
                        ? 'inherit'
                        : 'var(--v2-clay)'};font-weight:{member.is_active ? 400 : 600}"
                    >
                      <KeyRound size={13} />
                      <span class="v2-num">{member.active_token_count}</span>
                    </a>
                  {:else}
                    <span class="v2-muted">—</span>
                  {/if}
                </td>
                <td class="v2-r">
                  {#if member.last_login}
                    {relativeDays(member.last_login)}
                  {:else}
                    <span style="color:var(--v2-clay);font-weight:600">{m.team_never()}</span>
                  {/if}
                </td>
                <td class="v2-r">
                  {#if member.is_you}
                    <span class="v2-muted" style="font-size:11.5px">—</span>
                  {:else}
                    <span
                      style="display:inline-flex;gap:6px;justify-content:flex-end;flex-wrap:wrap"
                    >
                      <!-- Role toggle. Two roles, so one button naming the
                           destination is clearer than a picker. The last admin
                           cannot be demoted; the server enforces it too. -->
                      <form method="POST" action="?/setRole" use:enhance={working}>
                        <input type="hidden" name="userId" value={member.user_id} />
                        <input
                          type="hidden"
                          name="role"
                          value={member.role === 'ADMIN' ? 'USER' : 'ADMIN'}
                        />
                        <button
                          class="v2-btn v2-btn-sm"
                          disabled={busy || (member.role === 'ADMIN' && isLastAdmin)}
                          title={member.role === 'ADMIN' && isLastAdmin
                            ? m.team_last_admin_hint()
                            : ''}
                        >
                          {member.role === 'ADMIN' ? m.team_make_member() : m.team_make_admin()}
                        </button>
                      </form>
                      <!-- Activate / deactivate. The last active admin cannot
                           be deactivated; the server refuses it with a 400. -->
                      <form method="POST" action="?/setStatus" use:enhance={working}>
                        <input type="hidden" name="userId" value={member.user_id} />
                        <input
                          type="hidden"
                          name="status"
                          value={member.is_active ? 'Inactive' : 'Active'}
                        />
                        <button
                          class="v2-btn v2-btn-sm"
                          disabled={busy || (member.is_active && isLastAdmin)}
                          title={member.is_active && isLastAdmin
                            ? m.team_last_active_admin_hint()
                            : ''}
                          style={member.is_active ? 'color:var(--v2-rust)' : ''}
                        >
                          {member.is_active ? m.team_deactivate() : m.team_reactivate()}
                        </button>
                      </form>
                    </span>
                  {/if}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>

      <div class="v2-label" style="margin-bottom:10px">{m.team_teams()}</div>
      <div class="v2-card" style="overflow:hidden;margin-bottom:14px">
        {#each data.teams as t (t.id)}
          <div class="v2-setting">
            <div class="v2-setting-body">
              <b>{t.name}</b>
              <span class="v2-sub" style="font-size:11.5px">{t.description}</span>
            </div>
            <span class="v2-sub v2-num" style="font-size:12px">
              {m.team_member_count({ count: t.member_count })}
            </span>
          </div>
        {:else}
          <div class="v2-setting">
            <span class="v2-sub" style="font-size:12px">{m.team_no_teams()}</span>
          </div>
        {/each}
      </div>

      <p class="v2-sub" style="font-size:11.5px">
        {m.team_footer()}
      </p>
    </div>
  </div>
{/if}
