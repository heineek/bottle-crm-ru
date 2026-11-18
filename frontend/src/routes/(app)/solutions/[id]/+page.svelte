<script lang="ts">
  import { resolve } from '$app/paths';
  /**
   * An article, and where it is in the workflow.
   *
   * Two changes from the mock, both because the real model says so:
   *
   * 1. The crumb printed `solution.id`. That is a UUID, 36 characters of
   *    nothing, in the position where a reader looks for what they are
   *    reading. The status goes there instead.
   * 2. "Related articles" is gone. The mock listed three under that heading
   *    with no stated relation, and nothing in the schema computes one. What
   *    the database does hold is the **tickets this article is filed
   *    against**, which is the same rail pointing the other way: the ticket
   *    page already links here.
   */
  import PageHeader from '#lib/v2/components/PageHeader.svelte';
  import ConfirmAction from '#lib/v2/components/ConfirmAction.svelte';
  import NextAction from '#lib/v2/components/NextAction.svelte';
  import Pill from '#lib/v2/components/Pill.svelte';
  import { relativeDays, longDate } from '#lib/v2/format.js';
  import {
    SOLUTION_STATUS_LABEL,
    SOLUTION_STATUS_TONE,
    PRIORITY_TONE,
    CASE_STATUS_TONE,
    CASE_STATUS_LABEL,
    CASE_PRIORITY_LABEL
  } from '#lib/v2/enums.js';
  import { enhance } from '$app/forms';
  import { ChevronRight, Eye, EyeOff } from '@lucide/svelte';
  import { isOn } from '#lib/v2/modules.js';
  import { m } from '#lib/paraglide/messages.js';
  import type { PageProps } from './$types';

  let { data, form }: PageProps = $props();

  let { article, tickets, hidden_ticket_count, canRelease, canEdit, canDelete } = $derived(data);
  // With Tickets off the API empties the ticket figures, so none are shown.
  let ticketsOn = $derived(isOn(data.modules, 'tickets'));

  /**
   * What is standing between this article and being suggested on tickets,
   * said as the next single step rather than as a description of the state.
   *
   * The action is dropped for anyone who cannot take it. The API answers 403
   *, but the sentence stays, because "an admin has to approve this" is the
   * useful half and the half a writer needs to know.
   */
  let gate = $derived.by(() => {
    if (article.is_published) return null;
    if (article.status === 'approved') {
      return {
        // Without the button, "publishing is the last step" leaves a reader
        // hunting for a control that is not theirs. Naming who does it is the
        // whole value of the sentence for everybody else.
        text: `${
          ticketsOn ? m.solutions_gate_approved_tickets() : m.solutions_gate_approved_unpublished()
        } ${canRelease ? m.solutions_gate_publish_last() : m.solutions_gate_admin_publish()}`,
        action: canRelease ? m.solutions_publish() : null,
        form: 'setPublished',
        value: 'true'
      };
    }
    if (article.status === 'reviewed') {
      return {
        text: canRelease ? m.solutions_gate_reviewed_admin() : m.solutions_gate_reviewed_waiting(),
        action: canRelease ? m.solutions_approve() : null,
        form: 'setStatus',
        value: 'approved'
      };
    }
    return {
      text: m.solutions_gate_draft(),
      action: canEdit ? m.solutions_send_for_review() : null,
      form: 'setStatus',
      value: 'reviewed'
    };
  });
</script>

<PageHeader title={article.title} record>
  {#snippet crumb()}
    <a href={resolve('solutions')}>{m.solutions_list_title()}</a>
    <ChevronRight size={12} />
    <span>{SOLUTION_STATUS_LABEL[article.status]}</span>
  {/snippet}
  {#snippet sub()}
    {[
      article.author || m.solutions_detail_unknown_author(),
      m.solutions_detail_edited({ when: relativeDays(article.updated_at) }),
      ...(ticketsOn
        ? [
            article.use_count
              ? m.solutions_detail_filed_on({ count: article.use_count })
              : m.solutions_detail_not_linked()
          ]
        : [])
    ].join(' · ')}
  {/snippet}
  {#snippet actions()}
    {#if canEdit}
      <a class="v2-btn" href={resolve(`solutions/${article.id}/edit`)}>{m.common_edit()}</a>
    {/if}
    {#if article.is_published && canRelease}
      <form method="POST" action="?/setPublished" use:enhance>
        <input type="hidden" name="published" value="false" />
        <button class="v2-btn" type="submit">{m.solutions_detail_unpublish()}</button>
      </form>
    {/if}
    {#if canDelete}
      <!-- Offered only when the API's delete rule admits this caller; the
           DELETE asks the same rule again. -->
      <ConfirmAction
        action="?/delete"
        label={m.common_delete()}
        confirmLabel={m.solutions_detail_delete_confirm()}
        explain={m.solutions_detail_delete_explain({ title: article.title })}
      />
    {/if}
  {/snippet}
</PageHeader>

<div style="display:flex;flex:1;min-height:0;overflow:hidden">
  <div class="v2-main">
    <div class="v2-scroll">
      <div class="v2-pad" style="padding-top:16px;padding-bottom:32px">
        {#if form?.error}
          <p style="color:var(--v2-rust);font-size:12.5px;margin:0 0 14px">{form.error}</p>
        {/if}

        {#if gate}
          <div style="margin-bottom:20px">
            {#if gate.action}
              <!-- NextAction renders a plain `<button>` with no `type` when it
                   has no `href`, so inside a form it submits. That is the
                   whole mechanism: the component did not need a new prop, and
                   the one place it was a dead button is now the one place it
                   does something. -->
              <form method="POST" action="?/{gate.form}" use:enhance>
                <input
                  type="hidden"
                  name={gate.form === 'setPublished' ? 'published' : 'status'}
                  value={gate.value}
                />
                <NextAction
                  label={m.solutions_detail_not_visible()}
                  text={gate.text}
                  action={gate.action}
                />
              </form>
            {:else}
              <NextAction label={m.solutions_detail_not_visible()} text={gate.text} />
            {/if}
          </div>
        {/if}

        <article
          class="v2-card"
          style="padding:18px 20px;max-width:70ch;font-size:14px;line-height:1.65;white-space:pre-wrap"
        >
          {article.description}
        </article>

        {#if ticketsOn}
          <!-- The tickets this article was filed against. Real rows, and the
               other direction of the link the ticket page already draws. -->
          <div class="v2-label" style="margin:26px 0 10px">
            {tickets.length || hidden_ticket_count
              ? m.solutions_detail_filed_against()
              : m.solutions_detail_not_used()}
          </div>
          {#if tickets.length}
            <div class="v2-card" style="overflow:hidden;max-width:70ch">
              {#each tickets as t (t.id)}
                <a
                  href={resolve(`tickets/${t.id}`)}
                  style="display:flex;gap:12px;align-items:center;padding:11px 15px;border-bottom:1px solid var(--v2-line-soft);color:inherit;text-decoration:none"
                >
                  <span style="flex:1;font-size:13px;min-width:0">{t.name}</span>
                  <Pill tone={CASE_STATUS_TONE[t.status]}
                    >{CASE_STATUS_LABEL[t.status] ?? t.status}</Pill
                  >
                  <Pill tone={PRIORITY_TONE[t.priority]}
                    >{CASE_PRIORITY_LABEL[t.priority] ?? t.priority}</Pill
                  >
                </a>
              {/each}
            </div>
          {:else if !hidden_ticket_count}
            <p class="v2-sub" style="font-size:12.5px;max-width:70ch">
              {m.solutions_detail_nobody_attached()}
            </p>
          {/if}

          {#if hidden_ticket_count}
            <!-- The API filters this rail to tickets the reader may open, while
                 the count stays the article's real usage. Saying so is better
                 than a number that quietly means something different per
                 reader. -->
            <p class="v2-sub" style="font-size:12px;margin-top:10px;max-width:70ch">
              {m.solutions_detail_hidden_tickets({ count: hidden_ticket_count })}
            </p>
          {/if}
        {/if}
      </div>
    </div>
  </div>

  <aside class="v2-rail">
    <div class="v2-label v2-rail-head">{m.solutions_detail_rail_article()}</div>
    <dl class="v2-kv">
      <dt>{m.solutions_detail_status()}</dt>
      <dd>
        <Pill tone={SOLUTION_STATUS_TONE[article.status]}>
          {SOLUTION_STATUS_LABEL[article.status]}
        </Pill>
      </dd>
      <dt>{m.solutions_detail_visibility()}</dt>
      <dd>
        {#if article.is_published}
          <span style="display:inline-flex;gap:5px;align-items:center">
            <Eye size={13} />{m.solutions_detail_published()}
          </span>
        {:else}
          <span
            style="display:inline-flex;gap:5px;align-items:center"
            style:color={article.awaiting_release ? 'var(--v2-clay)' : 'inherit'}
          >
            <EyeOff size={13} />{m.solutions_internal()}
          </span>
        {/if}
      </dd>
      <dt>{m.solutions_detail_author()}</dt>
      <dd>{article.author || '—'}</dd>
      {#if ticketsOn}
        <dt>{m.solutions_detail_used_on()}</dt>
        <dd class="v2-num">{m.solutions_detail_used_count({ count: article.use_count })}</dd>
      {/if}
      <dt>{m.solutions_detail_written()}</dt>
      <dd>{longDate(article.created_at)}</dd>
      <dt>{m.solutions_detail_edited_label()}</dt>
      <dd>{longDate(article.updated_at)}</dd>
    </dl>

    {#if ticketsOn}
      <div class="v2-label v2-rail-head">{m.solutions_detail_how_used()}</div>
      <div class="v2-card" style="padding:11px 12px;font-size:12px;line-height:1.55">
        {m.solutions_detail_how_used_body()}
      </div>
    {/if}
  </aside>
</div>
