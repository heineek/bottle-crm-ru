import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/macro.dart';
import '../../data/models/ticket.dart';
import '../../l10n/l10n.dart';
import '../../providers/lookup_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/forms/multi_select_sheet.dart';

/// Write or edit a saved reply.
///
/// Returns the request body, or `null` if dismissed. [canCreateOrg] only
/// decides whether the "Everyone" choice is offered.
/// `_resolve_scope_and_owner` re-derives admin status from `request.profile`
/// and is what actually turns a non-admin's org-scope attempt into a 403.
///
/// The action pickers offer the active members and tags (`usersProvider`,
/// `tagsProvider`, both filtered to active rows). Whatever the macro already
/// carries is offered on top, deactivated or archived ones included, so saving
/// never drops one by omission; the server keeps a stored one and refuses a
/// newly named inactive one.
Future<Map<String, dynamic>?> showMacroFormSheet(
  BuildContext context, {
  Macro? existing,
  required bool canCreateOrg,
  required List<MacroPlaceholder> placeholders,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _MacroFormSheet(
      existing: existing,
      canCreateOrg: canCreateOrg,
      placeholders: placeholders,
    ),
  );
}

/// [active] plus any of [stored] it does not already hold.
/// A status or priority code as the ticket screens name it, or the code
/// itself for one this build does not know.
String _statusName(String code) {
  for (final s in TicketStatus.values) {
    if (s.value == code) return s.displayName;
  }
  return code;
}

String _priorityName(String code) {
  for (final p in TicketPriority.values) {
    if (p.value == code) return p.displayName;
  }
  return code;
}

List<MacroRef> _withStored(List<MacroRef> active, List<MacroRef> stored) {
  final ids = {for (final r in active) r.id};
  return [...active, ...stored.where((r) => !ids.contains(r.id))];
}

class _MacroFormSheet extends ConsumerStatefulWidget {
  const _MacroFormSheet({
    this.existing,
    required this.canCreateOrg,
    required this.placeholders,
  });

  final Macro? existing;
  final bool canCreateOrg;
  final List<MacroPlaceholder> placeholders;

  @override
  ConsumerState<_MacroFormSheet> createState() => _MacroFormSheetState();
}

class _MacroFormSheetState extends ConsumerState<_MacroFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late String _scope;
  late String _status;
  late String _priority;
  late List<MacroRef> _assignees;
  late List<MacroRef> _tags;
  String? _error;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _title = TextEditingController(text: m?.title ?? '');
    _body = TextEditingController(text: m?.body ?? '');
    // A member has one option, so default to it rather than to a scope the
    // server would refuse.
    _scope =
        m?.scope ??
        (widget.canCreateOrg ? Macro.scopeOrg : Macro.scopePersonal);
    _status = m?.setStatus ?? '';
    _priority = m?.setPriority ?? '';
    _assignees = [...?m?.assignees];
    _tags = [...?m?.tags];
  }

  bool get _hasAction =>
      _status.isNotEmpty ||
      _priority.isNotEmpty ||
      _assignees.isNotEmpty ||
      _tags.isNotEmpty;

  Future<void> _pickPeople() async {
    final active = [
      for (final u in ref.read(usersProvider))
        MacroRef(id: u.id, name: u.displayName),
    ];
    final options = _withStored(active, widget.existing?.assignees ?? []);
    final picked = await MultiSelectSheet.show<MacroRef>(
      context: context,
      title: context.l10n.settingsMacroFormAssignTo,
      items: options,
      initialSelection: options
          .where((o) => _assignees.any((a) => a.id == o.id))
          .toList(),
      labelOf: (r) => r.label,
      searchText: (r) => r.name,
      emptyMessage: context.l10n.settingsMacroFormNoMembers,
    );
    if (picked != null && mounted) setState(() => _assignees = picked);
  }

  Future<void> _pickTags() async {
    final active = [
      for (final t in ref.read(tagsProvider))
        MacroRef(id: t.id, name: t.name, isPerson: false),
    ];
    final options = _withStored(active, widget.existing?.tags ?? []);
    final picked = await MultiSelectSheet.show<MacroRef>(
      context: context,
      title: context.l10n.settingsMacroFormAddTags,
      items: options,
      initialSelection: options
          .where((o) => _tags.any((t) => t.id == o.id))
          .toList(),
      labelOf: (r) => r.label,
      searchText: (r) => r.name,
      emptyMessage: context.l10n.settingsMacroFormNoTags,
    );
    if (picked != null && mounted) setState(() => _tags = picked);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Drop a token into the body at the cursor. Typing `%customer_name%` on a
  /// phone keyboard is four mode switches, and a typo is not caught at save
  /// time: an unknown token renders literally into a reply to a customer.
  void _insert(String token) {
    final selection = _body.selection;
    final text = _body.text;
    final at = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(at, end, token);
    _body.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + token.length),
    );
  }

  void _submit() {
    final problem = validateMacroDraft(
      title: _title.text,
      body: _body.text,
      scope: _scope,
      hasAction: _hasAction,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(
      macroPayload(
        title: _title.text,
        body: _body.text,
        scope: _scope,
        setStatus: _status,
        setPriority: _priority,
        assigneeIds: [for (final a in _assignees) a.id],
        tagIds: [for (final t in _tags) t.id],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched so the two lists load while the form is open; the pickers read
    // them when tapped.
    ref.watch(usersProvider);
    ref.watch(tagsProvider);
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
                  ? l10n.settingsMacroFormNewTitle
                  : l10n.settingsMacroFormEditTitle(widget.existing!.title),
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 255,
              decoration: InputDecoration(
                labelText: l10n.settingsMacroFormTitleLabel,
                helperText: l10n.settingsMacroFormTitleHelper,
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            if (widget.canCreateOrg)
              DropdownButtonFormField<String>(
                initialValue: _scope,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.settingsMacroFormScopeLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: Macro.scopeOrg,
                    child: Text(l10n.settingsMacroFormScopeOrg),
                  ),
                  DropdownMenuItem(
                    value: Macro.scopePersonal,
                    child: Text(l10n.settingsMacroFormScopeMe),
                  ),
                ],
                onChanged: (v) => setState(() => _scope = v ?? _scope),
              )
            else
              // Not a disabled control: a member has exactly one option, and
              // showing a greyed "Everyone" would advertise an action the
              // server answers 403 to.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.gray100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.settingsMacroFormMemberNote,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              textCapitalization: TextCapitalization.sentences,
              minLines: 5,
              maxLines: 12,
              decoration: InputDecoration(
                labelText: l10n.settingsMacroFormBodyLabel,
                helperText: l10n.settingsMacroFormBodyHelper,
                helperMaxLines: 2,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.placeholders.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.settingsMacroFormTapToInsert,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final placeholder in widget.placeholders)
                    Tooltip(
                      message: placeholder.resolves,
                      child: ActionChip(
                        label: Text(placeholder.token),
                        onPressed: () => _insert(placeholder.token),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text(
              l10n.settingsMacroFormWhenSent,
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _status,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.settingsMacroFormSetStatus,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(l10n.settingsMacroFormNoChange),
                ),
                for (final s in macroStatuses)
                  DropdownMenuItem(value: s, child: Text(_statusName(s))),
              ],
              onChanged: (v) => setState(() => _status = v ?? ''),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _priority,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.settingsMacroFormSetPriority,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(l10n.settingsMacroFormNoChange),
                ),
                for (final p in macroPriorities)
                  DropdownMenuItem(value: p, child: Text(_priorityName(p))),
              ],
              onChanged: (v) => setState(() => _priority = v ?? ''),
            ),
            const SizedBox(height: 12),
            _PickerField(
              label: l10n.settingsMacroFormAssignTo,
              hint: l10n.settingsMacroFormAssignHint,
              values: [for (final a in _assignees) a.label],
              onTap: _pickPeople,
            ),
            const SizedBox(height: 12),
            _PickerField(
              label: l10n.settingsMacroFormAddTags,
              hint: l10n.settingsMacroFormTagsHint,
              values: [for (final t in _tags) t.label],
              onTap: _pickTags,
            ),
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
                            ? l10n.settingsMacroFormSaveReply
                            : l10n.settingsMacroFormSaveChanges,
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

/// A tappable field showing what is picked, opening a multi-select sheet.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.hint,
    required this.values,
    required this.onTap,
  });

  final String label;
  final String hint;
  final List<String> values;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(LucideIcons.chevronDown, size: 18),
        ),
        child: Text(
          values.isEmpty
              ? context.l10n.settingsMacroFormNoChange
              : values.join(', '),
          style: AppTypography.body.copyWith(
            color: values.isEmpty
                ? AppColors.textTertiary
                : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
