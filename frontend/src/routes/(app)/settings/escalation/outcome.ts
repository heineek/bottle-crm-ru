/**
 * What one half of an escalation policy actually does when a ticket breaches.
 *
 * Client-side display logic, in its own module rather than inline in
 * `+page.svelte`, because the harness cannot import a `.svelte` file and this
 * is a rule with a right answer that lives in `cases/tasks.py`. The routing
 * route does the same with `rotation.js`.
 *
 * This got the answer wrong in three of the eight action/target/team
 * combinations while it was inline, always in the same direction: reporting a
 * half as live when the engine does nothing with it.
 *
 * **A half with no target does nothing, whatever its action and whatever the
 * notify team.** `_scan_org` guards both dispatches with
 * `if <breach> and policy.<half>_target_id is not None`, so with the target
 * null `_dispatch_breach` is never reached: no mail, no reassignment, and no
 * ESCALATED activity. The team is a CC assembled *inside* that dispatch, not a
 * recipient that can stand on its own, so a policy set to "notify the Support
 * team" with nobody in the target field notifies nobody at all. The old rule
 * treated a team as enough for `notify`, and did not check the target for
 * `notify_and_reassign` at all (which also rendered "Notify and reassign to"
 * with nothing after it).
 *
 * **And a `reassign` half never notifies the team.** `_dispatch_breach` builds
 * a recipient list only for `notify` and `notify_and_reassign`. The old rule
 * appended "and the X team" to every action, so a policy that silently moves a
 * ticket read as one that also tells a team about it.
 *
 * `mobile/lib/data/models/escalation_policy.dart` carries the same rules.
 */
import { ESCALATION_ACTION_LABEL, ESCALATION_PRIORITIES } from '#lib/v2/enums.js';
import { m } from '#lib/paraglide/messages.js';

/**
 * "the Support team", but "the Support Team" when the name already says so.
 *
 * Seeded orgs name their team "Support Team", and appending the word
 * unconditionally reads "the Support Team team". The suffix is what makes a
 * team named "Support" read as a team rather than a person, so it stays for
 * every other name.
 */
export function teamPhrase(name: string) {
  const trimmed = (name ?? '').trim();
  const lower = trimmed.toLowerCase();
  const saysSo =
    lower === 'team' || lower === 'teams' || lower.endsWith(' team') || lower.endsWith(' teams');
  return saysSo
    ? m.settings_escalation_team_phrase_named({ name: trimmed })
    : m.settings_escalation_team_phrase({ name: trimmed });
}

/** The fields of a policy row (`getEscalationPolicies`) these read. */
type OutcomePolicy = {
  priority: string;
  is_active: boolean;
  first_response_action: string;
  resolution_action: string;
  first_response_target: { name: string } | null;
  resolution_target: { name: string } | null;
  notify_team: { name: string } | null;
  breaches_last_30d?: { first_response: number; resolution: number };
};

/** Whether an action emails anybody at all. */
export function actionNotifies(action: string) {
  return action === 'notify' || action === 'notify_and_reassign';
}

/**
 * Whether this half fires. See the note above: an inactive policy is skipped
 * whole, and a half with no target is skipped whatever else is set.
 */
export function halfFires(
  policy: OutcomePolicy | null | undefined,
  kind: 'first_response' | 'resolution'
) {
  return Boolean(policy?.is_active) && Boolean(policy?.[`${kind}_target` as const]);
}

/** What this half does, in a sentence, including when that is nothing. */
export function escalationOutcome(
  policy: OutcomePolicy | null | undefined,
  kind: 'first_response' | 'resolution'
): { text: string; dead: boolean } {
  if (!policy?.is_active) return { text: m.settings_escalation_outcome_off(), dead: true };

  const target = policy[`${kind}_target` as const];
  const team = policy.notify_team;

  if (!target) {
    // Naming the team here is the correction, not decoration. A team set with
    // no target reads as "somebody is told" and is the case where nobody is.
    return {
      text: team
        ? m.settings_escalation_outcome_no_target_team({ team: teamPhrase(team.name) })
        : m.settings_escalation_outcome_no_target(),
      dead: true
    };
  }

  const action = policy[`${kind}_action` as const];
  const label = ESCALATION_ACTION_LABEL[action] ?? action;
  const who =
    team && actionNotifies(action)
      ? m.settings_escalation_target_and_team({ target: target.name, team: teamPhrase(team.name) })
      : target.name;
  return { text: actionSentence(action, who), dead: false };
}

/**
 * "Notify Alice", "Reassign to Alice": one whole sentence per action.
 */
function actionSentence(action: string, who: string) {
  if (action === 'notify') return m.settings_escalation_outcome_notify({ who });
  if (action === 'reassign') return m.settings_escalation_outcome_reassign({ who });
  if (action === 'notify_and_reassign') {
    return m.settings_escalation_outcome_notify_and_reassign({ who });
  }
  return `${ESCALATION_ACTION_LABEL[action] ?? action} ${who}`;
}

/**
 * A team configured on a half that will never notify it, or null.
 *
 * Only for a half that fires: when it does not, the outcome sentence has
 * already said the team is not involved and repeating it would be noise.
 */
export function teamIgnoredNote(
  policy: OutcomePolicy | null | undefined,
  kind: 'first_response' | 'resolution'
): string | null {
  const team = policy?.notify_team;
  if (!policy || !team || !halfFires(policy, kind)) return null;
  if (actionNotifies(policy[`${kind}_action` as const])) return null;
  const phrase = teamPhrase(team.name);
  return m.settings_escalation_team_ignored({
    team: `${phrase[0].toUpperCase()}${phrase.slice(1)}`
  });
}

export const ESCALATION_HALVES: ('first_response' | 'resolution')[] = [
  'first_response',
  'resolution'
];

/** Policies that do nothing on either half. */
export function deadPolicyCount(policies: OutcomePolicy[] | null | undefined) {
  return (policies ?? []).filter((p) => ESCALATION_HALVES.every((kind) => !halfFires(p, kind)))
    .length;
}

/**
 * Breaches in the last 30 days that reached nobody, counting only the halves
 * that cannot fire.
 */
export function breachesGoingNowhere(policies: OutcomePolicy[] | null | undefined) {
  return (policies ?? []).reduce(
    (total, policy) =>
      total +
      ESCALATION_HALVES.reduce(
        (sum, kind) =>
          sum + (halfFires(policy, kind) ? 0 : (policy.breaches_last_30d?.[kind] ?? 0)),
        0
      ),
    0
  );
}

/**
 * Priorities with no policy at all.
 *
 * Two things read this. "New policy" may only offer these, because the
 * `(org, priority)` unique constraint (and `EscalationPolicySerializer
 * .validate`) refuses a second policy for a priority. And the page says out
 * loud that breaches at these priorities escalate to nobody, which is otherwise
 * invisible: the API attaches `breaches_last_30d` to policies, so an
 * unconfigured priority contributes no row and no number anywhere.
 */
export function unconfiguredPriorities(policies: OutcomePolicy[] | null | undefined) {
  const taken = new Set((policies ?? []).map((p) => p.priority));
  return ESCALATION_PRIORITIES.filter((priority) => !taken.has(priority));
}

/** "Urgent and High", "Urgent, High and Normal". */
export function joinWithAnd(parts: string[]) {
  if (!parts.length) return '';
  if (parts.length === 1) return parts[0];
  return m.settings_escalation_join_and({
    list: parts.slice(0, -1).join(', '),
    last: parts[parts.length - 1]
  });
}
