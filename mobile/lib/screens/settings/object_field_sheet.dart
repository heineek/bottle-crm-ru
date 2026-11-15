import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme.dart';
import '../../l10n/l10n.dart';
import '../../data/models/custom_field_definition.dart';
import '../../data/models/custom_object.dart';
import '../../providers/custom_objects_provider.dart';
import 'options_editor.dart';

Map<String, String> get objectFieldTypeLabels => {
  'text': appL10n.settingsObjectFieldTypeText,
  'textarea': appL10n.settingsObjectFieldTypeTextarea,
  'number': appL10n.settingsObjectFieldTypeNumber,
  'dropdown': appL10n.settingsObjectFieldTypeDropdown,
  'date': appL10n.settingsObjectFieldTypeDate,
  'checkbox': appL10n.settingsObjectFieldTypeCheckbox,
  'link': appL10n.settingsObjectFieldTypeLink,
};

String linkTargetLabel(List<LinkTarget> targets, String? key) {
  for (final t in targets) {
    if (t.key == key) return t.labelPlural;
  }
  return key ?? '';
}

/// Adds or edits one field. [onSubmit] performs the write and answers an error
/// message, or null when it worked; the sheet stays open on an error so the
/// admin does not lose what they typed.
Future<void> showObjectFieldSheet(
  BuildContext context, {
  ObjectField? existing,
  required List<LinkTarget> linkTargets,
  required Future<String?> Function(Map<String, dynamic> body) onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => ObjectFieldSheet(
      existing: existing,
      linkTargets: linkTargets,
      onSubmit: onSubmit,
    ),
  );
}

class ObjectFieldSheet extends StatefulWidget {
  const ObjectFieldSheet({
    super.key,
    this.existing,
    required this.linkTargets,
    required this.onSubmit,
  });

  final ObjectField? existing;
  final List<LinkTarget> linkTargets;
  final Future<String?> Function(Map<String, dynamic> body) onSubmit;

  @override
  State<ObjectFieldSheet> createState() => _ObjectFieldSheetState();
}

class _ObjectFieldSheetState extends State<ObjectFieldSheet> {
  static final _keyPattern = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  late final TextEditingController _label;
  late final TextEditingController _key;
  late final TextEditingController _order;
  late String _fieldType;
  late bool _isRequired;
  late bool _many;
  String? _target;
  late List<OptionDraft> _options;
  bool _keyTouched = false;
  bool _saving = false;
  String? _error;

  bool get _creating => widget.existing == null;
  bool get _isLink => _fieldType == 'link';

  @override
  void initState() {
    super.initState();
    final f = widget.existing;
    _label = TextEditingController(text: f?.label ?? '');
    _key = TextEditingController(text: f?.key ?? '');
    _order = TextEditingController(text: f == null ? '' : '${f.displayOrder}');
    _fieldType = f?.fieldType ?? 'text';
    _isRequired = f?.isRequired ?? false;
    _many = f?.many ?? false;
    _target = widget.linkTargets.isEmpty ? null : widget.linkTargets.first.key;
    _options = [
      for (final o in f?.options ?? const <CustomFieldOption>[])
        OptionDraft(value: o.value, label: o.label),
    ];
  }

  @override
  void dispose() {
    _label.dispose();
    _key.dispose();
    _order.dispose();
    for (final o in _options) {
      o.controller.dispose();
    }
    super.dispose();
  }

  void _onLabelChanged(String value) {
    if (!_creating || _keyTouched) return;
    final suggestion = suggestObjectKey(value, 64);
    _key.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  Future<void> _submit() async {
    final label = _label.text.trim();
    final key = _key.text.trim();
    String? problem;
    if (label.isEmpty) {
      problem = context.l10n.settingsObjectFieldLabelRequired;
    } else if (_creating && !_keyPattern.hasMatch(key)) {
      problem = context.l10n.settingsObjectFieldKeyInvalid;
    } else if (_creating && _isLink && _target == null) {
      problem = context.l10n.settingsObjectFieldTargetRequired;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final body = fieldWriteBody(
      creating: _creating,
      label: label,
      fieldType: _fieldType,
      key: key,
      target: _target ?? '',
      many: _many,
      isRequired: _isRequired,
      displayOrder: int.tryParse(_order.text.trim()),
      options: [
        for (final o in _options)
          CustomFieldOption(value: o.value, label: o.controller.text),
      ],
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSubmit(body);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
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
              _creating
                  ? l10n.settingsObjectFieldNewTitle
                  : l10n.settingsObjectsEditTitle(existing!.label),
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              onChanged: _onLabelChanged,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 128,
              decoration: InputDecoration(
                labelText: l10n.settingsObjectFieldLabel,
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            if (_creating) ...[
              TextField(
                controller: _key,
                onChanged: (_) => _keyTouched = true,
                maxLength: 64,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.settingsObjectsKey,
                  helperText: l10n.settingsObjectFieldKeyHelper,
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _fieldType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.settingsObjectFieldType,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final e in objectFieldTypeLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _fieldType = v ?? _fieldType),
              ),
            ] else
              _Fixed(
                label: l10n.settingsObjectFieldKeyAndType,
                value:
                    '${existing!.key}, '
                    '${objectFieldTypeLabels[existing.fieldType] ?? existing.fieldType}',
              ),
            if (_isLink) ...[
              const SizedBox(height: 12),
              if (_creating) ...[
                DropdownButtonFormField<String>(
                  initialValue: _target,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.settingsObjectFieldLinksTo,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final t in widget.linkTargets)
                      DropdownMenuItem(
                        value: t.key,
                        child: Text(t.labelPlural),
                      ),
                  ],
                  onChanged: (v) => setState(() => _target = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<bool>(
                  initialValue: _many,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.settingsObjectFieldHowMany,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: false,
                      child: Text(l10n.settingsObjectFieldOneRecord),
                    ),
                    DropdownMenuItem(
                      value: true,
                      child: Text(l10n.settingsObjectFieldSeveralRecords),
                    ),
                  ],
                  onChanged: (v) => setState(() => _many = v ?? _many),
                ),
              ] else
                _Fixed(
                  label: l10n.settingsObjectFieldLinksTo,
                  value: existing!.many == true
                      ? l10n.settingsObjectFieldLinkSeveralRecords(
                          linkTargetLabel(widget.linkTargets, existing.target),
                        )
                      : l10n.settingsObjectFieldLinkOneRecord(
                          linkTargetLabel(widget.linkTargets, existing.target),
                        ),
                ),
            ],
            if (_fieldType == 'dropdown') ...[
              const SizedBox(height: 16),
              OptionsEditor(
                options: _options,
                onAdd: () => setState(
                  () => _options.add(OptionDraft(value: '', label: '')),
                ),
                onRemove: (i) =>
                    setState(() => _options.removeAt(i).controller.dispose()),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _order,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.settingsObjectFieldOrder,
                border: OutlineInputBorder(),
              ),
            ),
            if (!_isLink)
              Material(
                color: Colors.transparent,
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isRequired,
                  onChanged: (v) => setState(() => _isRequired = v),
                  title: Text(l10n.settingsObjectsRequired),
                  subtitle: Text(l10n.settingsObjectFieldRequiredHint),
                ),
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
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: Text(
                        _creating
                            ? l10n.settingsObjectFieldAdd
                            : l10n.settingsObjectFieldSave,
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

class _Fixed extends StatelessWidget {
  const _Fixed({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.body),
        const SizedBox(height: 2),
        Text(
          context.l10n.settingsObjectsFixed,
          style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
        ),
      ],
    );
  }
}
