import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme.dart';
import '../../data/models/deal_pipeline.dart';
import '../../l10n/l10n.dart';

/// Create or rename a deal pipeline. Returns the trimmed name, or null if
/// dismissed. A new pipeline starts with the six default stages, which the
/// server seeds.
Future<String?> showDealPipelineNameSheet(
  BuildContext context, {
  DealPipeline? existing,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _DealPipelineNameSheet(existing: existing),
  );
}

/// Add or edit a stage of a deal pipeline. Returns the request body, or null
/// if dismissed. The stage's code is not editable: the server derives it once
/// and every deal in the stage stores it.
Future<Map<String, dynamic>?> showDealStageSheet(
  BuildContext context, {
  DealPipelineStage? existing,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _DealStageSheet(existing: existing),
  );
}

class _DealPipelineNameSheet extends StatefulWidget {
  const _DealPipelineNameSheet({this.existing});

  final DealPipeline? existing;

  @override
  State<_DealPipelineNameSheet> createState() => _DealPipelineNameSheetState();
}

class _DealPipelineNameSheetState extends State<_DealPipelineNameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  String? _error;

  bool get _isCreate => widget.existing == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = dealPipelineNameProblem(_name.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: _isCreate
          ? context.l10n.settingsPipelineNew
          : context.l10n.settingsPipelineRenameTitle,
      error: _error,
      submitLabel: _isCreate
          ? context.l10n.commonCreate
          : context.l10n.commonSave,
      onSubmit: _submit,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: dealPipelineNameMax,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.commonName,
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
        if (_isCreate) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsDealPipelineSheetsNewHint,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _DealStageSheet extends StatefulWidget {
  const _DealStageSheet({this.existing});

  final DealPipelineStage? existing;

  @override
  State<_DealStageSheet> createState() => _DealStageSheetState();
}

class _DealStageSheetState extends State<_DealStageSheet> {
  late final TextEditingController _label = TextEditingController(
    text: widget.existing?.label ?? '',
  );
  late final TextEditingController _expected = TextEditingController(
    text: widget.existing?.expectedDays?.toString() ?? '',
  );
  late final TextEditingController _warning = TextEditingController(
    text: widget.existing?.warningDays?.toString() ?? '',
  );
  late String _kind = widget.existing?.kind ?? dealStageOpen;
  String? _error;

  bool get _isCreate => widget.existing == null;

  @override
  void dispose() {
    _label.dispose();
    _expected.dispose();
    _warning.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = dealStageDraftProblem(
      label: _label.text,
      kind: _kind,
      expectedDays: _expected.text,
      warningDays: _warning.text,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(
      dealStagePayload(
        label: _label.text,
        kind: _kind,
        expectedDays: _expected.text,
        warningDays: _warning.text,
      ),
    );
  }

  InputDecoration _days(String label, String helper) => InputDecoration(
    labelText: label,
    helperText: helper,
    helperMaxLines: 3,
    border: const OutlineInputBorder(),
  );

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: _isCreate
          ? context.l10n.settingsPipelineNewStage
          : context.l10n.settingsPipelineEditStage,
      error: _error,
      submitLabel: _isCreate
          ? context.l10n.settingsPipelineAddStage
          : context.l10n.commonSave,
      onSubmit: _submit,
      children: [
        TextField(
          controller: _label,
          autofocus: _isCreate,
          maxLength: dealStageLabelMax,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.commonName,
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _kind,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: context.l10n.settingsDealPipelineSheetsKind,
            helperText: context.l10n.settingsDealPipelineSheetsKindHint,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final entry in dealStageKinds.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (v) => setState(() => _kind = v ?? _kind),
        ),
        if (_kind == dealStageOpen) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _expected,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _days(
              context.l10n.settingsDealPipelineSheetsExpectedLabel,
              context.l10n.settingsDealPipelineSheetsExpectedHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _warning,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _days(
              context.l10n.settingsDealPipelineSheetsWarningLabel,
              context.l10n.settingsDealPipelineSheetsWarningHint,
            ),
          ),
        ],
      ],
    );
  }
}

/// Title, fields, the draft's problem if any, then Cancel and the submit
/// button, all above the keyboard.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.error,
    required this.submitLabel,
    required this.onSubmit,
    required this.children,
  });

  final String title;
  final String? error;
  final String submitLabel;
  final VoidCallback onSubmit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
              title,
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ...children,
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
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
                      child: Text(context.l10n.commonCancel),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: onSubmit,
                      child: Text(submitLabel),
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
