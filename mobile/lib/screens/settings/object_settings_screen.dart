import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../l10n/l10n.dart';
import '../../data/models/custom_object.dart';
import '../../providers/auth_provider.dart';
import '../../providers/custom_objects_provider.dart';
import '../../widgets/common/badge.dart';
import 'object_field_sheet.dart';
import 'objects_settings_screen.dart';

/// One custom object: its details, access and fields. Members read; an admin
/// edits with the server's say-so, and can always archive, restore or delete
/// for good (the server refuses a delete while records or links remain).
class ObjectSettingsScreen extends ConsumerWidget {
  const ObjectSettingsScreen({super.key, required this.objectKey});

  final String objectKey;

  void _say(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger600),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    ObjectSummary summary,
    bool active,
  ) async {
    if (!active) {
      final ok = await _confirm(
        context,
        title: context.l10n.settingsObjectSettingsArchiveTitle(
          summary.labelPlural,
        ),
        body: context.l10n.settingsObjectSettingsArchiveBody,
        action: context.l10n.settingsObjectSettingsArchive,
      );
      if (!ok || !context.mounted) return;
    }
    final api = ref.read(customObjectsApiProvider);
    final response = active
        ? await api.updateObject(objectKey, {'is_active': true})
        : await api.deleteObject(objectKey);
    if (!context.mounted) return;
    if (response.success) refreshObjects(ref, objectKey);
    _say(
      context,
      response.success
          ? (active
                ? context.l10n.settingsObjectSettingsRestored
                : context.l10n.settingsObjectSettingsArchivedDone)
          : settingsWriteError(
              response,
              context.l10n.settingsObjectSettingsCouldNotDoThat,
              labels: objectFormLabels,
            ),
    );
  }

  Future<void> _destroy(
    BuildContext context,
    WidgetRef ref,
    ObjectSummary summary,
  ) async {
    final ok = await _confirm(
      context,
      title: context.l10n.settingsObjectSettingsDestroyTitle(
        summary.labelPlural,
      ),
      body: context.l10n.settingsObjectSettingsDestroyBody,
      action: context.l10n.settingsObjectSettingsDeleteForGood,
    );
    if (!ok || !context.mounted) return;
    final response = await ref
        .read(customObjectsApiProvider)
        .deleteObject(objectKey);
    if (!context.mounted) return;
    if (response.success) {
      refreshObjects(ref, objectKey);
      context.pop();
    } else {
      _say(
        context,
        settingsWriteError(
          response,
          context.l10n.settingsObjectSettingsDeleteError,
          labels: objectFormLabels,
        ),
      );
    }
  }

  Future<void> _editObject(
    BuildContext context,
    WidgetRef ref,
    ObjectSummary summary,
  ) {
    return showObjectFormSheet(
      context,
      existing: summary,
      onSubmit: (body) async {
        final response = await ref
            .read(customObjectsApiProvider)
            .updateObject(objectKey, body);
        if (!response.success) {
          return settingsWriteError(
            response,
            appL10n.settingsObjectSettingsSaveObjectError,
            labels: objectFormLabels,
          );
        }
        refreshObjects(ref, objectKey);
        return null;
      },
    );
  }

  Future<void> _chooseAccess(
    BuildContext context,
    WidgetRef ref,
    ObjectSummary summary,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(context.l10n.appObjectFormRecordAccess),
            ),
            for (final o in [
              ('everyone', context.l10n.settingsObjectsAccessEveryone),
              ('own', context.l10n.settingsObjectsAccessOwn),
            ])
              ListTile(
                minTileHeight: 48,
                title: Text(o.$2),
                trailing:
                    o.$1 ==
                        (summary.recordAccess == 'everyone'
                            ? 'everyone'
                            : 'own')
                    ? Icon(LucideIcons.check, color: AppColors.primary600)
                    : null,
                onTap: () => Navigator.of(sheet).pop(o.$1),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == summary.recordAccess || !context.mounted) {
      return;
    }
    final response = await ref.read(customObjectsApiProvider).updateObject(
      objectKey,
      {'record_access': picked},
    );
    if (!context.mounted) return;
    if (response.success) refreshObjects(ref, objectKey);
    _say(
      context,
      response.success
          ? context.l10n.settingsObjectSettingsSaved
          : settingsWriteError(
              response,
              context.l10n.settingsObjectSettingsAccessFailed,
              labels: objectFormLabels,
            ),
    );
  }

  Future<void> _chooseBoard(
    BuildContext context,
    WidgetRef ref,
    ObjectSummary summary,
    List<ObjectField> fields,
  ) async {
    final choices = boardChoices(fields);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(context.l10n.settingsObjectSettingsGroupBoardBy),
            ),
            for (final c in [null, ...choices])
              ListTile(
                minTileHeight: 48,
                title: Text(c?.label ?? context.l10n.appObjectsNoBoard),
                trailing: (c?.key ?? '') == summary.boardField
                    ? Icon(LucideIcons.check, color: AppColors.primary600)
                    : null,
                onTap: () => Navigator.of(sheet).pop(c?.key ?? ''),
              ),
            if (choices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.l10n.settingsObjectSettingsBoardNeedsDropdown,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == summary.boardField || !context.mounted) {
      return;
    }
    final response = await ref
        .read(customObjectsApiProvider)
        .updateObject(objectKey, boardFieldBody(picked));
    if (!context.mounted) return;
    if (response.success) refreshObjects(ref, objectKey);
    _say(
      context,
      response.success
          ? (picked.isEmpty
                ? context.l10n.settingsObjectSettingsBoardOff
                : context.l10n.settingsObjectSettingsBoardSaved)
          : settingsWriteError(
              response,
              context.l10n.settingsObjectSettingsBoardFailed,
              labels: objectFormLabels,
            ),
    );
  }

  Future<void> _editField(
    BuildContext context,
    WidgetRef ref,
    ObjectField? field,
    List<LinkTarget> targets,
  ) {
    return showObjectFieldSheet(
      context,
      existing: field,
      linkTargets: targets,
      onSubmit: (body) async {
        final api = ref.read(customObjectsApiProvider);
        final response = field == null
            ? await api.createField(objectKey, body)
            : await api.updateField(objectKey, field.key, body);
        if (!response.success) {
          return settingsWriteError(
            response,
            appL10n.settingsObjectSettingsSaveFieldError,
            labels: fieldFormLabels,
          );
        }
        refreshObjects(ref, objectKey);
        return null;
      },
    );
  }

  Future<void> _turn(
    BuildContext context,
    WidgetRef ref,
    ObjectField field,
    bool on,
  ) async {
    if (!on) {
      final ok = await _confirm(
        context,
        title: context.l10n.settingsObjectSettingsTurnOffTitle(field.label),
        body: context.l10n.settingsObjectSettingsTurnOffBody,
        action: context.l10n.settingsObjectSettingsTurnOff,
      );
      if (!ok || !context.mounted) return;
    }
    final api = ref.read(customObjectsApiProvider);
    final response = on
        ? await api.updateField(objectKey, field.key, {'is_active': true})
        : await api.turnOffField(objectKey, field.key);
    if (!context.mounted) return;
    if (response.success) refreshObjects(ref, objectKey);
    _say(
      context,
      response.success
          ? (on
                ? context.l10n.settingsObjectSettingsFieldTurnedOn
                : context.l10n.settingsObjectSettingsFieldTurnedOff)
          : settingsWriteError(
              response,
              context.l10n.settingsObjectSettingsCouldNotDoThat,
              labels: fieldFormLabels,
            ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(objectSettingsProvider(objectKey));
    final answerState = ref.watch(customObjectsProvider);
    final answer = shownCustomObjects(answerState);
    final loadFailed = customObjectsFailed(answerState);
    final isAdmin = ref.watch(isOrgAdminProvider);
    final targets = answer?.linkTargets ?? const <LinkTarget>[];

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(
          async.value?.summary.labelPlural ??
              context.l10n.settingsObjectSettingsTitleFallback,
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.settingsObjectSettingsLoadError),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(objectSettingsProvider(objectKey)),
                  child: Text(context.l10n.settingsObjectsTryAgain),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          final summary = data.summary;
          final canWrite = isAdmin && canWriteObject(summary, answer);
          final canShape = isAdmin && canCustomizeObject(summary, answer);
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(objectSettingsProvider(objectKey).future),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (isAdmin && loadFailed)
                  _LoadFailed(
                    onRetry: () => ref.invalidate(customObjectsProvider),
                  )
                else if (isAdmin && !canShape && !answerState.isLoading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      objectShapeLockedNotice,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                _Details(
                  summary: summary,
                  boardLabel: boardLabelOf(summary, data.fields),
                  actions: [
                    if (canShape)
                      _action(
                        context.l10n.settingsObjectSettingsEditObject,
                        () => _editObject(context, ref, summary),
                      )
                    else if (canWrite)
                      _action(
                        context.l10n.settingsObjectSettingsWhoSees,
                        () => _chooseAccess(context, ref, summary),
                      ),
                    if (canWrite)
                      _action(
                        context.l10n.appObjectFormBoardField,
                        () => _chooseBoard(context, ref, summary, data.fields),
                      ),
                    if (isAdmin && summary.isActive)
                      _action(
                        context.l10n.settingsObjectSettingsArchive,
                        () => _setActive(context, ref, summary, false),
                        danger: true,
                      ),
                    if (isAdmin && !summary.isActive) ...[
                      _action(
                        context.l10n.settingsObjectSettingsRestore,
                        () => _setActive(context, ref, summary, true),
                      ),
                      _action(
                        context.l10n.settingsObjectSettingsDeleteForGood,
                        () => _destroy(context, ref, summary),
                        danger: true,
                      ),
                    ],
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.settingsObjectSettingsFieldsHeader,
                          style: AppTypography.overline.copyWith(
                            color: AppColors.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      if (canShape)
                        SizedBox(
                          height: 44,
                          child: TextButton.icon(
                            onPressed: () =>
                                _editField(context, ref, null, targets),
                            icon: const Icon(LucideIcons.plus, size: 16),
                            label: Text(context.l10n.settingsObjectsAddField),
                          ),
                        ),
                    ],
                  ),
                ),
                if (data.fields.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.l10n.settingsObjectSettingsFieldsEmpty,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                for (final f in data.fields)
                  _FieldRow(
                    field: f,
                    targets: targets,
                    canWrite: canWrite,
                    canShape: canShape,
                    onEdit: () => _editField(context, ref, f, targets),
                    onTurn: () => _turn(context, ref, f, !f.isActive),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  _Action _action(String label, VoidCallback onTap, {bool danger = false}) =>
      _Action(label, onTap, danger);
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              objectsLoadFailedNotice,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            child: Text(context.l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}

class _Action {
  const _Action(this.label, this.onTap, this.danger);

  final String label;
  final VoidCallback onTap;
  final bool danger;
}

class _Details extends StatelessWidget {
  const _Details({
    required this.summary,
    required this.actions,
    required this.boardLabel,
  });

  final ObjectSummary summary;
  final String boardLabel;
  final List<_Action> actions;

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        Text(value, style: AppTypography.body),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line(l10n.commonName, '${summary.label} / ${summary.labelPlural}'),
          _line(l10n.settingsObjectsKey, summary.key),
          _line(l10n.settingsObjectSettingsNameCalled, summary.nameLabel),
          _line(
            l10n.settingsObjectsAccessLabel,
            summary.recordAccess == 'everyone'
                ? l10n.settingsObjectsAccessEveryone
                : l10n.settingsObjectsAccessOwn,
          ),
          _line(l10n.appObjectFormBoardField, boardLabel),
          if (summary.description.isNotEmpty)
            _line(l10n.commonDescription, summary.description),
          if (!summary.isActive) ...[
            const SizedBox(height: 10),
            StatusBadge(
              label: l10n.settingsObjectsArchived,
              color: AppColors.gray500,
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in actions)
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: a.onTap,
                      style: a.danger
                          ? OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger600,
                            )
                          : null,
                      child: Text(a.label),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.targets,
    required this.canWrite,
    required this.canShape,
    required this.onEdit,
    required this.onTurn,
  });

  final ObjectField field;
  final List<LinkTarget> targets;
  final bool canWrite;
  final bool canShape;
  final VoidCallback onEdit;
  final VoidCallback onTurn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = objectFieldTypeLabels[field.fieldType] ?? field.fieldType;
    final target = linkTargetLabel(targets, field.target);
    final detail = [
      type,
      if (field.isLink)
        field.many == true
            ? l10n.settingsObjectSettingsLinkSeveral(target)
            : l10n.settingsObjectSettingsLinkOne(target),
      if (field.options.isNotEmpty)
        field.options.map((o) => o.label).join(', '),
    ].join(' · ');
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: field.isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              if (!field.isActive)
                StatusBadge(
                  label: l10n.settingsObjectSettingsTurnedOff,
                  color: AppColors.gray500,
                )
              else if (field.isRequired)
                StatusBadge(
                  label: l10n.settingsObjectsRequired,
                  color: AppColors.primary600,
                ),
            ],
          ),
          Text(
            field.key,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (canWrite) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canShape)
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: onEdit,
                      child: Text(l10n.commonEdit),
                    ),
                  ),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: onTurn,
                    style: field.isActive
                        ? OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger600,
                          )
                        : null,
                    child: Text(
                      field.isActive
                          ? l10n.settingsObjectSettingsTurnOff
                          : l10n.settingsObjectSettingsTurnOn,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
