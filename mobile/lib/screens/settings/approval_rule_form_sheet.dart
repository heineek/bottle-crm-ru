import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../data/models/approval_rule.dart';
import '../../data/models/lookup_models.dart';
import '../../l10n/l10n.dart';
import '../../providers/lookup_provider.dart';

/// Write or edit an approval rule.
///
/// Returns the request body, or null if dismissed. Create and edit send the
/// same shape: nothing on this resource is frozen after creation.
Future<Map<String, dynamic>?> showApprovalRuleFormSheet(
  BuildContext context, {
  ApprovalRule? existing,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ApprovalRuleFormSheet(existing: existing),
  );
}

class _ApprovalRuleFormSheet extends ConsumerStatefulWidget {
  const _ApprovalRuleFormSheet({this.existing});

  final ApprovalRule? existing;

  @override
  ConsumerState<_ApprovalRuleFormSheet> createState() =>
      _ApprovalRuleFormSheetState();
}

class _ApprovalRuleFormSheetState
    extends ConsumerState<_ApprovalRuleFormSheet> {
  late final TextEditingController _name;
  late String _role;
  late List<String> _approverIds;
  String? _priority;
  String? _caseType;
  String? _teamId;
  String? _error;

  bool get _isCreate => widget.existing == null;

  /// Approvers named on the rule who are not in the picker, which offers active
  /// profiles only. Dropping them would narrow the rule as a side effect of
  /// opening the form, and on a manager rule that leaves it clearable by
  /// nobody. Kept, labelled, and removable on purpose.
  Map<String, String> get _offListNames => {
    for (final person in widget.existing?.approvers ?? const <UserLookup>[])
      if (!person.isActive) person.id: person.displayName,
  };

  @override
  void initState() {
    super.initState();
    final rule = widget.existing;
    _name = TextEditingController(text: rule?.name ?? '');
    _role = rule?.approverRole ?? 'ADMIN';
    _approverIds = [
      for (final person in rule?.approvers ?? const []) person.id,
    ];
    _priority = rule?.matchPriority;
    _caseType = rule?.matchCaseType;
    _teamId = rule?.matchTeam?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = approvalRuleNameProblem(_name.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(
      approvalRulePayload(
        name: _name.text,
        approverRole: _role,
        approverIds: _approverIds,
        matchPriority: _priority,
        matchCaseType: _caseType,
        matchTeamId: _teamId,
        // Only the create form carries this. On an edit the row's own Turn off
        // and Turn on controls own the state.
        isActive: _isCreate ? true : null,
      ),
    );
  }

  /// Who could clear the rule as the form currently stands, so the answer is
  /// visible before saving rather than on the row afterwards.
  String get _clearedBy {
    final l10n = context.l10n;
    final named = [
      for (final person in ref.read(usersProvider))
        if (_approverIds.contains(person.id)) person.displayName,
      for (final entry in _offListNames.entries)
        if (_approverIds.contains(entry.key)) entry.value,
    ];
    if (rolesThatExist.contains(_role)) {
      return named.isEmpty
          ? l10n.settingsApprovalRuleFormAnyAdmin
          : l10n.settingsApprovalRuleFormAnyAdminOr(
              named.join(l10n.settingsApprovalRuleFormOrSeparator),
            );
    }
    return named.isEmpty
        ? l10n.settingsApprovalRuleFormNobody
        : named.join(l10n.settingsApprovalRuleFormOrSeparator);
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(usersProvider);
    final teams = ref.watch(teamsProvider);
    final offList = _offListNames;
    final strandsTickets =
        _clearedBy == context.l10n.settingsApprovalRuleFormNobody;

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
                  ? context.l10n.settingsApprovalRuleFormNewTitle
                  : context.l10n.settingsApprovalRuleFormEditTitle(
                      widget.existing!.name,
                    ),
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 128,
              decoration: InputDecoration(
                labelText: context.l10n.settingsApprovalRuleFormNameLabel,
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            _SectionLabel(context.l10n.settingsApprovalRuleFormSectionGates),
            DropdownButtonFormField<String?>(
              initialValue: _priority,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.commonPriority,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(context.l10n.settingsApprovalRuleFormAny),
                ),
                for (final priority in approvalPriorities)
                  DropdownMenuItem(value: priority, child: Text(priority)),
              ],
              onChanged: (v) => setState(() => _priority = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _caseType,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.settingsApprovalRuleFormTicketType,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(context.l10n.settingsApprovalRuleFormAny),
                ),
                for (final type in approvalCaseTypes)
                  DropdownMenuItem(value: type, child: Text(type)),
              ],
              onChanged: (v) => setState(() => _caseType = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: teams.any((t) => t.id == _teamId) ? _teamId : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.settingsApprovalRuleFormTeam,
                helperText: teams.isEmpty
                    ? context.l10n.settingsApprovalRuleFormNoTeams
                    : null,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(context.l10n.settingsApprovalRuleFormAnyTeam),
                ),
                for (final team in teams)
                  DropdownMenuItem(value: team.id, child: Text(team.name)),
              ],
              onChanged: (v) => setState(() => _teamId = v),
            ),
            const SizedBox(height: 16),
            _SectionLabel(context.l10n.settingsApprovalRuleFormSectionWho),
            DropdownButtonFormField<String>(
              initialValue: _role,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.settingsApprovalRuleFormRole,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final choice in approverRoleChoices)
                  DropdownMenuItem(
                    value: choice.value,
                    child: Text(choice.label),
                  ),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.settingsApprovalRuleFormPickedHint,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final person in people)
                  FilterChip(
                    label: Text(person.displayName),
                    selected: _approverIds.contains(person.id),
                    onSelected: (on) => setState(() {
                      on
                          ? _approverIds.add(person.id)
                          : _approverIds.remove(person.id);
                    }),
                  ),
                for (final entry in offList.entries)
                  if (_approverIds.contains(entry.key))
                    FilterChip(
                      label: Text(
                        context.l10n.settingsApprovalRuleFormDeactivated(
                          entry.value,
                        ),
                      ),
                      selected: true,
                      onSelected: (_) =>
                          setState(() => _approverIds.remove(entry.key)),
                    ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.settingsApprovalRuleFormClearedBy(_clearedBy),
              style: AppTypography.caption.copyWith(
                color: strandsTickets
                    ? AppColors.danger600
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (strandsTickets) ...[
              const SizedBox(height: 6),
              Text(
                context.l10n.settingsApprovalRuleFormStrandsWarning,
                style: AppTypography.caption.copyWith(
                  color: AppColors.danger600,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTypography.caption.copyWith(
                  color: AppColors.danger600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.l10n.commonCancel),
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
                            ? context.l10n.settingsApprovalRuleFormAddRule
                            : context.l10n.settingsApprovalRuleFormSaveChanges,
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
