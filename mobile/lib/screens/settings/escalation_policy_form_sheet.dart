import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../data/models/escalation_policy.dart';
import '../../data/models/lookup_models.dart';
import '../../data/models/ticket.dart';
import '../../l10n/l10n.dart';
import '../../providers/lookup_provider.dart';

/// The result of the sheet: which request to send, and what to send.
///
/// Create and edit do not send the same body. `priority` exists only on a
/// create and `is_active` only on a create, so the two are built by separate
/// functions rather than one payload with holes in it.
typedef EscalationFormResult = Map<String, dynamic>;

/// A priority code ("High") as the ticket screens name it, or the code itself
/// for one this build does not know.
String escalationPriorityName(String code) {
  for (final p in TicketPriority.values) {
    if (p.value == code) return p.displayName;
  }
  return code;
}

/// Write or edit an escalation policy.
///
/// Returns the request body, or `null` if dismissed. [availablePriorities] is
/// the set a create may choose from: at most one policy exists per priority, so
/// offering a taken one would only produce a 400 the admin could have been
/// spared. It is ignored on an edit, where the priority is frozen.
Future<EscalationFormResult?> showEscalationPolicyFormSheet(
  BuildContext context, {
  EscalationPolicy? existing,
  List<String> availablePriorities = const [],
}) {
  return showModalBottomSheet<EscalationFormResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _EscalationPolicyFormSheet(
      existing: existing,
      availablePriorities: availablePriorities,
    ),
  );
}

class _EscalationPolicyFormSheet extends ConsumerStatefulWidget {
  const _EscalationPolicyFormSheet({
    this.existing,
    required this.availablePriorities,
  });

  final EscalationPolicy? existing;
  final List<String> availablePriorities;

  @override
  ConsumerState<_EscalationPolicyFormSheet> createState() =>
      _EscalationPolicyFormSheetState();
}

class _EscalationPolicyFormSheetState
    extends ConsumerState<_EscalationPolicyFormSheet> {
  late String _priority;
  late String _firstResponseAction;
  late String _resolutionAction;

  /// `''` is "Nobody", which the payload turns into `null`.
  late String _firstResponseTargetId;
  late String _resolutionTargetId;
  late String _teamId;

  /// Blank means "no override", which falls back to the built-in default for
  /// this priority. Kept as text so an emptied field stays distinguishable
  /// from a zero the serializer would reject anyway.
  late final TextEditingController _firstResponseHours;
  late final TextEditingController _resolutionHours;
  late final TextEditingController _nextResponseHours;
  String? _hoursError;

  bool get _isCreate => widget.existing == null;

  /// Targets already on the policy whom the picker cannot offer.
  ///
  /// `GetTeamsAndUsersView` returns `Profile.objects.filter(is_active=True)`
  /// while `first_response_target` / `resolution_target` carry whoever was
  /// chosen, deactivated or not, and the engine escalates to them with no
  /// active filter. Without an entry of their own, opening this form to change
  /// one unrelated field would drop the target to Nobody and stop breaches at
  /// this priority escalating to anybody.
  Map<String, String> get _offListNames => {
    for (final target in widget.existing?.deactivatedTargets ?? const [])
      target.id: target.displayName,
  };

  @override
  void initState() {
    super.initState();
    final policy = widget.existing;
    _priority =
        policy?.priority ??
        (widget.availablePriorities.isNotEmpty
            ? widget.availablePriorities.first
            : escalationPriorities.first);
    _firstResponseAction =
        policy?.firstResponseAction ?? escalationActionNotify;
    _resolutionAction = policy?.resolutionAction ?? escalationActionNotify;
    _firstResponseTargetId = policy?.firstResponseTarget?.id ?? '';
    _resolutionTargetId = policy?.resolutionTarget?.id ?? '';
    _teamId = policy?.notifyTeam?.id ?? '';
    _firstResponseHours = TextEditingController(
      text: policy?.firstResponseHours?.toString() ?? '',
    );
    _resolutionHours = TextEditingController(
      text: policy?.resolutionHours?.toString() ?? '',
    );
    // Prefilled like the other two: the edit body always carries the key, so
    // a field left empty here would clear a stored override.
    _nextResponseHours = TextEditingController(
      text: policy?.nextResponseHours?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _firstResponseHours.dispose();
    _resolutionHours.dispose();
    _nextResponseHours.dispose();
    super.dispose();
  }

  void _submit() {
    final first = parseSlaHours(_firstResponseHours.text);
    final resolution = parseSlaHours(_resolutionHours.text);
    final next = parseSlaHours(_nextResponseHours.text);
    final error = first.error ?? next.error ?? resolution.error;
    if (error != null) {
      setState(() => _hoursError = error);
      return;
    }
    Navigator.of(context).pop(
      _isCreate
          ? escalationCreatePayload(
              priority: _priority,
              firstResponseAction: _firstResponseAction,
              resolutionAction: _resolutionAction,
              firstResponseTargetId: _firstResponseTargetId,
              resolutionTargetId: _resolutionTargetId,
              notifyTeamId: _teamId,
              firstResponseHours: first.hours,
              resolutionHours: resolution.hours,
              nextResponseHours: next.hours,
            )
          : escalationUpdatePayload(
              firstResponseAction: _firstResponseAction,
              resolutionAction: _resolutionAction,
              firstResponseTargetId: _firstResponseTargetId,
              resolutionTargetId: _resolutionTargetId,
              notifyTeamId: _teamId,
              firstResponseHours: first.hours,
              resolutionHours: resolution.hours,
              nextResponseHours: next.hours,
            ),
    );
  }

  /// One hours field. Blank is legal and means the built-in default, which the
  /// hint names so an empty box never reads as "no SLA".
  Widget _hoursField({
    required String label,
    required TextEditingController controller,
    required int defaultHours,
    String? helperText,
  }) {
    final l10n = context.l10n;
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        hintText: l10n.settingsEscalationPolicyFormHoursHint(defaultHours),
        helperText: helperText ?? l10n.settingsEscalationPolicyFormHoursHelper,
        helperMaxLines: 4,
      ),
      onChanged: (_) {
        if (_hoursError != null) setState(() => _hoursError = null);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(usersProvider);
    final teams = ref.watch(teamsProvider);
    final offList = _offListNames;
    final l10n = context.l10n;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isCreate
                  ? l10n.settingsEscalationPolicyFormNewTitle
                  : l10n.settingsEscalationPolicyFormEditTitle(
                      escalationPriorityName(widget.existing!.priority),
                    ),
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (_isCreate)
              DropdownButtonFormField<String>(
                initialValue: _priority,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.commonPriority,
                  helperText: l10n.settingsEscalationPolicyFormPriorityHelper,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final priority in widget.availablePriorities)
                    DropdownMenuItem(
                      value: priority,
                      child: Text(escalationPriorityName(priority)),
                    ),
                ],
                onChanged: (v) => setState(() => _priority = v ?? _priority),
              )
            else
              // Not a disabled select. `EscalationPolicyDetailView.put` strips
              // `priority` from the body, so any control here would report a
              // change it did not make.
              Text(
                l10n.settingsEscalationPolicyFormPriorityFixed(
                  escalationPriorityName(widget.existing!.priority),
                ),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 20),
            _SectionLabel(l10n.settingsEscalationPolicyFormSlaSection),
            const SizedBox(height: 8),
            _hoursField(
              label: l10n.settingsEscalationPolicyFormFirstResponse,
              controller: _firstResponseHours,
              defaultHours: defaultSlaHours(
                _priority,
                EscalationHalf.firstResponse,
              ),
            ),
            const SizedBox(height: 12),
            // Scored by `compute_nrt` on wall-clock hours and read by no
            // escalation scan, so its helper says both instead of inheriting
            // the business-hours line of the other two.
            _hoursField(
              label: l10n.settingsEscalationPolicyFormNextResponse,
              controller: _nextResponseHours,
              defaultHours: defaultNextResponseHours(_priority),
              helperText: l10n.settingsEscalationPolicyFormNextHelper,
            ),
            const SizedBox(height: 12),
            _hoursField(
              label: l10n.settingsEscalationPolicyFormResolution,
              controller: _resolutionHours,
              defaultHours: defaultSlaHours(
                _priority,
                EscalationHalf.resolution,
              ),
            ),
            if (_hoursError != null) ...[
              const SizedBox(height: 8),
              Text(
                _hoursError!,
                style: AppTypography.caption.copyWith(
                  color: AppColors.danger600,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              l10n.settingsEscalationPolicyFormApplyNote,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            _HalfFields(
              half: EscalationHalf.firstResponse,
              action: _firstResponseAction,
              targetId: _firstResponseTargetId,
              people: people,
              offList: offList,
              onAction: (v) => setState(() => _firstResponseAction = v),
              onTarget: (v) => setState(() => _firstResponseTargetId = v),
            ),
            const SizedBox(height: 20),
            _HalfFields(
              half: EscalationHalf.resolution,
              action: _resolutionAction,
              targetId: _resolutionTargetId,
              people: people,
              offList: offList,
              onAction: (v) => setState(() => _resolutionAction = v),
              onTarget: (v) => setState(() => _resolutionTargetId = v),
            ),
            const SizedBox(height: 20),
            _SectionLabel(l10n.settingsEscalationPolicyFormAlsoNotify),
            DropdownButtonFormField<String>(
              initialValue: teams.any((t) => t.id == _teamId) ? _teamId : '',
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.settingsEscalationPolicyFormTeamLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(l10n.settingsEscalationPolicyFormNoTeam),
                ),
                for (final team in teams)
                  DropdownMenuItem(value: team.id, child: Text(team.name)),
              ],
              onChanged: (v) => setState(() => _teamId = v ?? ''),
            ),
            const SizedBox(height: 6),
            Text(
              teams.isEmpty
                  ? l10n.settingsEscalationPolicyFormNoTeams
                  : l10n.settingsEscalationPolicyFormTeamHint,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _submit,
                      child: Text(
                        _isCreate
                            ? l10n.settingsEscalationPolicyFormAddPolicy
                            : l10n.settingsEscalationPolicyFormSaveChanges,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One half of the SLA: what to do, and who to do it to.
class _HalfFields extends StatelessWidget {
  const _HalfFields({
    required this.half,
    required this.action,
    required this.targetId,
    required this.people,
    required this.offList,
    required this.onAction,
    required this.onTarget,
  });

  final EscalationHalf half;
  final String action;
  final String targetId;
  final List<UserLookup> people;
  final Map<String, String> offList;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final knownIds = {'', ...people.map((p) => p.id), ...offList.keys};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(half.label),
        DropdownButtonFormField<String>(
          initialValue: action,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.settingsEscalationPolicyFormDoWhat,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final entry in escalationActionLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) => onAction(v ?? action),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: knownIds.contains(targetId) ? targetId : '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.settingsEscalationPolicyFormToWhom,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(l10n.settingsEscalationPolicyFormNobody),
            ),
            for (final person in people)
              DropdownMenuItem(
                value: person.id,
                child: Text(person.displayName),
              ),
            // A deactivated target the picker cannot offer, kept so opening the
            // form does not silently empty the policy.
            for (final entry in offList.entries)
              if (entry.key != '' && !people.any((p) => p.id == entry.key))
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    l10n.settingsEscalationPolicyFormDeactivated(entry.value),
                  ),
                ),
          ],
          onChanged: (v) => onTarget(v ?? ''),
        ),
        if (targetId.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            escalationNoTargetHint,
            style: AppTypography.caption.copyWith(color: AppColors.warning600),
          ),
        ] else if (offList.containsKey(targetId)) ...[
          const SizedBox(height: 6),
          Text(
            l10n.settingsEscalationPolicyFormInactiveTarget,
            style: AppTypography.caption.copyWith(color: AppColors.warning600),
          ),
        ] else if (!escalationActionNotifies(action)) ...[
          const SizedBox(height: 6),
          Text(
            l10n.settingsEscalationPolicyFormReassignHint,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.overline.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
