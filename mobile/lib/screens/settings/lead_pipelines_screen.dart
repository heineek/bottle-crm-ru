import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/lead_pipeline.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/lead_pipelines_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/common/badge.dart';
import 'lead_pipeline_form_sheet.dart';

/// The org's lead pipelines: the boards leads are moved through.
///
/// Reading is open to every member; creating, renaming and deleting are
/// admin-only, and the server answers 403 to anyone else. A pipeline that
/// still holds leads cannot be deleted, and the server says how many.
class LeadPipelinesScreen extends ConsumerWidget {
  const LeadPipelinesScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    LeadPipeline? existing,
  ) async {
    final payload = await showLeadPipelineFormSheet(
      context,
      existing: existing,
    );
    if (payload == null || !context.mounted) return;
    final notifier = ref.read(leadPipelinesProvider.notifier);
    final error = existing == null
        ? await notifier.createPipeline(payload)
        : await notifier.updatePipeline(existing.id, payload);
    if (!context.mounted) return;
    _snack(
      context,
      error ??
          (existing == null
              ? context.l10n.settingsPipelineCreated
              : context.l10n.settingsLeadPipelinesSaved),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    LeadPipeline pipeline,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsPipelineDeleteTitle(pipeline.name)),
        content: Text(context.l10n.settingsLeadPipelinesDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.settingsPipelineKeepIt),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger600),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await ref
        .read(leadPipelinesProvider.notifier)
        .deletePipeline(pipeline.id);
    if (!context.mounted) return;
    _snack(context, error ?? context.l10n.settingsPipelineDeleted);
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leadPipelinesProvider);
    final isAdmin = ref.watch(isOrgAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsLeadPipelinesTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: context.l10n.settingsPipelineNew,
              onPressed: () => _edit(context, ref, null),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.read(leadPipelinesProvider.notifier).refresh(),
        ),
        data: (pipelines) {
          if (pipelines.isEmpty) return _EmptyState(isAdmin: isAdmin);
          return RefreshIndicator(
            onRefresh: () => ref.read(leadPipelinesProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final pipeline in pipelines)
                  _PipelineRow(
                    pipeline: pipeline,
                    canEdit: isAdmin,
                    onOpen: () => context.push(
                      AppRoutes.settingsLeadPipeline(pipeline.id),
                    ),
                    onRename: () => _edit(context, ref, pipeline),
                    onDelete: () => _delete(context, ref, pipeline),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    context.l10n.settingsLeadPipelinesFooter,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PipelineRow extends StatelessWidget {
  const _PipelineRow({
    required this.pipeline,
    required this.canEdit,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final LeadPipeline pipeline;
  final bool canEdit;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              pipeline.name,
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (pipeline.isDefault)
                              StatusBadge(
                                label: context.l10n.settingsPipelineDefault,
                                color: AppColors.primary600,
                              ),
                          ],
                        ),
                        if (pipeline.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            pipeline.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          context.l10n.settingsPipelineCounts(
                            context.l10n.settingsPipelineStageCount(
                              pipeline.stageCount,
                            ),
                            context.l10n.settingsPipelineLeadCount(
                              pipeline.leadCount,
                            ),
                          ),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: onRename,
                      child: Text(context.l10n.settingsPipelineRename),
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: onDelete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger600,
                      ),
                      child: Text(context.l10n.commonDelete),
                    ),
                  ),
                ],
              ),
            ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.squareKanban,
              size: 40,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsLeadPipelinesEmptyTitle,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? context.l10n.settingsLeadPipelinesEmptyAdmin
                  : context.l10n.settingsLeadPipelinesEmptyMember,
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
      child: SingleChildScrollView(
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
              context.l10n.settingsPipelineLoadFailed,
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
