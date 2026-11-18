/// Whether a customer's reply brings a closed ticket back.
///
/// One row per org, four fields, plus three 30-day metrics the settings screen
/// draws. The whole question is what number goes in the window, and the only
/// thing that answers it is how customers actually behave, which is what the
/// metrics are for.
library;

import '../../l10n/l10n.dart';
import '../api/schema.g.dart' as api;
import 'ticket.dart' show TicketStatus;

/// `ReopenPolicySerializer.NON_TERMINAL_STATUSES`. A ticket reopened into a
/// terminal status would close again on arrival, so only these three.
const List<String> reopenToStatuses = ['New', 'Assigned', 'Pending'];

/// `validate_reopen_window_days`.
const int reopenWindowMin = 1;
const int reopenWindowMax = 365;

class ReopenPolicy {
  const ReopenPolicy({
    this.isEnabled = true,
    this.windowDays = 7,
    this.reopenToStatus = 'Pending',
    this.notifyAssigned = true,
    this.reopenedLast30d = 0,
    this.repliesAfterWindow30d = 0,
    this.medianDaysToReply = 0,
  });

  final bool isEnabled;
  final int windowDays;
  final String reopenToStatus;
  final bool notifyAssigned;

  /// One REOPENED activity per reopen. Honest history even when the policy has
  /// since been turned off.
  final int reopenedLast30d;

  /// Replies that landed too late to reopen anything. **Only counted while the
  /// policy is on**: see [missedWindowIsMeasured].
  final int repliesAfterWindow30d;

  /// Days from close to reply, across every post-close external reply that can
  /// be dated.
  final int medianDaysToReply;

  /// Whether [repliesAfterWindow30d] is a measurement or a zero by
  /// construction.
  ///
  /// `cases/signals.py::_evaluate_reopen` returns `None` on
  /// `if not policy["is_enabled"]`, **before** it ever compares the window, and
  /// the `out_of_reopen_window` flag the metric counts is written only for the
  /// `"out_of_window"` return. So with the policy off nothing is ever flagged
  /// and the count is always zero, in exactly the state where every reply to a
  /// closed ticket reopens nothing. A card reading "0 replies missed the
  /// window" there is reassurance about the one thing that is certainly
  /// happening.
  bool get missedWindowIsMeasured => isEnabled;

  /// Reads a `ReopenPolicyWithStats`, the GET's policy plus its metrics. The
  /// median is a float and is rounded to whole days.
  factory ReopenPolicy.fromJson(Map<String, dynamic> json) {
    final w = api.ReopenPolicyWithStats.fromJson(json);
    return ReopenPolicy(
      isEnabled: w.isEnabled ?? true,
      windowDays: w.reopenWindowDays ?? 7,
      reopenToStatus: w.reopenToStatus ?? 'Pending',
      notifyAssigned: w.notifyAssigned ?? true,
      reopenedLast30d: w.reopenedLast30d ?? 0,
      repliesAfterWindow30d: w.repliesAfterWindow30d ?? 0,
      medianDaysToReply: w.medianDaysToReply?.round() ?? 0,
    );
  }
}

/// The body for `PUT /cases/reopen-policy/`.
///
/// All four fields go every time. The endpoint is `partial=True` and would
/// accept a subset, but the form edits all four at once and a partial body
/// makes "switched off" and "not sent" the same thing for the two booleans.
Map<String, dynamic> reopenPolicyPayload({
  required bool isEnabled,
  required int windowDays,
  required String reopenToStatus,
  required bool notifyAssigned,
}) => {
  'is_enabled': isEnabled,
  'reopen_window_days': windowDays,
  'reopen_to_status': reopenToStatus,
  'notify_assigned': notifyAssigned,
};

/// What a reopen save has to fix before it is worth sending, or `null`.
///
/// Both rules are `ReopenPolicySerializer`'s, which is the authority. These
/// exist so a typo answers immediately rather than after a round trip.
String? reopenPolicyProblem({
  required int? windowDays,
  required String reopenToStatus,
}) {
  if (windowDays == null ||
      windowDays < reopenWindowMin ||
      windowDays > reopenWindowMax) {
    return appL10n.appReopenValidateWindow(reopenWindowMin, reopenWindowMax);
  }
  if (!reopenToStatuses.contains(reopenToStatus)) {
    return appL10n.appReopenValidateStatus;
  }
  return null;
}

/// What the policy does, in one sentence.
String reopenSummary(ReopenPolicy policy) {
  if (!policy.isEnabled) return appL10n.appReopenSummaryOff;
  final status = TicketStatus.values
      .where((s) => s.value == policy.reopenToStatus)
      .firstOrNull;
  return appL10n.appReopenSummaryOn(
    policy.windowDays,
    status?.label ?? policy.reopenToStatus,
  );
}

/// The note that has to sit under the missed-window figure when the policy is
/// off, or `null`.
String? missedWindowCaveat(ReopenPolicy policy) {
  if (policy.missedWindowIsMeasured) return null;
  return appL10n.appReopenMissedCaveat;
}
