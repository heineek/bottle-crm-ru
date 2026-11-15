/**
 * The settings hub's rows. Browser-safe, so the derivation can be tested.
 *
 * A switched-off module's rows are left out, and every value read from a
 * skipped call is read null-safely: the numbers and the module list come from
 * one read, but a row must still never throw on a missing total.
 */
import { isOrgAdmin } from '#lib/admin.js';
import { hubValue, showAutomationSetting } from '#lib/v2/automation.js';
import { showObjectsSetting } from '#lib/v2/custom-objects.js';
import { isOn, productsOn, wordsOn } from '#lib/v2/modules.js';
import { m } from '#lib/paraglide/messages.js';

/**
 * @param {any} data the hub load plus the shell's admin fact
 * @returns {{ label: string, items: { href: string, title: string, body: string, value: string | null, warn: boolean }[] }[]}
 */
export function hubGroups(data) {
  const org = data.org;
  const ticketsOn = isOn(data.modules, 'tickets');
  const switchedOff = Array.isArray(data.modules)
    ? data.modules.filter((/** @type {any} */ m) => !m.enabled).length
    : null;

  /**
   * Weekday hours as one line. When the days do not all match it says so
   * rather than printing the first day's hours; "09:00-17:00" beside a
   * calendar where four days run to 17:30 is a summary that is simply wrong,
   * and this is the number an SLA is measured against.
   */
  const hoursSummary = (() => {
    if (!data.calendar) return '';
    const open = data.calendar.days.filter((/** @type {any} */ d) => d.open);
    if (!open.length) return m.settings_hub_hours_none();
    const first = open[0];
    const uniform = open.every(
      (/** @type {any} */ d) => d.open === first.open && d.close === first.close
    );
    return uniform
      ? m.settings_hub_hours_uniform({ count: open.length, open: first.open, close: first.close })
      : m.settings_hub_hours_vary({ count: open.length });
  })();

  const formMakes = wordsOn(
    data.modules,
    [
      ['leads', m.settings_hub_webforms_word_lead()],
      ['tickets', m.settings_hub_webforms_word_ticket()]
    ],
    m.settings_hub_word_or()
  );

  /** An approval rule set to MANAGER with no named approvers matches nobody. */
  const stuckApprovalRules = (data.approvalRules ?? []).filter(
    (/** @type {any} */ r) => r.is_active && r.approver_role === 'MANAGER' && !r.approvers.length
  ).length;

  return [
    {
      label: m.settings_hub_group_people(),
      items: [
        {
          href: '/team',
          title: m.settings_hub_team_title(),
          body: m.settings_hub_team_body(),
          // People counts are admin-only oversight; a member's fan-out gets no
          // totals (the endpoint 403s), so the row lists the destination with
          // no value rather than a misleading zero.
          value: data.peopleTotals
            ? `${m.settings_hub_people_count({ count: data.peopleTotals.count })} · ${m.settings_hub_admins_count({ count: data.peopleTotals.admins })}`
            : null,
          warn: data.peopleTotals ? data.peopleTotals.tokens_on_deactivated > 0 : false
        },
        {
          href: '/settings/api-tokens',
          title: m.settings_hub_tokens_title(),
          body: m.settings_hub_tokens_body(),
          value: data.tokenTotals
            ? m.settings_hub_tokens_live({ count: data.tokenTotals.live })
            : null,
          warn: data.tokenTotals
            ? data.tokenTotals.orphaned > 0 || data.tokenTotals.unused_90d > 0
            : false
        },
        // Listed for admins only: every webhooks route answers a member 403,
        // reads included, so a member would open it only to be turned away.
        // `isOrgAdmin` is a display hint; the API is the gate.
        ...(isOrgAdmin(data)
          ? [
              {
                href: '/settings/webhooks',
                title: m.settings_hub_webhooks_title(),
                body: m.settings_hub_webhooks_body(),
                value: null,
                warn: false
              },
              // Admin-only on the server for the same reason as webhooks.
              {
                href: '/settings/audit-log',
                title: m.settings_hub_audit_title(),
                body: m.settings_hub_audit_body(),
                value: null,
                warn: false
              }
            ]
          : []),
        {
          // Filed with access rather than with the ticket channels. What a
          // published web form grants is the ability for a stranger with no
          // account to write into this org, which is an access question; what
          // it arrives as is the smaller half.
          href: '/settings/web-forms',
          title: m.settings_hub_webforms_title(),
          body: formMakes
            ? m.settings_hub_webforms_body_makes({ target: formMakes })
            : m.settings_hub_webforms_body(),
          value: m.settings_hub_webforms_published({ count: data.webFormTotals.published }),
          // Forms are live and nothing has arrived in a month. Usually the
          // snippet was taken off the site it was pasted onto, which nothing
          // else would ever tell you. The destination names the individual
          // forms; this only says that at least one is silent.
          warn: data.webFormTotals.published > 0 && data.webFormTotals.submissions_30d === 0
        },
        ...(isOn(data.modules, 'knowledge_base') && data.helpCenter
          ? [
              {
                // Filed beside web forms for the same reason: it is what a stranger
                // with no account can reach. Readable by every member, so the value
                // is always computable.
                href: '/settings/help-center',
                title: m.settings_hub_helpcenter_title(),
                body: m.settings_hub_helpcenter_body(),
                value:
                  data.helpCenter.help_center_enabled && data.helpCenter.help_center_slug
                    ? `/help-center/${data.helpCenter.help_center_slug}`
                    : m.settings_hub_helpcenter_off(),
                warn: false
              }
            ]
          : []),
        {
          href: '/settings/organization',
          title: m.settings_hub_org_title(),
          body: isOn(data.modules, 'invoices')
            ? m.settings_hub_org_body_invoices()
            : m.settings_hub_org_body(),
          value: org.company_name,
          warn: false
        },
        ...(isOrgAdmin(data)
          ? [
              {
                href: '/settings/modules',
                title: m.settings_hub_modules_title(),
                body: m.settings_hub_modules_body(),
                value:
                  switchedOff === null
                    ? null
                    : switchedOff
                      ? m.settings_hub_modules_switched_off({ count: switchedOff })
                      : m.settings_hub_modules_all_on(),
                warn: false
              }
            ]
          : [])
      ]
    },
    ...(ticketsOn
      ? [
          {
            label: m.settings_hub_group_tickets(),
            items: [
              {
                href: '/settings/routing',
                title: m.settings_hub_routing_title(),
                body: m.settings_hub_routing_body(),
                value: data.routingTotals
                  ? m.settings_hub_routing_rules({ count: data.routingTotals.active })
                  : null,
                warn: (data.routingTotals?.unrouted_last_30d ?? 0) > 0
              },
              {
                href: '/settings/escalation',
                title: m.settings_hub_escalation_title(),
                body: m.settings_hub_escalation_body(),
                value: data.escalationTotals
                  ? m.settings_hub_escalation_value({
                      active: data.escalationTotals.active,
                      count: data.escalationTotals.count
                    })
                  : null,
                warn: (data.escalationTotals?.breaches_unhandled_30d ?? 0) > 0
              },
              {
                href: '/settings/business-hours',
                title: m.settings_hub_hours_title(),
                body: m.settings_hub_hours_body(),
                value: data.calendar ? `${data.calendar.name} · ${hoursSummary}` : null,
                warn: false
              },
              {
                href: '/settings/ticket-approvals',
                title: m.settings_hub_approvals_title(),
                body: m.settings_hub_approvals_body(),
                value: data.approvalTotals
                  ? m.settings_hub_active_count({ count: data.approvalTotals.active })
                  : null,
                warn: stuckApprovalRules > 0
              },
              {
                href: '/settings/reopen',
                title: m.settings_hub_reopen_title(),
                body: m.settings_hub_reopen_body(),
                // Admin-only, like people and tokens above: a member's fan-out gets
                // null (the endpoint 403s), so the row lists the destination without
                // a value rather than guessing at the policy.
                value: !data.reopen
                  ? null
                  : data.reopen.is_enabled
                    ? m.settings_hub_reopen_within({ count: data.reopen.reopen_window_days })
                    : m.settings_hub_reopen_off(),
                // Replies arriving outside the window are normal for any window, so
                // that number belongs on the page, not on a warning here. Off is the
                // state worth flagging: it makes every reply to a closed ticket
                // vanish, not just the late ones.
                warn: data.reopen ? !data.reopen.is_enabled : false
              },
              {
                href: '/settings/inbound-email',
                title: m.settings_hub_inbound_title(),
                body: m.settings_hub_inbound_body(),
                value: data.mailboxTotals
                  ? m.settings_hub_inbound_value({
                      active: data.mailboxTotals.active,
                      count: data.mailboxTotals.count
                    })
                  : null,
                // Off AND still receiving, not merely off. An address switched off
                // and left alone is a decision; one still getting mail and creating
                // nothing is a customer being ignored.
                warn: (data.mailboxTotals?.silently_dropping ?? 0) > 0
              }
            ]
          }
        ]
      : []),
    {
      label: m.settings_hub_group_words(),
      items: [
        ...(ticketsOn
          ? [
              {
                href: '/settings/macros',
                title: m.settings_hub_macros_title(),
                body: m.settings_hub_macros_body(),
                value: data.macroTotals
                  ? m.settings_hub_macros_shared({ count: data.macroTotals.org })
                  : null,
                warn: (data.macroTotals?.with_unknown_placeholders ?? 0) > 0
              }
            ]
          : []),
        {
          href: '/settings/tags',
          title: m.common_tags(),
          body: m.settings_hub_tags_body({
            list: wordsOn(
              data.modules,
              [
                [null, m.settings_hub_tags_word_accounts()],
                ['leads', m.settings_hub_tags_word_leads()],
                ['deals', m.settings_hub_tags_word_deals()],
                ['tickets', m.settings_hub_tags_word_tickets()]
              ],
              m.settings_hub_word_and()
            )
          }),
          value: m.settings_hub_tags_in_use({ count: data.tagTotals.active }),
          // Unused tags are housekeeping, not a fault, the tags page lists
          // them without needing the hub to raise an alarm about tidiness.
          warn: false
        },
        ...(isOn(data.modules, 'leads')
          ? [
              {
                href: '/settings/lead-pipelines',
                title: m.settings_hub_lead_pipelines_title(),
                body: m.settings_hub_lead_pipelines_body(),
                value: null,
                warn: false
              }
            ]
          : []),
        ...(isOn(data.modules, 'deals')
          ? [
              {
                href: '/settings/deal-pipelines',
                title: m.settings_hub_deal_pipelines_title(),
                body: m.settings_hub_deal_pipelines_body(),
                value: null,
                warn: false
              }
            ]
          : []),
        {
          href: '/settings/custom-fields',
          title: m.settings_hub_fields_title(),
          body: m.settings_hub_fields_body(),
          value: m.settings_hub_fields_value({
            active: data.fieldTotals.active,
            models: data.fieldTotals.models_extended
          }),
          warn: data.fieldTotals.required_with_gaps > 0
        },
        ...(showObjectsSetting(data.customObjects, isOrgAdmin(data))
          ? [
              {
                href: '/settings/objects',
                title: m.settings_hub_objects_title(),
                body: m.settings_hub_objects_body(),
                value: m.settings_hub_active_count({ count: data.customObjects.objects.length }),
                warn: false
              }
            ]
          : []),
        ...(showAutomationSetting(data.automation, isOrgAdmin(data))
          ? [
              {
                href: '/settings/automation',
                title: m.settings_hub_automation_title(),
                body: m.settings_hub_automation_body(),
                ...hubValue(data.automation)
              }
            ]
          : []),
        ...(isOn(data.modules, 'invoices')
          ? [
              {
                href: '/invoices/templates',
                title: m.settings_hub_invoice_templates_title(),
                body: m.settings_hub_invoice_templates_body(),
                value: m.settings_hub_invoice_templates_value(),
                warn: false
              }
            ]
          : []),
        ...(productsOn(data.modules)
          ? [
              {
                href: '/invoices/products',
                title: m.settings_hub_products_title(),
                body: m.settings_hub_products_body(),
                value: null,
                warn: false
              }
            ]
          : [])
      ]
    }
  ];
}
