import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/deal.dart' show Currency;
import '../../data/models/lookup_models.dart';
import '../../data/models/sales_goal.dart';
import '../../providers/auth_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/lookup_provider.dart';
import '../../services/org_date.dart';
import '../../widgets/forms/unsaved_changes.dart';
import '../../l10n/l10n.dart';

/// Create or edit a sales goal.
///
/// Admin-only, and the gate is checked before the form is drawn rather than on
/// submit: `SalesGoalListView.post` and `SalesGoalDetailView.put`/`delete` all
/// answer 403 to a member, so drawing the form for one would be an invitation
/// to fill in a page that cannot save. The server is what refuses; this only
/// avoids offering.
///
/// One target picker, not two. The API has separate `assigned_to` and `team`
/// FKs and permits both at once, but a goal belonging to a person and a team
/// simultaneously has no meaning in either client's reading of progress, so the
/// picker offers one choice and [goalTargetFields] decodes it into exactly one.
class GoalFormScreen extends ConsumerStatefulWidget {
  const GoalFormScreen({super.key, this.goalId});

  /// Null when creating.
  final String? goalId;

  bool get isEditing => goalId != null;

  @override
  ConsumerState<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends ConsumerState<GoalFormScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _target = TextEditingController();

  /// One controller per deal type. A blank box means "count this type in full",
  /// so nothing is pre-filled with 1: an untouched form has to store an empty
  /// map, or every goal would grow five redundant weights the first time
  /// somebody opened its edit screen.
  final Map<String, TextEditingController> _weights = {
    for (final type in dealTypes) type: TextEditingController(),
  };
  bool _weightsOpen = false;

  String _goalType = 'REVENUE';

  /// The currency a REVENUE target is in. The server counts only the won deals
  /// in it, so it is part of the bar rather than a display choice. Normalised
  /// through [Currency] so the picker always holds one of its own items.
  String _currency = Currency.usd.value;
  String _periodType = 'MONTHLY';
  String _periodStart = '';
  String _periodEnd = '';
  String _targetOwner = 'org';
  bool _isActive = true;

  /// How many boxes hold something other than the default weight of 1.
  int get _weightedCount => _weights.values
      .where(
        (c) => c.text.trim().isNotEmpty && num.tryParse(c.text.trim()) != 1,
      )
      .length;

  bool _saving = false;
  bool _dirty = false;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.isEditing) {
      // The org's currency, the same default the server applies when none is
      // sent, so an untouched picker and an omitted field mean the same goal.
      _currency = Currency.fromString(
        ref.read(selectedOrgProvider)?.defaultCurrency,
      ).value;
      // A month starting today is the shape most goals take, and a form that
      // opens with both dates blank makes somebody type what they were going to
      // pick anyway. Changed freely; nothing depends on the default. The
      // org's day, not the phone's.
      final today = orgToday();
      _periodStart = goalToday(today);
      _periodEnd = goalToday(DateTime(today.year, today.month + 1, today.day));
      _loaded = true;
    }
    _name.addListener(_markDirty);
    _target.addListener(_markDirty);
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    for (final controller in _weights.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && _loaded) _dirty = true;
  }

  void _fill(SalesGoal goal) {
    _name.text = goal.name;
    // `toStringAsFixed(2)` would show "50000.00" for a round quota. The server
    // sends a DecimalField, so trailing zeros are on the wire, and trimming
    // them is the difference between a field somebody edits and one they
    // retype.
    _target.text = goal.targetValue == goal.targetValue.roundToDouble()
        ? goal.targetValue.round().toString()
        : goal.targetValue.toString();
    _goalType = goal.goalType;
    if (goal.currency != null) {
      _currency = Currency.fromString(goal.currency).value;
    }
    _periodType = goal.periodType;
    _periodStart = goal.periodStart;
    _periodEnd = goal.periodEnd;
    _targetOwner = goalTargetValue(goal);
    _isActive = goal.isActive;
    // Whole weights print without a ".0", as the target does: the wire type
    // reads every weight as a double, so a stored 2 arrives as 2.0.
    for (final entry in goal.typeWeights.entries) {
      final weight = entry.value;
      _weights[entry.key]?.text = weight == weight.roundToDouble()
          ? weight.round().toString()
          : weight.toString();
    }
    // Open when the goal already carries weights, so an existing weighting is
    // visible rather than hidden behind a control nobody thought to tap.
    _weightsOpen = goal.typeWeights.isNotEmpty;
    // Set last: filling the controllers fires the listeners above, and a form
    // that opens already dirty prompts on the way out of a page nobody edited.
    _loaded = true;
    _dirty = false;
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = DateTime.tryParse(isStart ? _periodStart : _periodEnd);
    final today = orgToday();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? today,
      // Wide enough for a goal set against a past period (backfilling last
      // quarter) and for a multi-year one.
      firstDate: DateTime(today.year - 3),
      lastDate: DateTime(today.year + 6),
    );
    if (picked == null) return;
    setState(() {
      _dirty = true;
      if (isStart) {
        _periodStart = goalToday(picked);
      } else {
        _periodEnd = goalToday(picked);
      }
    });
  }

  Future<void> _save() async {
    final problem = validateGoalForm(
      name: _name.text,
      targetValue: _target.text,
      periodStart: _periodStart,
      periodEnd: _periodEnd,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'goal_type': _goalType,
      'target_value': _target.text.trim(),
      'currency': _currency,
      'period_type': _periodType,
      'period_start': _periodStart,
      'period_end': _periodEnd,
      'is_active': _isActive,
      ...goalTargetFields(_targetOwner),
      // Empty for an ACTIVITIES goal, which has no deal type and which the
      // backend refuses weights on. Sent either way so clearing a box clears
      // the weight: PUT is partial, and an omitted key keeps the old map.
      ...goalWeightFields(
        _goalType == 'ACTIVITIES'
            ? const {}
            : {
                for (final entry in _weights.entries)
                  entry.key: entry.value.text,
              },
      ),
    };

    final notifier = ref.read(goalsProvider.notifier);
    final response = widget.isEditing
        ? await notifier.updateGoal(widget.goalId!, body)
        : await notifier.createGoal(body);

    if (!mounted) return;
    if (!response.success) {
      setState(() {
        _saving = false;
        _error = response.message ?? context.l10n.goalsFormSaveFailed;
      });
      return;
    }

    _dirty = false;
    final saved = widget.isEditing
        ? context.l10n.goalsFormUpdated
        : context.l10n.goalsFormCreated;
    context.pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved)));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.goalsFormDeleteTitle),
        content: Text(context.l10n.goalsFormDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.goalsFormKeepIt),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger600),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final response = await ref
        .read(goalsProvider.notifier)
        .deleteGoal(widget.goalId!);
    if (!mounted) return;
    if (!response.success) {
      setState(() {
        _saving = false;
        _error = response.message ?? context.l10n.goalsFormDeleteFailed;
      });
      return;
    }
    _dirty = false;
    final deleted = context.l10n.goalsFormDeleted;
    context.pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(deleted)));
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(isOrgAdminProvider)) return const _AdminsOnly();

    if (widget.isEditing && !_loaded) {
      return ref
          .watch(goalProvider(widget.goalId!))
          .when(
            loading: () => const _Busy(),
            error: (e, _) => _LoadFailed(message: e.toString()),
            data: (goal) {
              _fill(goal);
              return _form(context);
            },
          );
    }
    return _form(context);
  }

  Widget _form(BuildContext context) {
    final people = ref.watch(usersProvider);
    final teams = ref.watch(teamsProvider);
    final l10n = context.l10n;

    return UnsavedChangesGuard(
      hasUnsavedChanges: () => _dirty,
      isSaving: _saving,
      child: Scaffold(
        backgroundColor: AppColors.surfaceDim,
        appBar: AppBar(
          title: Text(
            widget.isEditing ? l10n.goalsFormEditTitle : l10n.goalsFormNewTitle,
          ),
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: _saving
                ? null
                : () => leaveForm(context, hasUnsavedChanges: _dirty),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.danger200),
                ),
                child: Text(
                  _error!,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.danger600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 255,
              decoration: InputDecoration(
                labelText: l10n.goalsFormName,
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _goalType,
              decoration: InputDecoration(
                labelText: l10n.goalsFormMeasuredIn,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final type in goalTypes)
                  DropdownMenuItem(
                    value: type,
                    child: Text(goalTypeLabel(type)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _goalType = value ?? _goalType;
                      _dirty = true;
                    }),
            ),
            const SizedBox(height: 16),

            // Only a revenue goal is in a currency; deals and activities are
            // counts. The value is still sent for them, and it is the one the
            // goal already had, so switching the type back loses nothing.
            if (_goalType == 'REVENUE') ...[
              DropdownButtonFormField<String>(
                initialValue: _currency,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.goalsFormCurrency,
                  helperText: l10n.goalsFormCurrencyHelper,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final c in Currency.values)
                    DropdownMenuItem(value: c.value, child: Text(c.value)),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _currency = value ?? _currency;
                        _dirty = true;
                      }),
              ),
              const SizedBox(height: 16),
            ],

            TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                labelText: l10n.goalsFormTarget,
                border: const OutlineInputBorder(),
                helperText: switch (_goalType) {
                  'DEALS_CLOSED' => l10n.goalsFormTargetDeals,
                  'ACTIVITIES' => l10n.goalsFormTargetActivities,
                  _ => l10n.goalsFormTargetRevenue,
                },
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),

            // Optional per-deal-type multipliers. Hidden entirely for an
            // ACTIVITIES goal, which counts logged activity and has no deal
            // type to weigh; the backend refuses weights on one with a 400.
            if (_goalType != 'ACTIVITIES') ...[
              InkWell(
                onTap: () => setState(() => _weightsOpen = !_weightsOpen),
                child: Container(
                  // 44px so the row is a real tap target between two other
                  // controls, where a few pixels either way is easy to miss.
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.goalsFormWeightTitle,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        _weightedCount == 0
                            ? l10n.goalsFormWeightOptional
                            : l10n.goalsFormWeightAdjusted(_weightedCount),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Icon(
                        _weightsOpen
                            ? LucideIcons.chevronUp
                            : LucideIcons.chevronDown,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                    ],
                  ),
                ),
              ),
              if (_weightsOpen) ...[
                const SizedBox(height: 8),
                for (final type in dealTypes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dealTypeLabel(type),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 96,
                          child: TextField(
                            controller: _weights[type],
                            textAlign: TextAlign.right,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              hintText: '1',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  l10n.goalsFormWeightHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
              const SizedBox(height: 16),
            ],

            DropdownButtonFormField<String>(
              initialValue: _periodType,
              decoration: InputDecoration(
                labelText: l10n.goalsFormPeriod,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final period in goalPeriodTypes)
                  DropdownMenuItem(
                    value: period,
                    child: Text(goalPeriodLabel(period)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _periodType = value ?? _periodType;
                      _dirty = true;
                    }),
            ),
            const SizedBox(height: 6),
            Text(
              // The dates are what the server actually counts against, and the
              // period type is only a label on the board's filter. Saying so
              // stops somebody choosing Monthly and expecting the dates to
              // follow.
              l10n.goalsFormPeriodHint,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: l10n.goalsFormStarts,
                    value: _periodStart,
                    onTap: _saving ? null : () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: l10n.goalsFormEnds,
                    value: _periodEnd,
                    onTap: _saving ? null : () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _ownerValue(people, teams),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.goalsFormGoalFor,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'org',
                  child: Text(l10n.goalsFormWholeOrg),
                ),
                for (final person in people)
                  DropdownMenuItem(
                    value: 'profile:${person.id}',
                    child: Text(
                      person.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                for (final team in teams)
                  DropdownMenuItem(
                    value: 'team:${team.id}',
                    child: Text(
                      l10n.goalsFormTeam(team.name),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _targetOwner = value ?? _targetOwner;
                      _dirty = true;
                    }),
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _isActive = value;
                      _dirty = true;
                    }),
              title: Text(l10n.goalsFormActive),
              subtitle: Text(
                l10n.goalsFormActiveHint,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.isEditing
                            ? l10n.goalsFormSaveChanges
                            : l10n.goalsFormCreate,
                      ),
              ),
            ),

            if (widget.isEditing) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _saving ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger600,
                    side: BorderSide(color: AppColors.danger200),
                  ),
                  child: Text(l10n.goalsFormDelete),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The dropdown's value, guarded against an option that is not in the list.
  ///
  /// A goal assigned to somebody since deactivated has an `assigned_to` the
  /// people lookup (active profiles only) does not carry, and a
  /// `DropdownButtonFormField` whose value matches no item throws. Falling back
  /// to `org` would silently reassign the goal on the next save, so the stored
  /// value is kept and only the DISPLAY falls back, with the mismatch surfaced
  /// as an extra item.
  String? _ownerValue(List<UserLookup> people, List<TeamLookup> teams) {
    if (_targetOwner == 'org') return 'org';
    final known = [
      for (final p in people) 'profile:${p.id}',
      for (final t in teams) 'team:${t.id}',
    ];
    return known.contains(_targetOwner) ? _targetOwner : null;
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        // A 48px box keeps the tap target above the 44px floor, which an
        // InputDecorator wrapping a single line of text does not reach on its
        // own.
        child: SizedBox(
          height: 24,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(value.isEmpty ? context.l10n.goalsFormPickDate : value),
          ),
        ),
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.goalsFormGoalTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            message,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _AdminsOnly extends StatelessWidget {
  const _AdminsOnly();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.goalsFormGoalTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.l10n.goalsFormAdminsOnly,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
