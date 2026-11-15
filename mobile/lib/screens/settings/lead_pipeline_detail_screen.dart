import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/lead_pipeline.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/lead_pipelines_provider.dart';
import 'lead_stage_form_sheet.dart';

/// One lead pipeline's stages, in the order the board shows them as lanes.
///
/// Every member may look. An admin may add, edit, delete and reorder stages;
/// the server answers 403 to anyone else. Reordering is the up and down
/// buttons on each row, and each press sends the whole order, because the
/// server takes nothing less.
class LeadPipelineDetailScreen extends ConsumerStatefulWidget {
  const LeadPipelineDetailScreen({super.key, required this.pipelineId});

  final String pipelineId;

  @override
  ConsumerState<LeadPipelineDetailScreen> createState() =>
      _LeadPipelineDetailScreenState();
}

class _LeadPipelineDetailScreenState
    extends ConsumerState<LeadPipelineDetailScreen> {
  /// True while a write is in flight, so a second press cannot send an order
  /// computed from a list the first one is still changing.
  bool _busy = false;

  LeadPipelineDetailNotifier get _notifier =>
      ref.read(leadPipelineDetailProvider(widget.pipelineId).notifier);

  Future<void> _run(Future<String?> Function() write, String done) async {
    setState(() => _busy = true);
    final error = await write();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error ?? done)));
  }

  Future<void> _edit(LeadStage? existing) async {
    final payload = await showLeadStageFormSheet(context, existing: existing);
    if (payload == null || !mounted) return;
    await _run(
      () => existing == null
          ? _notifier.createStage(payload)
          : _notifier.updateStage(existing.id, payload),
      existing == null
          ? context.l10n.settingsPipelineStageAdded
          : context.l10n.settingsPipelineStageSaved,
    );
  }

  Future<void> _delete(LeadStage stage) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsPipelineDeleteTitle(stage.name)),
        content: Text(context.l10n.settingsLeadPipelineDetailDeleteStageBody),
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
    if (confirmed != true || !mounted) return;
    await _run(
      () => _notifier.deleteStage(stage.id),
      context.l10n.settingsPipelineStageDeleted,
    );
  }

  Future<void> _move(int from, int to) => _run(
    () => _notifier.moveStage(from, to),
    context.l10n.settingsPipelineOrderSaved,
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(leadPipelineDetailProvider(widget.pipelineId));
    final isAdmin = ref.watch(isOrgAdminProvider);
    final canEdit = isAdmin && !_busy;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(
          async.value?.pipeline.name ??
              context.l10n.settingsPipelineTitleFallback,
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isAdmin && async.hasValue)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: context.l10n.settingsPipelineAddStage,
              onPressed: canEdit ? () => _edit(null) : null,
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error.toString().replaceFirst('Exception: ', ''),
          onRetry: () => _notifier.refresh(),
        ),
        data: (detail) => RefreshIndicator(
          onRefresh: () => _notifier.refresh(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _Header(detail: detail),
              if (detail.stages.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    isAdmin
                        ? context.l10n.settingsLeadPipelineDetailNoStagesAdmin
                        : context.l10n.settingsLeadPipelineDetailNoStages,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              for (final (index, stage) in detail.stages.indexed)
                _StageRow(
                  stage: stage,
                  isAdmin: isAdmin,
                  onEdit: canEdit ? () => _edit(stage) : null,
                  onDelete: canEdit ? () => _delete(stage) : null,
                  onMoveUp: canEdit && index > 0
                      ? () => _move(index, index - 1)
                      : null,
                  onMoveDown: canEdit && index < detail.stages.length - 1
                      ? () => _move(index, index + 1)
                      : null,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  context.l10n.settingsLeadPipelineDetailFooter,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final LeadPipelineDetail detail;

  @override
  Widget build(BuildContext context) {
    final pipeline = detail.pipeline;
    final counts = context.l10n.settingsPipelineCounts(
      context.l10n.settingsPipelineStageCount(detail.stages.length),
      context.l10n.settingsPipelineLeadCount(pipeline.leadCount),
    );
    return Container(
      color: AppColors.surface,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pipeline.description.isNotEmpty) ...[
            Text(
              pipeline.description,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            pipeline.isDefault
                ? context.l10n.settingsPipelineIsDefault(counts)
                : counts,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.stage,
    required this.isAdmin,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final LeadStage stage;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  String _summary(BuildContext context) {
    final parts = [
      leadStageTypeOptions(stage.stageType)[stage.stageType]!,
      if (stage.mapsToStatus != null)
        context.l10n.settingsLeadPipelineDetailSetsStatus(
          '${leadStageStatusOptions(stage.mapsToStatus)[stage.mapsToStatus]}',
        ),
      if (stage.winProbability > 0)
        context.l10n.settingsLeadPipelineDetailWinPercent(stage.winProbability),
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onEdit,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: stage.swatch,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stage.name,
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _summary(context),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            Text(
                              context.l10n.settingsPipelineLeadCount(
                                stage.leadCount,
                              ),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isAdmin) ...[
            _IconAction(
              icon: LucideIcons.chevronUp,
              tooltip: context.l10n.settingsPipelineMoveStageUp(stage.name),
              onPressed: onMoveUp,
            ),
            _IconAction(
              icon: LucideIcons.chevronDown,
              tooltip: context.l10n.settingsPipelineMoveStageDown(stage.name),
              onPressed: onMoveDown,
            ),
            _IconAction(
              icon: LucideIcons.trash2,
              tooltip: context.l10n.settingsPipelineDeleteStage(stage.name),
              color: AppColors.danger600,
              onPressed: onDelete,
            ),
          ],
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      color: color ?? AppColors.textSecondary,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
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
              message,
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
