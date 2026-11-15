import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme.dart';
import '../../data/models/reopen_policy.dart';
import '../../data/models/ticket.dart';
import '../../l10n/l10n.dart';

/// A ticket status code ("Pending") as the ticket screens name it, or the
/// code itself for one this build does not know.
String reopenStatusName(String code) {
  for (final s in TicketStatus.values) {
    if (s.value == code) return s.displayName;
  }
  return code;
}

/// Edit the org's reopen policy.
///
/// Returns the request body, or `null` if dismissed. All four fields go every
/// time: the form edits all four at once, and a partial body would make
/// "switched off" and "not sent" the same thing for the two booleans.
Future<Map<String, dynamic>?> showReopenFormSheet(
  BuildContext context,
  ReopenPolicy policy,
) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ReopenFormSheet(policy: policy),
  );
}

class _ReopenFormSheet extends StatefulWidget {
  const _ReopenFormSheet({required this.policy});

  final ReopenPolicy policy;

  @override
  State<_ReopenFormSheet> createState() => _ReopenFormSheetState();
}

class _ReopenFormSheetState extends State<_ReopenFormSheet> {
  late final TextEditingController _window;
  late bool _isEnabled;
  late bool _notifyAssigned;
  late String _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _window = TextEditingController(text: '${widget.policy.windowDays}');
    _isEnabled = widget.policy.isEnabled;
    _notifyAssigned = widget.policy.notifyAssigned;
    _status = widget.policy.reopenToStatus;
  }

  @override
  void dispose() {
    _window.dispose();
    super.dispose();
  }

  void _submit() {
    final days = int.tryParse(_window.text.trim());
    final problem = reopenPolicyProblem(
      windowDays: days,
      reopenToStatus: _status,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(
      reopenPolicyPayload(
        isEnabled: _isEnabled,
        windowDays: days!,
        reopenToStatus: _status,
        notifyAssigned: _notifyAssigned,
      ),
    );
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
              l10n.settingsReopenTitle,
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isEnabled,
              onChanged: (v) => setState(() => _isEnabled = v),
              title: Text(l10n.settingsReopenEnabledLabel),
              subtitle: Text(
                _isEnabled
                    ? l10n.settingsReopenFormEnabledOn
                    : l10n.settingsReopenFormEnabledOff,
                style: AppTypography.caption.copyWith(
                  color: _isEnabled
                      ? AppColors.textSecondary
                      : AppColors.warning600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _window,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: l10n.settingsReopenFormWindowLabel,
                helperText: l10n.settingsReopenFormWindowHelper(
                  reopenWindowMin,
                  reopenWindowMax,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.settingsReopenStatusLabel,
                helperText: l10n.settingsReopenFormStatusHelper,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final status in reopenToStatuses)
                  DropdownMenuItem(
                    value: status,
                    child: Text(reopenStatusName(status)),
                  ),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _notifyAssigned,
              onChanged: (v) => setState(() => _notifyAssigned = v),
              title: Text(l10n.settingsReopenNotifyLabel),
              subtitle: Text(
                l10n.settingsReopenNotifyDetail,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
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
                      child: Text(l10n.settingsReopenFormSave),
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
