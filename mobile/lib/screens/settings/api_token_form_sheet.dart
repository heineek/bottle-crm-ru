import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../data/models/access_token.dart';
import '../../l10n/l10n.dart';

/// What the create form collected. The payload itself is built in the provider
/// from `tokenCreatePayload`, so the sheet never decides the wire format.
typedef TokenDraft = ({String name, String expiryChoice, String accessChoice});

/// Create a personal access token.
///
/// Returns the draft, or null if dismissed. **Self-scoped underneath**: the
/// server sets the owner from the caller's own profile, so there is no owner
/// field here and no way to mint a token for someone else.
Future<TokenDraft?> showApiTokenFormSheet(BuildContext context) {
  return showModalBottomSheet<TokenDraft>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ApiTokenFormSheet(),
  );
}

class _ApiTokenFormSheet extends StatefulWidget {
  const _ApiTokenFormSheet();

  @override
  State<_ApiTokenFormSheet> createState() => _ApiTokenFormSheetState();
}

class _ApiTokenFormSheetState extends State<_ApiTokenFormSheet> {
  final TextEditingController _name = TextEditingController();

  /// 90 days, the first entry, so the default is an expiry rather than never.
  String _expiry = expiryChoices.first.value;
  String _access = accessChoices.first.value;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = tokenNameProblem(_name.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop((
      name: _name.text.trim(),
      expiryChoice: _expiry,
      accessChoice: _access,
    ));
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
              context.l10n.settingsApiTokenFormTitle,
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.settingsApiTokenFormIntro,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 255,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.l10n.settingsApiTokenFormNameLabel,
                hintText: context.l10n.settingsApiTokenFormNameHint,
                helperText: context.l10n.settingsApiTokenFormNameHelper,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: _access,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.settingsApiTokenFormAccess,
                helperText: context.l10n.settingsApiTokenFormAccessHelper,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final choice in accessChoices)
                  DropdownMenuItem(
                    value: choice.value,
                    child: Text(choice.label),
                  ),
              ],
              onChanged: (v) => setState(() => _access = v ?? _access),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _expiry,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.settingsApiTokenFormExpires,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final choice in expiryChoices)
                  DropdownMenuItem(
                    value: choice.value,
                    child: Text(choice.label),
                  ),
              ],
              onChanged: (v) => setState(() => _expiry = v ?? _expiry),
            ),
            if (_expiry == 'never') ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.settingsApiTokenFormNeverWarning,
                style: AppTypography.caption.copyWith(
                  color: AppColors.warning600,
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
                      child: Text(context.l10n.settingsApiTokenFormCreate),
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
