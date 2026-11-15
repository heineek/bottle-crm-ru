import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../data/models/webhook.dart';
import '../../l10n/l10n.dart';
import '../../providers/webhooks_provider.dart';

/// Create or edit a webhook. Returns the draft, or null if dismissed.
///
/// The two checks here (an https URL, at least one event) are hints so the
/// sheet does not submit something certain to bounce. The serializer is the
/// rule: it also resolves the host and refuses private addresses, which this
/// app cannot judge.
Future<WebhookDraft?> showWebhookFormSheet(
  BuildContext context, {
  required List<WebhookEventGroup> catalogue,
  WebhookEndpoint? initial,
}) {
  return showModalBottomSheet<WebhookDraft>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        WebhookFormSheet(catalogue: catalogue, initial: initial),
  );
}

class WebhookFormSheet extends StatefulWidget {
  const WebhookFormSheet({super.key, required this.catalogue, this.initial});

  final List<WebhookEventGroup> catalogue;
  final WebhookEndpoint? initial;

  @override
  State<WebhookFormSheet> createState() => _WebhookFormSheetState();
}

class _WebhookFormSheetState extends State<WebhookFormSheet> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initial?.url ?? '',
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late String _format = widget.initial?.format ?? WebhookEndpoint.formatJson;
  late final Set<String> _events = {...?widget.initial?.events};
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    if (!url.toLowerCase().startsWith('https://')) {
      setState(() => _error = context.l10n.settingsWebhookFormErrorHttps);
      return;
    }
    if (_events.isEmpty) {
      setState(() => _error = context.l10n.settingsWebhookFormErrorEvents);
      return;
    }
    // Catalogue order, so the saved list reads the same on both clients.
    final ordered = [
      for (final group in widget.catalogue)
        for (final name in group.events)
          if (_events.contains(name)) name,
    ];
    Navigator.of(context).pop((
      url: url,
      description: _description.text.trim(),
      format: _format,
      events: ordered,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              editing
                  ? l10n.settingsWebhookFormEditTitle
                  : l10n.settingsWebhookFormNewTitle,
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: l10n.settingsWebhookFormUrlLabel,
                hintText: 'https://hooks.zapier.com/hooks/catch/...',
                helperText: l10n.settingsWebhookFormUrlHelper,
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _description,
              maxLength: 255,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.settingsWebhookFormDescriptionLabel,
                hintText: l10n.settingsWebhookFormDescriptionHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: _format,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.settingsWebhookFormSendAs,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: WebhookEndpoint.formatJson,
                  child: Text(l10n.settingsWebhookFormFormatJson),
                ),
                DropdownMenuItem(
                  value: WebhookEndpoint.formatSlack,
                  child: Text(l10n.settingsWebhookFormFormatSlack),
                ),
              ],
              onChanged: (v) => setState(() => _format = v ?? _format),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.settingsWebhookFormEvents.toUpperCase(),
              style: AppTypography.overline.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            for (final group in widget.catalogue) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 2),
                child: Text(
                  group.label,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final name in group.events)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(webhookEventLabel(name)),
                  value: _events.contains(name),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _events.add(name);
                    } else {
                      _events.remove(name);
                    }
                  }),
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
                      child: Text(
                        editing
                            ? l10n.commonSave
                            : l10n.settingsWebhookFormAddButton,
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
