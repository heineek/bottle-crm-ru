import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../data/models/lead_pipeline.dart';
import '../../l10n/l10n.dart';

/// Create or rename a lead pipeline.
///
/// Returns the request body, or `null` if dismissed. A new pipeline also asks
/// whether to start with the default stages, which the server seeds when
/// `create_default_stages` is true (its default).
Future<Map<String, dynamic>?> showLeadPipelineFormSheet(
  BuildContext context, {
  LeadPipeline? existing,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _LeadPipelineFormSheet(existing: existing),
  );
}

class _LeadPipelineFormSheet extends StatefulWidget {
  const _LeadPipelineFormSheet({this.existing});

  final LeadPipeline? existing;

  @override
  State<_LeadPipelineFormSheet> createState() => _LeadPipelineFormSheetState();
}

class _LeadPipelineFormSheetState extends State<_LeadPipelineFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  bool _defaultStages = true;
  String? _error;

  bool get _isCreate => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _description = TextEditingController(
      text: widget.existing?.description ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = leadPipelineNameProblem(_name.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(
      leadPipelinePayload(
        name: _name.text,
        description: _description.text,
        createDefaultStages: _isCreate ? _defaultStages : null,
      ),
    );
  }

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
              _isCreate
                  ? context.l10n.settingsPipelineNew
                  : context.l10n.settingsPipelineRenameTitle,
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: leadPipelineNameMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.commonName,
                border: const OutlineInputBorder(),
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
                labelText: context.l10n.settingsLeadPipelineFormDescription,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_isCreate) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _defaultStages,
                onChanged: (v) => setState(() => _defaultStages = v),
                title: Text(context.l10n.settingsLeadPipelineFormDefaultStages),
                subtitle: Text(
                  _defaultStages
                      ? context.l10n.settingsLeadPipelineFormDefaultStagesOn
                      : context.l10n.settingsLeadPipelineFormDefaultStagesOff,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
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
                      child: Text(context.l10n.commonCancel),
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
                            ? context.l10n.commonCreate
                            : context.l10n.commonSave,
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
