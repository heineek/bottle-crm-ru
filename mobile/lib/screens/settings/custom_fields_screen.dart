import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/custom_field_definition.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common/badge.dart';
import 'custom_field_form_sheet.dart';

/// Fields this organization added to records that shipped without them.
///
/// Grouped by the record they extend, because that is how anyone looks for
/// one: "what do we collect on a ticket", not "show me all forty definitions".
///
/// The number that earns its place is `records_missing_value`. Marking a field
/// required binds writes from that moment and backfills nothing, so "Required"
/// on a field twenty-three records have no value for is a promise the stored
/// data does not keep, and any report on that field will quietly exclude or
/// mis-bucket those twenty-three.
///
/// Reading is open to every member; create, edit and turn off are admin-only
/// and the server answers 403 to anyone else. The controls follow that rule so
/// a member is not offered an action that cannot work.
class CustomFieldsScreen extends ConsumerWidget {
  const CustomFieldsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CustomFieldDefinition? existing,
  ) async {
    final draft = await showCustomFieldFormSheet(context, existing);
    if (draft == null || !context.mounted) return;
    final notifier = ref.read(customFieldsProvider.notifier);
    final error = existing == null
        ? await notifier.createField(draft)
        : await notifier.updateField(existing.id, draft);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (existing == null
                  ? context.l10n.settingsCustomFieldsAdded
                  : context.l10n.settingsCustomFieldsSaved),
        ),
      ),
    );
  }

  Future<void> _turnOff(
    BuildContext context,
    WidgetRef ref,
    CustomFieldDefinition field,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsCustomFieldsTurnOffTitle(field.label)),
        // Deliberately not "delete". The server soft-deletes: it flips
        // is_active and every value already stored stays readable on the
        // records that carry it. Saying Delete would promise a removal that
        // does not happen.
        content: Text(context.l10n.settingsCustomFieldsTurnOffBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.settingsCustomFieldsLeaveOn),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger600),
            child: Text(context.l10n.settingsCustomFieldsTurnOff),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await ref
        .read(customFieldsProvider.notifier)
        .deactivateField(field.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? context.l10n.settingsCustomFieldsTurnedOffSnack),
      ),
    );
  }

  Future<void> _turnOn(
    BuildContext context,
    WidgetRef ref,
    CustomFieldDefinition field,
  ) async {
    final error = await ref
        .read(customFieldsProvider.notifier)
        .activateField(field.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? context.l10n.settingsCustomFieldsTurnedOnSnack),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customFieldsProvider);
    final isAdmin = ref.watch(isOrgAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsCustomFieldsTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: context.l10n.settingsCustomFieldsNewField,
              onPressed: () => _edit(context, ref, null),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.read(customFieldsProvider.notifier).refresh(),
        ),
        data: (state) {
          if (state.fields.isEmpty) {
            return _EmptyState(isAdmin: isAdmin);
          }
          final groups = state.grouped;
          return RefreshIndicator(
            onRefresh: () => ref.read(customFieldsProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _Summary(state: state),
                for (final group in groups) ...[
                  _GroupHeader(
                    label: customFieldTargetLabel(group.key),
                    count: group.value.length,
                  ),
                  for (final field in group.value)
                    _FieldRow(
                      field: field,
                      canEdit: isAdmin,
                      onEdit: () => _edit(context, ref, field),
                      onTurnOff: () => _turnOff(context, ref, field),
                      onTurnOn: () => _turnOn(context, ref, field),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The counts, and the one warning worth interrupting for.
class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final CustomFieldsState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      margin: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: at 390px three stat pairs plus their labels do not
          // fit on one line, and a Row would overflow rather than wrap.
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _Stat(
                value: '${state.active}',
                label: context.l10n.settingsCustomFieldsStatInUse,
              ),
              _Stat(
                value: '${state.count - state.active}',
                label: context.l10n.settingsCustomFieldsStatTurnedOff,
              ),
              _Stat(
                value: '${state.modelsExtended}',
                label: context.l10n.settingsCustomFieldsStatRecordTypes(
                  state.modelsExtended,
                ),
              ),
            ],
          ),
          if (state.requiredWithGaps > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.triangleAlert,
                    size: 18,
                    color: AppColors.warning600,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10n.settingsCustomFieldsGapsBanner(
                        state.requiredWithGaps,
                      ),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.h2.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTypography.overline.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Text(
            '$count',
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.canEdit,
    required this.onEdit,
    required this.onTurnOff,
    required this.onTurnOn,
  });

  final CustomFieldDefinition field;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onTurnOff;
  final VoidCallback onTurnOn;

  @override
  Widget build(BuildContext context) {
    final missing = field.recordsMissingValue;
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: field.isActive
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            field.key,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(
                label: field.fieldType.label,
                color: AppColors.gray500,
              ),
              if (!field.isActive)
                StatusBadge(
                  label: context.l10n.settingsCustomFieldsBadgeOff,
                  color: AppColors.gray500,
                ),
              if (field.isRequired)
                StatusBadge(
                  label: context.l10n.settingsCustomFieldsRequired,
                  color: AppColors.primary600,
                ),
              if (field.isFilterable)
                StatusBadge(
                  label: context.l10n.settingsCustomFieldsBadgeFilter,
                  color: AppColors.gray500,
                ),
              if (field.fieldType == CustomFieldType.dropdown)
                Text(
                  context.l10n.settingsCustomFieldsOptionCount(
                    field.options.length,
                  ),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          // Only worth saying when it is a problem. A count on an optional
          // field is just "records saved before this existed", which is not
          // news; on a required one it is the gap the banner warns about.
          if (field.isRequired && missing > 0) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsCustomFieldsMissing(missing),
              style: AppTypography.caption.copyWith(
                color: AppColors.warning600,
              ),
            ),
          ],
          if (canEdit) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: Text(context.l10n.commonEdit),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: field.isActive
                      ? OutlinedButton(
                          onPressed: onTurnOff,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger600,
                          ),
                          child: Text(context.l10n.settingsCustomFieldsTurnOff),
                        )
                      : OutlinedButton(
                          onPressed: onTurnOn,
                          child: Text(context.l10n.settingsCustomFieldsTurnOn),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.listPlus, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsCustomFieldsEmptyTitle,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? context.l10n.settingsCustomFieldsEmptyAdmin
                  : context.l10n.settingsCustomFieldsEmptyMember,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.triangleAlert,
              size: 40,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsCustomFieldsLoadFailed,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.settingsPipelineTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
