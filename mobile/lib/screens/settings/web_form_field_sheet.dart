import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../data/models/custom_field_definition.dart';
import '../../data/models/web_form.dart';
import '../../l10n/l10n.dart';

/// Add or edit one question on a web form.
///
/// Returns the row, or `null` if dismissed. Nothing is saved from here: the
/// caller holds the list and writes it back in one request, because the server
/// assigns `order` from list position and a per-row save would have to decide
/// what position meant mid-edit.
///
/// [target] is the form's (lead or ticket), and decides which built-in fields
/// are offered: Lead columns on a lead form, ticket fields on a ticket form.
/// [customFields] must already be the definitions for that target's model.
///
/// [builtinFieldsInUse] are the built-in fields other rows already claim. Two
/// rows writing to the same field is not a database error, it is a form that
/// asks for an email address twice and keeps whichever answer the serializer
/// read last. The picker greys those out rather than leaving someone to find
/// out.
Future<WebFormField?> showWebFormFieldSheet(
  BuildContext context, {
  WebFormField? existing,
  required String target,
  required List<CustomFieldDefinition> customFields,
  required Set<String> builtinFieldsInUse,
}) {
  return showModalBottomSheet<WebFormField>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _WebFormFieldSheet(
      existing: existing,
      target: target,
      customFields: customFields,
      builtinFieldsInUse: builtinFieldsInUse,
    ),
  );
}

class _WebFormFieldSheet extends StatefulWidget {
  const _WebFormFieldSheet({
    this.existing,
    required this.target,
    required this.customFields,
    required this.builtinFieldsInUse,
  });

  final WebFormField? existing;
  final String target;
  final List<CustomFieldDefinition> customFields;
  final Set<String> builtinFieldsInUse;

  @override
  State<_WebFormFieldSheet> createState() => _WebFormFieldSheetState();
}

class _WebFormFieldSheetState extends State<_WebFormFieldSheet> {
  late final TextEditingController _label;
  late final TextEditingController _placeholder;
  late String _source;
  String _builtinField = '';
  String? _customField;
  late bool _isRequired;
  String? _error;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final field = widget.existing;
    _label = TextEditingController(text: field?.label ?? '');
    _placeholder = TextEditingController(text: field?.placeholder ?? '');
    // A new row starts as a built-in field either way. The source toggle is
    // only rendered when the org has defined custom fields for this target's
    // model, so with none defined this is the single reachable option rather
    // than a default.
    _source = field?.source ?? _builtinSource;
    _builtinField = field?.builtinField ?? '';
    _customField = field?.customField;
    _isRequired = field?.isRequired ?? false;
  }

  @override
  void dispose() {
    _label.dispose();
    _placeholder.dispose();
    super.dispose();
  }

  String get _builtinSource => WebFormField.builtinSourceFor(widget.target);
  bool get _isTicket => widget.target == WebForm.targetTicket;

  String _labelOf(String value) => builtinFieldLabel(widget.target, value);

  /// Whether this built-in field is already claimed by a different row.
  bool _taken(String value) =>
      widget.builtinFieldsInUse.contains(value) &&
      value != widget.existing?.builtinField;

  /// Follow the target with the label, unless somebody typed their own.
  /// Guessing is a convenience; overwriting a person's words is a correction,
  /// and this has no business making one.
  void _suggestLabel(String suggestion, String previousSuggestion) {
    final current = _label.text.trim();
    if (current.isEmpty || current == previousSuggestion) {
      _label.text = suggestion;
    }
  }

  void _submit() {
    final field = WebFormField(
      id: widget.existing?.id,
      source: _source,
      leadField: _source == WebFormField.sourceLead ? _builtinField : '',
      ticketField: _source == WebFormField.sourceTicket ? _builtinField : '',
      customField: _source == WebFormField.sourceCustom ? _customField : null,
      label: _label.text.trim(),
      placeholder: _placeholder.text.trim(),
      isRequired: _isRequired,
    );

    // The same two rules `WebFormFieldSerializer` enforces, and behind it the
    // `web_form_field_exactly_one_target` constraint. Checking here is so the
    // person is told before the round trip, not instead of it.
    if (!field.isComplete) {
      setState(() {
        _error = field.label.isEmpty
            ? context.l10n.settingsWebFormFieldLabelRequired
            : context.l10n.settingsWebFormFieldTargetRequired;
      });
      return;
    }
    Navigator.of(context).pop(field);
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomFields = widget.customFields.isNotEmpty;
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
                  ? l10n.settingsWebFormFieldAddTitle
                  : l10n.settingsWebFormFieldEditTitle,
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            if (hasCustomFields) ...[
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: _builtinSource,
                    label: Text(
                      _isTicket
                          ? l10n.settingsWebFormFieldTicketField
                          : l10n.settingsWebFormFieldLeadField,
                    ),
                  ),
                  ButtonSegment(
                    value: WebFormField.sourceCustom,
                    label: Text(l10n.settingsWebFormCustomField),
                  ),
                ],
                selected: {_source},
                onSelectionChanged: (selection) => setState(() {
                  _source = selection.first;
                  // Clearing both is what keeps the exactly-one-target rule
                  // true: carrying the old target across would leave a row
                  // naming a built-in field and a custom definition at once.
                  _builtinField = '';
                  _customField = null;
                }),
              ),
              const SizedBox(height: 12),
            ],

            if (_source == WebFormField.sourceCustom)
              DropdownButtonFormField<String>(
                initialValue: _customField,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.settingsWebFormCustomField,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final definition in widget.customFields)
                    DropdownMenuItem(
                      value: definition.id,
                      child: Text(definition.label),
                    ),
                ],
                onChanged: (value) => setState(() {
                  final previous = widget.customFields
                      .where((d) => d.id == _customField)
                      .map((d) => d.label)
                      .join();
                  _customField = value;
                  final picked = widget.customFields
                      .where((d) => d.id == value)
                      .map((d) => d.label)
                      .join();
                  if (picked.isNotEmpty) _suggestLabel(picked, previous);
                }),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _builtinField.isEmpty ? null : _builtinField,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.settingsWebFormFieldWritesInto,
                  border: const OutlineInputBorder(),
                  helperText: _isTicket
                      ? l10n.settingsWebFormFieldWritesIntoTicket
                      : l10n.settingsWebFormFieldWritesIntoLead,
                  helperMaxLines: 2,
                ),
                items: [
                  for (final field in builtinFieldsFor(widget.target))
                    DropdownMenuItem(
                      value: field.value,
                      enabled: !_taken(field.value),
                      child: Text(
                        _taken(field.value)
                            ? l10n.settingsWebFormFieldAlreadyOnForm(
                                field.label,
                              )
                            : field.label,
                        style: _taken(field.value)
                            ? AppTypography.body.copyWith(
                                color: AppColors.textTertiary,
                              )
                            : null,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  final previous = _labelOf(_builtinField);
                  _builtinField = value ?? '';
                  _suggestLabel(_labelOf(_builtinField), previous);
                }),
              ),

            const SizedBox(height: 12),
            TextField(
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 255,
              decoration: InputDecoration(
                labelText: l10n.settingsWebFormFieldLabel,
                helperText: l10n.settingsWebFormFieldLabelHelper,
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _placeholder,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 255,
              decoration: InputDecoration(
                labelText: l10n.settingsWebFormFieldPlaceholder,
                helperText: l10n.settingsWebFormFieldPlaceholderHelper,
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile.adaptive(
              value: _isRequired,
              onChanged: (value) => setState(() => _isRequired = value),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.settingsWebFormFieldRequired),
              subtitle: Text(l10n.settingsWebFormFieldRequiredSub),
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
                            ? l10n.settingsWebFormFieldAddButton
                            : l10n.settingsWebFormFieldSaveButton,
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
