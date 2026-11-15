import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../data/models/automation.dart';
import '../../../l10n/l10n.dart';
import '../../../services/automation_text.dart';
import 'rule_sheet.dart';
import 'rule_value_field.dart';

String _typeLabel(AppLocalizations l10n, String type) => switch (type) {
  'set_field' => l10n.settingsAutomationActionTypeSetField,
  'assign' => l10n.settingsAutomationActionTypeAssign,
  'create_task' => l10n.settingsAutomationActionTypeCreateTask,
  'notify' => l10n.settingsAutomationActionTypeNotify,
  'webhook' => l10n.settingsAutomationActionTypeWebhook,
  _ => type,
};

/// The values the API stores; only their labels are translated.
const _priorities = ['Low', 'Medium', 'High'];

String _priorityLabel(AppLocalizations l10n, String p) => switch (p) {
  'Low' => l10n.settingsAutomationActionPriorityLow,
  'Medium' => l10n.settingsAutomationActionPriorityMedium,
  'High' => l10n.settingsAutomationActionPriorityHigh,
  _ => p,
};

/// The "For" choice that names the record's parent, or null when the object
/// has no such choice (deal, ticket and task only).
String? taskParentLabel(AutomationObject? object) {
  for (final r in recipientsFor(object)) {
    if (r.value == 'parent_assignees') return r.label;
  }
  return null;
}

/// Adds or edits one action. Returns it, or null when cancelled.
Future<ActionDraft?> showActionSheet(
  BuildContext context, {
  required AutomationCatalogue catalogue,
  required AutomationObject object,
  ActionDraft? draft,
}) => showRuleSheet<ActionDraft>(
  context,
  (controller) => _ActionSheet(
    catalogue: catalogue,
    object: object,
    draft: draft,
    controller: controller,
  ),
);

class _ActionSheet extends StatefulWidget {
  const _ActionSheet({
    required this.catalogue,
    required this.object,
    required this.draft,
    required this.controller,
  });

  final AutomationCatalogue catalogue;
  final AutomationObject object;
  final ActionDraft? draft;
  final ScrollController controller;

  @override
  State<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends State<_ActionSheet> {
  late ActionDraft _a;
  late bool _clear;

  /// What the value was before "Clear it instead" was ticked, so unticking
  /// brings it back.
  Object? _previous;

  Map<String, dynamic> get _v => _a.values;

  @override
  void initState() {
    super.initState();
    final types = actionTypes(widget.catalogue, widget.object);
    _a =
        widget.draft?.copy() ??
        blankAction(
          types.contains('create_task') ? 'create_task' : types.first,
        );
    _clear =
        _a.type == 'set_field' &&
        _v['value'] == null &&
        (_v['field'] ?? '').toString().isNotEmpty;
  }

  List<RuleTarget> get _targets => targetsFor(widget.catalogue, widget.object);

  RuleTarget? get _target {
    for (final t in _targets) {
      if (t.value == _v['target']) return t;
    }
    return null;
  }

  RuleField? get _setField =>
      fieldOf(_target?.object, (_v['field'] ?? '').toString());

  bool _empty(Object? v) => v == null || v == '' || (v is List && v.isEmpty);

  int _count(Object? v) => v is List ? v.length : 0;

  bool get _valid {
    switch (_a.type) {
      case 'set_field':
        if ((_v['field'] ?? '').toString().isEmpty || _target == null) {
          return false;
        }
        return _clear || !_empty(_v['value']);
      case 'assign':
        final n = _count(_v['people']);
        return _v['mode'] == 'rotate' ? n >= 2 && n <= 20 : n == 1;
      case 'create_task':
        final title = (_v['title'] ?? '').toString();
        final days = _v['due_in_days'];
        final daysOk =
            days == null || (days is int && days >= 0 && days <= 365);
        final personOk = _v['assign_to'] != 'person' || !_empty(_v['person']);
        return title.trim().isNotEmpty &&
            title.length <= 200 &&
            daysOk &&
            personOk;
      case 'notify':
        final message = (_v['message'] ?? '').toString();
        return (_count(_v['to']) + _count(_v['people']) > 0) &&
            message.trim().isNotEmpty &&
            message.length <= 500;
      case 'webhook':
        return !_empty(_v['endpoint']);
    }
    return false;
  }

  void _done() {
    final out = _a.copy();
    if (out.type == 'create_task' && out.values['assign_to'] != 'person') {
      out.values['person'] = null;
    }
    Navigator.of(context).pop(out);
  }

  void _pickType(String type) {
    if (type == _a.type) return;
    setState(() {
      _a = blankAction(type);
      _clear = false;
    });
  }

  Widget _select(
    String label,
    String? value,
    List<RuleOption> options,
    ValueChanged<String> onChanged, {
    Key? key,
  }) => DropdownButtonFormField<String>(
    key: key,
    initialValue: value == null || value.isEmpty ? null : value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final o in options)
        DropdownMenuItem(
          value: o.value,
          child: Text(optionLabel(o), overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );

  List<RuleOption> get _people => withStored([
    for (final p in widget.catalogue.people)
      RuleOption(value: p.id, label: p.name.isEmpty ? p.id : p.name),
  ], null);

  Widget _personSelect(String label, String? value, ValueChanged<String> on) {
    final options = withStored(_people, value, person: true);
    return _select(label, value, options, on, key: ValueKey('$label-$value'));
  }

  Widget _caption(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: AppTypography.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
    ),
  );

  Widget _peopleField(String label, Object? value, ValueChanged<Object?> on) =>
      RuleValueField(
        key: ValueKey('people-$label'),
        field: RuleField(key: 'people', label: label, type: 'people'),
        kind: ValueKind.people.name,
        value: value,
        onChanged: on,
        people: widget.catalogue.people,
      );

  List<Widget> _setFieldBody() {
    final target = _target;
    final targetOptions = withStored(
      [for (final t in _targets) RuleOption(value: t.value, label: t.label)],
      _v['target'],
      label: (_) => context.l10n.settingsAutomationActionRemovedLink,
    );
    final fieldOptions = withStored([
      for (final f in target?.object.fields ?? const <RuleField>[])
        if (f.settable) RuleOption(value: f.key, label: f.label),
    ], _v['field']);
    final field = _setField;
    final stored = (_v['field'] ?? '').toString();
    return [
      _select(
        context.l10n.settingsAutomationActionOn,
        _v['target']?.toString(),
        targetOptions,
        (t) {
          if (t == _v['target']) return;
          setState(() {
            _v['target'] = t;
            _v['field'] = '';
            _v['value'] = null;
            _clear = false;
            _previous = null;
          });
        },
      ),
      const SizedBox(height: 12),
      _select(context.l10n.settingsAutomationActionSet, stored, fieldOptions, (
        f,
      ) {
        if (f == stored) return;
        setState(() {
          _v['field'] = f;
          _v['value'] = null;
          _clear = false;
          _previous = null;
        });
      }, key: ValueKey('set-${_v['target']}')),
      if (stored.isNotEmpty && field == null)
        _note(context.l10n.settingsAutomationFieldGone)
      else if (stored.isNotEmpty && field != null) ...[
        const SizedBox(height: 4),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(context.l10n.settingsAutomationActionClearInstead),
          value: _clear,
          onChanged: (on) => setState(() {
            _clear = on == true;
            if (_clear) {
              _previous = _v['value'];
              _v['value'] = null;
            } else {
              _v['value'] = _previous;
            }
          }),
        ),
        if (!_clear) ...[
          const SizedBox(height: 8),
          RuleValueField(
            key: ValueKey('value-${_v['target']}-$stored'),
            field: field,
            kind: valueKind(field, 'eq').name,
            value: _v['value'],
            settableOnly: true,
            onChanged: (v) => setState(() => _v['value'] = v),
            people: widget.catalogue.people,
          ),
        ],
      ],
    ];
  }

  List<Widget> _assignBody() {
    final rotate = _v['mode'] == 'rotate';
    final people = _v['people'] is List ? _v['people'] as List : const [];
    final l10n = context.l10n;
    final modes = withStored([
      RuleOption(
        value: 'replace',
        label: l10n.settingsAutomationActionOnePerson,
      ),
      RuleOption(value: 'rotate', label: l10n.settingsAutomationActionInTurn),
    ], _v['mode']);
    return [
      _select(l10n.settingsAutomationActionWho, _v['mode']?.toString(), modes, (
        m,
      ) {
        if (m == _v['mode']) return;
        setState(() {
          _v['mode'] = m;
          if (m == 'replace' && people.length > 1) {
            _v['people'] = [people.first];
          }
        });
      }),
      const SizedBox(height: 12),
      if (rotate) ...[
        _caption(l10n.settingsAutomationActionPeople),
        _peopleField(
          l10n.settingsAutomationActionPeople,
          _v['people'],
          (v) => setState(() => _v['people'] = v),
        ),
        _note(l10n.settingsAutomationActionRotateHint),
      ] else ...[
        if (people.length > 1)
          _note(l10n.settingsAutomationActionOnePersonHint),
        _personSelect(
          l10n.settingsAutomationActionPerson,
          people.length == 1 ? people.first.toString() : null,
          (id) => setState(() => _v['people'] = [id]),
        ),
      ],
      _note(l10n.settingsAutomationActionReplacesAssignees),
    ];
  }

  List<Widget> _taskBody() {
    final l10n = context.l10n;
    final parent = taskParentLabel(widget.object);
    final forOptions = withStored(
      [
        RuleOption(
          value: 'record',
          label: l10n.settingsAutomationActionForAssignees,
        ),
        if (parent != null) RuleOption(value: 'parent', label: parent),
        RuleOption(
          value: 'owner',
          label: l10n.settingsAutomationActionForOwner,
        ),
        RuleOption(
          value: 'person',
          label: l10n.settingsAutomationActionForPerson,
        ),
      ],
      _v['assign_to'],
      label: recipientLabel,
    );
    final days = _v['due_in_days'];
    return [
      TextFormField(
        initialValue: (_v['title'] ?? '').toString(),
        maxLength: 200,
        decoration: InputDecoration(
          labelText: l10n.settingsAutomationActionTitle,
          helperText: l10n.settingsAutomationActionNameHint('{name}'),
          border: OutlineInputBorder(),
        ),
        onChanged: (t) => setState(() => _v['title'] = t),
      ),
      const SizedBox(height: 12),
      TextFormField(
        initialValue: days?.toString() ?? '',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: l10n.settingsAutomationActionDueIn,
          suffixText: l10n.settingsAutomationActionDueSuffix,
          helperText: l10n.settingsAutomationActionDueHelper,
          border: OutlineInputBorder(),
        ),
        onChanged: (t) => setState(() {
          final text = t.trim();
          _v['due_in_days'] = text.isEmpty
              ? null
              : (int.tryParse(text) ?? text);
        }),
      ),
      const SizedBox(height: 12),
      _select(
        l10n.commonPriority,
        _v['priority']?.toString(),
        withStored([
          for (final p in _priorities)
            RuleOption(value: p, label: _priorityLabel(l10n, p)),
        ], _v['priority']),
        (p) => setState(() => _v['priority'] = p),
      ),
      const SizedBox(height: 12),
      _select(
        l10n.settingsAutomationActionFor,
        _v['assign_to']?.toString(),
        forOptions,
        (w) => setState(() {
          _v['assign_to'] = w;
          if (w != 'person') _v['person'] = null;
        }),
      ),
      if (_v['assign_to'] == 'person') ...[
        const SizedBox(height: 12),
        _personSelect(
          l10n.settingsAutomationActionPerson,
          _v['person']?.toString(),
          (id) => setState(() => _v['person'] = id),
        ),
      ],
    ];
  }

  List<Widget> _notifyBody() {
    final to = _v['to'] is List ? [..._v['to'] as List] : <dynamic>[];
    final options = withStored(
      recipientsFor(widget.object),
      to,
      label: recipientLabel,
    );
    final l10n = context.l10n;
    return [
      _caption(l10n.settingsAutomationActionWho),
      for (final o in options)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(o.label),
          value: to.contains(o.value),
          onChanged: (on) => setState(() {
            _v['to'] = [
              for (final x in options)
                if (x.value == o.value ? on == true : to.contains(x.value))
                  x.value,
            ];
          }),
        ),
      const SizedBox(height: 8),
      _caption(l10n.settingsAutomationActionAndThesePeople),
      _peopleField(
        l10n.settingsAutomationActionAndThesePeople,
        _v['people'],
        (v) => setState(() => _v['people'] = v),
      ),
      const SizedBox(height: 12),
      TextFormField(
        initialValue: (_v['message'] ?? '').toString(),
        maxLength: 500,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          labelText: l10n.settingsAutomationActionMessage,
          helperText: l10n.settingsAutomationActionNameHint('{name}'),
          border: OutlineInputBorder(),
        ),
        onChanged: (t) => setState(() => _v['message'] = t),
      ),
      _note(l10n.settingsAutomationActionNotifyHint),
    ];
  }

  List<Widget> _webhookBody() => [
    _select(
      context.l10n.settingsAutomationActionEndpoint,
      _v['endpoint']?.toString(),
      withStored(
        [
          for (final e in widget.catalogue.endpoints)
            RuleOption(
              value: e.id,
              label: e.description.isEmpty ? e.id : e.description,
            ),
        ],
        _v['endpoint'],
        label: (_) => context.l10n.settingsAutomationActionEndpointGone,
      ),
      (id) => setState(() => _v['endpoint'] = id),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final types = [
      for (final o in withStored([
        for (final t in actionTypes(widget.catalogue, widget.object))
          RuleOption(value: t, label: _typeLabel(l10n, t)),
      ], _a.type))
        o.gone
            ? RuleOption(
                value: o.value,
                label: l10n.settingsAutomationNoLongerAvailable(
                  _typeLabel(l10n, o.value),
                ),
              )
            : o,
    ];
    final body = switch (_a.type) {
      'set_field' => _setFieldBody(),
      'assign' => _assignBody(),
      'create_task' => _taskBody(),
      'notify' => _notifyBody(),
      'webhook' => _webhookBody(),
      _ => <Widget>[_note(l10n.settingsAutomationActionGone)],
    };
    return RuleSheetFrame(
      title: widget.draft == null
          ? l10n.settingsAutomationAddAction
          : l10n.settingsAutomationActionEditTitle,
      controller: widget.controller,
      onDone: _valid ? _done : null,
      children: [
        _select(l10n.settingsAutomationActionLabel, _a.type, types, _pickType),
        const SizedBox(height: 12),
        KeyedSubtree(
          key: ValueKey('action-body-${_a.type}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: body,
          ),
        ),
      ],
    );
  }
}
