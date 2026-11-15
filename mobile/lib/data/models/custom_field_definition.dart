import '../../l10n/l10n.dart';

/// Per-org schema row describing a single custom field on an entity.
///
/// Mirrors `common.models.CustomFieldDefinition` on the backend. The form
/// renderer uses `fieldType` to pick the input widget and `options` for
/// dropdown choices. Values live on the entity itself under `custom_fields`.
class CustomFieldDefinition {
  final String id;
  final String targetModel;
  final String key;
  final String label;
  final CustomFieldType fieldType;
  final List<CustomFieldOption> options;
  final bool isRequired;

  /// Whether the field is offered as a list filter. Read by the settings
  /// screen only; the form renderer has no use for it.
  final bool isFilterable;

  final int displayOrder;
  final bool isActive;

  /// How many records of [targetModel] predate this field and carry no value
  /// for it. Computed server-side and only present when the request did not
  /// pass `include_counts=false`, so it is 0 on the form-rendering path.
  ///
  /// This is the number the settings screen exists to show: marking a field
  /// required binds writes from that moment on and backfills nothing, so
  /// "Required" beside a non-zero count is a promise the stored data does not
  /// keep.
  final int recordsMissingValue;

  const CustomFieldDefinition({
    required this.id,
    required this.targetModel,
    required this.key,
    required this.label,
    required this.fieldType,
    this.options = const [],
    this.isRequired = false,
    this.isFilterable = false,
    this.displayOrder = 0,
    this.isActive = true,
    this.recordsMissingValue = 0,
  });

  factory CustomFieldDefinition.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    final List<CustomFieldOption> parsedOptions = [];
    if (rawOptions is List) {
      for (final o in rawOptions) {
        if (o is Map<String, dynamic>) {
          final value = o['value']?.toString() ?? '';
          if (value.isEmpty) continue;
          parsedOptions.add(
            CustomFieldOption(
              value: value,
              label: o['label']?.toString() ?? value,
            ),
          );
        }
      }
    }
    return CustomFieldDefinition(
      id: json['id']?.toString() ?? '',
      targetModel: json['target_model'] as String? ?? '',
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      fieldType: CustomFieldType.fromString(json['field_type'] as String?),
      options: parsedOptions,
      isRequired: json['is_required'] as bool? ?? false,
      isFilterable: json['is_filterable'] as bool? ?? false,
      displayOrder: json['display_order'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      recordsMissingValue: json['records_missing_value'] as int? ?? 0,
    );
  }
}

class CustomFieldOption {
  final String value;
  final String label;
  const CustomFieldOption({required this.value, required this.label});
}

enum CustomFieldType {
  text('text'),
  textarea('textarea'),
  number('number'),
  dropdown('dropdown'),
  date('date'),
  checkbox('checkbox');

  final String value;

  const CustomFieldType(this.value);

  /// Matches `FIELD_TYPE_LABEL` in `frontend/src/lib/v2/enums.js`, so the two
  /// clients name the same type the same way.
  String get label => switch (this) {
    text => appL10n.appCustomFieldTypeText,
    textarea => appL10n.appCustomFieldTypeTextarea,
    number => appL10n.appCustomFieldTypeNumber,
    dropdown => appL10n.appCustomFieldTypeDropdown,
    date => appL10n.appCustomFieldTypeDate,
    checkbox => appL10n.appCustomFieldTypeCheckbox,
  };

  static CustomFieldType fromString(String? value) {
    return CustomFieldType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => CustomFieldType.text,
    );
  }
}

/// The record types the backend will attach a custom field to, with the names
/// this app already uses for them elsewhere (`Case` is a ticket, `Opportunity`
/// is a deal).
///
/// Mirrors the custom-field targets in `backend/common/object_registry.py` and
/// `TARGET_MODEL_LABEL` in `frontend/src/lib/v2/enums.js`.
/// `CustomFieldDefinitionSerializer` rejects anything outside this set, so
/// offering a wider list would only produce a 400.
Map<String, String> get customFieldTargets {
  final l10n = appL10n;
  return {
    'Account': l10n.appTargetAccounts,
    'Case': l10n.appTargetTickets,
    'Contact': l10n.appTargetContacts,
    'Estimate': l10n.appTargetEstimates,
    'Invoice': l10n.appTargetInvoices,
    'Lead': l10n.appTargetLeads,
    'Opportunity': l10n.appTargetDeals,
    'RecurringInvoice': l10n.appTargetRecurringInvoices,
    'Task': l10n.appTargetTasks,
  };
}

/// The module that serves each target; Account and Contact are always on.
/// Twin of `TARGET_MODULES` in `frontend/src/lib/v2/modules.js`.
const Map<String, String> customFieldTargetModules = {
  'Lead': 'leads',
  'Opportunity': 'deals',
  'Case': 'tickets',
  'Task': 'tasks',
  'Invoice': 'invoices',
  'Estimate': 'invoices',
  'RecurringInvoice': 'invoices',
};

String customFieldTargetLabel(String targetModel) =>
    customFieldTargets[targetModel] ?? targetModel;

/// Whether [key] is a key the server will accept.
///
/// `CustomFieldDefinitionSerializer.validate_key` requires
/// `[a-z][a-z0-9_]*`. Hyphens are the trap: they read as natural in a slug and
/// are refused, so the form says so rather than letting the save fail.
bool isValidCustomFieldKey(String key) =>
    RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(key);

/// A starting key derived from the label, for the create form only.
///
/// Typing a lowercase underscored slug on a phone keyboard is several mode
/// switches, so the field is pre-filled and still editable. It is a default,
/// not a rule: whatever is in the box at submit time is what gets sent, and
/// [isValidCustomFieldKey] is what decides whether it may be.
///
/// Returns `''` when nothing usable survives (a label of only punctuation, or
/// one starting with a digit, which the server's leading-letter rule refuses),
/// leaving the admin to type one.
String suggestCustomFieldKey(String label) {
  final slug = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isEmpty) return '';
  return isValidCustomFieldKey(slug) ? slug : '';
}

/// "Very High" to "very-high", for a NEW dropdown option only.
///
/// An existing option's value is stored on every record that uses it, so a
/// relabel must leave the value untouched. This mirrors `slugifyOptionValue`
/// in `frontend/src/lib/server/v2/custom-fields.js`, hyphens included: option
/// values are free-form on the server and only the field `key` is slug-checked.
String slugifyOptionValue(String label) => label
    .toLowerCase()
    .trim()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// What a custom-field form has to say before it can be submitted, or `null`.
///
/// Extracted from the form so it is testable without driving the widget, and
/// so the create and edit paths cannot drift: both call this.
///
/// [isCreate] decides whether [key] and [targetModel] are checked at all. They
/// are frozen after creation (`CustomFieldDefinitionSerializer.validate`), so
/// the edit form does not offer them and has nothing to validate.
String? validateCustomFieldDraft({
  required bool isCreate,
  required String label,
  required String key,
  required String targetModel,
  required CustomFieldType fieldType,
  required List<CustomFieldOption> options,
}) {
  final l10n = appL10n;
  if (label.trim().isEmpty) return l10n.appCustomFieldValidateLabel;
  if (isCreate) {
    if (key.trim().isEmpty) return l10n.appCustomFieldValidateKey;
    if (!isValidCustomFieldKey(key.trim())) {
      return l10n.appCustomFieldValidateKeyFormat;
    }
    if (!customFieldTargets.containsKey(targetModel)) {
      return l10n.appCustomFieldValidateTarget;
    }
  }
  if (fieldType == CustomFieldType.dropdown) {
    final rows = options.where((o) => o.label.trim().isNotEmpty).toList();
    if (rows.isEmpty) return l10n.appCustomFieldValidateNoOptions;
    final seen = <String>{};
    for (final row in rows) {
      final value = row.value.isNotEmpty
          ? row.value
          : slugifyOptionValue(row.label);
      if (value.isEmpty) {
        return l10n.appCustomFieldValidateOptionName;
      }
      if (!seen.add(value)) {
        return l10n.appCustomFieldValidateOptionDuplicate(value);
      }
    }
  }
  return null;
}

/// The body for `POST /custom-fields/`.
///
/// `org` is set from the JWT server-side and `records_missing_value` is
/// computed, so neither appears here. `is_active` is left off too: the model
/// defaults it to true and a new field is always on.
///
/// `options` rides only on a dropdown. `validate_definition_options` refuses a
/// non-empty options list on any other type, so sending one turns a valid text
/// field into a 400.
Map<String, dynamic> customFieldCreatePayload({
  required String targetModel,
  required String key,
  required String label,
  required CustomFieldType fieldType,
  required bool isRequired,
  required bool isFilterable,
  required int displayOrder,
  required List<CustomFieldOption> options,
}) {
  final body = <String, dynamic>{
    'target_model': targetModel,
    'key': key.trim(),
    'label': label.trim(),
    'field_type': fieldType.value,
    'is_required': isRequired,
    'is_filterable': isFilterable,
    'display_order': displayOrder,
  };
  if (fieldType == CustomFieldType.dropdown) {
    body['options'] = _optionRows(options);
  }
  return body;
}

/// The body for `PUT /custom-fields/<id>/`.
///
/// `key`, `target_model` and `field_type` are absent on purpose.
/// `CustomFieldDefinitionSerializer.validate` refuses a change to any of the
/// three with a 400, and it is right to: values live in each record's
/// `custom_fields` JSON keyed by `key`, so changing the key orphans them,
/// changing the target leaves them on the old entity, and changing the type
/// reinterprets values written under the old one.
Map<String, dynamic> customFieldUpdatePayload({
  required String label,
  required CustomFieldType fieldType,
  required bool isRequired,
  required bool isFilterable,
  required int displayOrder,
  required List<CustomFieldOption> options,
}) {
  final body = <String, dynamic>{
    'label': label.trim(),
    'is_required': isRequired,
    'is_filterable': isFilterable,
    'display_order': displayOrder,
  };
  if (fieldType == CustomFieldType.dropdown) {
    body['options'] = _optionRows(options);
  }
  return body;
}

/// The body for turning a field back on.
///
/// Only `is_active`, and that is the whole point. Reusing the edit payload
/// would send `label` too, and a reactivate control has no label to send: the
/// field would come back with its name blanked. The web learned this the same
/// way, which is why its `activate` action calls `updateCustomField` directly
/// instead of going through its form reader.
Map<String, dynamic> customFieldActivatePayload() => {'is_active': true};

List<Map<String, String>> _optionRows(List<CustomFieldOption> options) {
  final rows = <Map<String, String>>[];
  for (final option in options) {
    final label = option.label.trim();
    if (label.isEmpty) continue;
    final value = option.value.isNotEmpty
        ? option.value
        : slugifyOptionValue(label);
    if (value.isEmpty) continue;
    rows.add({'value': value, 'label': label});
  }
  return rows;
}
