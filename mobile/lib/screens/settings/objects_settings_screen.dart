import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../l10n/l10n.dart';
import '../../data/models/custom_object.dart';
import '../../providers/auth_provider.dart';
import '../../providers/custom_objects_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/common/badge.dart';
import '../../widgets/common/buttons.dart';

/// Every provider the settings screens and the rest of the app read, so More,
/// the hub and the lists catch up after a write.
void refreshObjects(WidgetRef ref, [String? key]) {
  ref.invalidate(objectsSettingsProvider);
  if (key != null) ref.invalidate(objectSettingsProvider(key));
  ref.invalidate(customObjectsProvider);
}

/// Custom objects, mirroring `/settings/objects` on the web. Reading is open to
/// every member; creating needs an admin and the server's say-so.
class ObjectsSettingsScreen extends ConsumerWidget {
  const ObjectsSettingsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    String? created;
    await showObjectFormSheet(
      context,
      onSubmit: (body) async {
        final response = await ref
            .read(customObjectsApiProvider)
            .createObject(body);
        if (!response.success) {
          return settingsWriteError(
            response,
            appL10n.settingsObjectsAddError,
            labels: objectFormLabels,
          );
        }
        created = body['key'] as String?;
        refreshObjects(ref);
        return null;
      },
    );
    if (created != null && context.mounted) {
      context.push(AppRoutes.settingsObject(created!));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(objectsSettingsProvider);
    final isAdmin = ref.watch(isOrgAdminProvider);
    final answer = async.value;
    final writesOn = answer?.hasCustomObjects == true;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsObjectsTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      floatingActionButton: isAdmin && writesOn
          ? AppFAB(
              icon: LucideIcons.plus,
              label: context.l10n.settingsObjectsNewObject,
              onPressed: () => _create(context, ref),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _Message(
          text: context.l10n.settingsObjectsLoadError,
          onRetry: () => ref.invalidate(objectsSettingsProvider),
        ),
        data: (answer) {
          if (answer == null) {
            return _Message(
              text: context.l10n.settingsObjectsLoadError,
              onRetry: () => ref.invalidate(objectsSettingsProvider),
            );
          }
          final objects = answer.objects;
          return RefreshIndicator(
            onRefresh: () => ref.refresh(objectsSettingsProvider.future),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (isAdmin && !writesOn)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      objectsTurnedOffNotice,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                if (objects.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      context.l10n.settingsObjectsEmpty,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final o in objects) _ObjectRow(summary: o),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ObjectRow extends StatelessWidget {
  const _ObjectRow({required this.summary});

  final ObjectSummary summary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => context.push(AppRoutes.settingsObject(summary.key)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.labelPlural,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: summary.isActive
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      summary.key,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (!summary.isActive)
                StatusBadge(
                  label: context.l10n.settingsObjectsArchived,
                  color: AppColors.gray500,
                ),
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: AppTypography.body, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.settingsObjectsTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds or edits an object. [onSubmit] does the write and answers an error
/// message, or null on success; the sheet stays open on an error.
Future<void> showObjectFormSheet(
  BuildContext context, {
  ObjectSummary? existing,
  required Future<String?> Function(Map<String, dynamic> body) onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _ObjectFormSheet(existing: existing, onSubmit: onSubmit),
  );
}

class _ObjectFormSheet extends StatefulWidget {
  const _ObjectFormSheet({this.existing, required this.onSubmit});

  final ObjectSummary? existing;
  final Future<String?> Function(Map<String, dynamic> body) onSubmit;

  @override
  State<_ObjectFormSheet> createState() => _ObjectFormSheetState();
}

class _ObjectFormSheetState extends State<_ObjectFormSheet> {
  static final _keyPattern = RegExp(r'^[a-z][a-z0-9_]{1,27}$');

  late final TextEditingController _label;
  late final TextEditingController _plural;
  late final TextEditingController _key;
  late final TextEditingController _nameLabel;
  late final TextEditingController _description;
  late String _access;
  bool _keyTouched = false;
  bool _saving = false;
  String? _error;

  bool get _creating => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final o = widget.existing;
    _label = TextEditingController(text: o?.label ?? '');
    _plural = TextEditingController(text: o?.labelPlural ?? '');
    _key = TextEditingController(text: o?.key ?? '');
    _nameLabel = TextEditingController(text: o?.nameLabel ?? '');
    _description = TextEditingController(text: o?.description ?? '');
    _access = o?.recordAccess == 'everyone' ? 'everyone' : 'own';
  }

  @override
  void dispose() {
    _label.dispose();
    _plural.dispose();
    _key.dispose();
    _nameLabel.dispose();
    _description.dispose();
    super.dispose();
  }

  void _onLabelChanged(String value) {
    if (!_creating || _keyTouched) return;
    final suggestion = suggestObjectKey(value, 28);
    _key.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  Future<void> _submit() async {
    String? problem;
    if (_label.text.trim().isEmpty || _plural.text.trim().isEmpty) {
      problem = context.l10n.settingsObjectsFormNamesRequired;
    } else if (_creating && !_keyPattern.hasMatch(_key.text.trim())) {
      problem = context.l10n.settingsObjectsFormKeyInvalid;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSubmit(
      objectWriteBody(
        creating: _creating,
        label: _label.text,
        labelPlural: _plural.text,
        key: _key.text,
        nameLabel: _nameLabel.text,
        description: _description.text,
        recordAccess: _access,
      ),
    );
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
                  ? l10n.settingsObjectsNewObject
                  : l10n.settingsObjectsEditTitle(widget.existing!.label),
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              onChanged: _onLabelChanged,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 64,
              decoration: InputDecoration(
                labelText: l10n.settingsObjectsFormSingularLabel,
                hintText: l10n.settingsObjectsFormSingularHint,
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _plural,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 64,
              decoration: InputDecoration(
                labelText: l10n.settingsObjectsFormPluralLabel,
                hintText: l10n.settingsObjectsFormPluralHint,
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            if (_creating)
              TextField(
                controller: _key,
                onChanged: (_) => _keyTouched = true,
                maxLength: 28,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.settingsObjectsKey,
                  helperText: l10n.settingsObjectsFormKeyHelper,
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsObjectsKey,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(widget.existing!.key, style: AppTypography.body),
                  Text(
                    l10n.settingsObjectsFixed,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameLabel,
              maxLength: 64,
              decoration: InputDecoration(
                labelText: l10n.settingsObjectsFormNameLabel,
                hintText: l10n.settingsObjectsFormNameHint,
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.commonDescription,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _access,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.settingsObjectsAccessLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'own',
                  child: Text(l10n.settingsObjectsAccessOwn),
                ),
                DropdownMenuItem(
                  value: 'everyone',
                  child: Text(l10n.settingsObjectsAccessEveryone),
                ),
              ],
              onChanged: (v) => setState(() => _access = v ?? _access),
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
                            ? l10n.settingsObjectsFormAdd
                            : l10n.settingsObjectsFormSave,
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
