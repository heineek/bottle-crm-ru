import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_config.dart';
import '../../core/theme/theme.dart';
import '../../data/models/lead_source.dart';
import '../../data/models/mailbox.dart';
import '../../l10n/l10n.dart';
import '../../providers/lead_sources_provider.dart';
import '../../providers/lookup_provider.dart';

/// Add or edit an inbound address.
///
/// Returns the request body, or null if dismissed.
///
/// The webhook secret (Postmark's basic-auth password, Mailgun's signing key)
/// is write-only: the field is never prefilled, the sheet says only whether one
/// is stored, and a blank field sends nothing, so a save cannot blank it.
///
/// The SNS Topic ARN is a field. Only admins reach this sheet, and the server
/// sends the ARN to admins only; it is sent back only when changed
/// ([mailboxTopicArnEdit]).
///
/// [leadsOffered] and [generatedDomain] come from the list
/// ([MailboxesState]): an API without lead addresses gets the ticket form only,
/// and "Generate an address" appears only where the server makes them.
Future<Map<String, dynamic>?> showMailboxFormSheet(
  BuildContext context, {
  Mailbox? existing,
  bool leadsOffered = false,
  String? generatedDomain,
  bool startAsLeads = false,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _MailboxFormSheet(
      existing: existing,
      leadsOffered: leadsOffered,
      generatedDomain: generatedDomain,
      startAsLeads: startAsLeads,
    ),
  );
}

class _MailboxFormSheet extends ConsumerStatefulWidget {
  const _MailboxFormSheet({
    this.existing,
    this.leadsOffered = false,
    this.generatedDomain,
    this.startAsLeads = false,
  });

  final Mailbox? existing;
  final bool leadsOffered;
  final String? generatedDomain;
  final bool startAsLeads;

  @override
  ConsumerState<_MailboxFormSheet> createState() => _MailboxFormSheetState();
}

class _MailboxFormSheetState extends ConsumerState<_MailboxFormSheet> {
  late final TextEditingController _address;
  late final TextEditingController _topicArn;
  final TextEditingController _secret = TextEditingController();
  late String _provider;
  late String _priority;
  String? _caseType;
  String? _assigneeId;
  String? _error;
  late String _creates;
  late String _leadSource;
  late final TextEditingController _leadSourceDetail;
  bool _generate = false;

  bool get _isCreate => widget.existing == null;
  bool get _leads => widget.leadsOffered && _creates == mailboxCreatesLeads;
  bool get _canGenerate => _isCreate && widget.generatedDomain != null;

  @override
  void initState() {
    super.initState();
    final mailbox = widget.existing;
    _address = TextEditingController(text: mailbox?.address ?? '');
    _topicArn = TextEditingController(text: mailbox?.topicArn ?? '');
    _provider = mailbox?.provider ?? 'ses';
    _priority = mailbox?.defaultPriority ?? 'Normal';
    _caseType = mailbox?.defaultCaseType;
    _assigneeId = mailbox?.defaultAssignee?.id;
    _creates =
        mailbox?.creates ??
        (widget.startAsLeads ? mailboxCreatesLeads : mailboxCreatesTickets);
    _leadSource = mailbox?.leadSource ?? 'email';
    _leadSourceDetail = TextEditingController(
      text: mailbox?.leadSourceDetail ?? '',
    );
  }

  @override
  void dispose() {
    _address.dispose();
    _topicArn.dispose();
    _secret.dispose();
    _leadSourceDetail.dispose();
    super.dispose();
  }

  /// On a create, or when changed; [mailboxPayload] leaves out a null.
  String? _changed(String value, String? loaded) =>
      _isCreate || value != loaded ? value : null;

  /// The server's own address: one to generate, or one it already made.
  bool get _serverAddress =>
      (_canGenerate && _generate) || (widget.existing?.isGenerated ?? false);

  void _submit() {
    final problem = _serverAddress
        ? null
        : mailboxAddressProblem(_address.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final existing = widget.existing;
    Navigator.of(context).pop(
      mailboxPayload(
        address: _serverAddress ? null : _address.text,
        provider: _provider,
        defaultPriority: _priority,
        defaultCaseType: _caseType,
        defaultAssigneeId: _assigneeId,
        // Only the create form carries this. On an edit the row's own Turn off
        // and Turn on controls own the state, and resending it from here would
        // let a form opened before a toggle undo it.
        isActive: _isCreate ? true : null,
        topicArn: mailboxTopicArnEdit(
          _topicArn.text,
          widget.existing?.topicArn,
        ),
        webhookSecret: secretMailboxProviders.contains(_provider)
            ? _secret.text
            : null,
        generateAddress: _canGenerate && _generate,
        creates: widget.leadsOffered
            ? _changed(_creates, existing?.creates)
            : null,
        leadSource: _leads ? _changed(_leadSource, existing?.leadSource) : null,
        leadSourceDetail: _leads
            ? _changed(
                _leadSourceDetail.text.trim(),
                existing?.leadSourceDetail,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(usersProvider);
    // The stored assignee when the picker cannot offer them, because the
    // profile has been deactivated since it was chosen (or the list has not
    // loaded yet). Dropping them here would move the mailbox back to
    // unassigned as a side effect of editing the address, so they get an entry
    // of their own, labelled deactivated only when they are.
    final stored = widget.existing?.defaultAssignee;
    final offList = stored != null && !people.any((p) => p.id == stored.id)
        ? stored
        : null;

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
                  ? context.l10n.settingsMailboxFormNewTitle
                  : context.l10n.settingsMailboxFormEditTitle(
                      widget.existing!.address,
                    ),
              style: AppTypography.h3.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (widget.leadsOffered) ...[
              DropdownButtonFormField<String>(
                key: const ValueKey('mailbox-creates'),
                initialValue: _creates,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsMailboxFormCreates,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: mailboxCreatesTickets,
                    child: Text(context.l10n.settingsMailboxFormCreatesTickets),
                  ),
                  DropdownMenuItem(
                    value: mailboxCreatesLeads,
                    child: Text(context.l10n.settingsMailboxFormCreatesLeads),
                  ),
                ],
                onChanged: (v) => setState(() => _creates = v ?? _creates),
              ),
              const SizedBox(height: 12),
            ],
            if (_canGenerate) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _generate,
                onChanged: (v) => setState(() => _generate = v),
                title: Text(context.l10n.settingsMailboxFormGenerate),
                subtitle: Text(
                  context.l10n.settingsMailboxFormGenerateHint(
                    widget.generatedDomain ?? '',
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!_serverAddress) ...[
              TextField(
                controller: _address,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsMailboxFormAddress,
                  helperText: _isCreate
                      ? null
                      : _leads
                      ? context.l10n.settingsMailboxFormAddressHintLeads
                      : context.l10n.settingsMailboxFormAddressHint,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _provider,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsMailboxFormProvider,
                  helperText: context.l10n.settingsMailboxFormProviderHint,
                  helperMaxLines: 4,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final provider in mailboxProviderLabels.keys)
                    DropdownMenuItem(
                      value: provider,
                      child: Text(mailboxProviderLabel(provider)),
                    ),
                ],
                onChanged: (v) => setState(() => _provider = v ?? _provider),
              ),
              const SizedBox(height: 12),
              if (secretMailboxProviders.contains(_provider))
                ..._secretFields()
              else
                TextField(
                  key: const ValueKey('mailbox-topic-arn'),
                  controller: _topicArn,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'SNS Topic ARN',
                    hintText: 'arn:aws:sns:us-east-1:123456789012:inbound-mail',
                    helperText: context.l10n.settingsMailboxFormTopicHint,
                    helperMaxLines: 5,
                    border: OutlineInputBorder(),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            if (_leads) ...[
              _SectionLabel(context.l10n.settingsMailboxFormSectionLeadArrives),
              _leadSourceField(),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('mailbox-lead-source-detail'),
                controller: _leadSourceDetail,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsMailboxFormSubSource,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              _SectionLabel(context.l10n.settingsMailboxFormSectionOpensAs),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.commonPriority,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final priority in mailboxPriorities)
                    DropdownMenuItem(value: priority, child: Text(priority)),
                ],
                onChanged: (v) => setState(() => _priority = v ?? _priority),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _caseType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsMailboxFormType,
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.l10n.settingsMailboxFormNone),
                  ),
                  for (final type in mailboxCaseTypes)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: (v) => setState(() => _caseType = v),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String?>(
              initialValue: _assigneeId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.commonAssignedTo,
                helperText: _leads
                    ? context.l10n.settingsMailboxFormAssigneeHintLeads
                    : context.l10n.settingsMailboxFormAssigneeHint,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(
                    _leads
                        ? context.l10n.settingsMailboxFormUnassignedLeads
                        : context.l10n.settingsMailboxFormUnassigned,
                  ),
                ),
                if (offList != null)
                  DropdownMenuItem(
                    value: offList.id,
                    child: Text(
                      offList.isActive
                          ? offList.displayName
                          : context.l10n.settingsMailboxFormDeactivated(
                              offList.displayName,
                            ),
                    ),
                  ),
                for (final person in people)
                  DropdownMenuItem(
                    value: person.id,
                    child: Text(person.displayName),
                  ),
              ],
              onChanged: (v) => setState(() => _assigneeId = v),
            ),
            if (offList != null &&
                !offList.isActive &&
                _assigneeId == offList.id) ...[
              const SizedBox(height: 8),
              Text(
                _leads
                    ? context.l10n.settingsMailboxFormDeactivatedHintLeads
                    : context.l10n.settingsMailboxFormDeactivatedHint,
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
                      child: Text(
                        _isCreate
                            ? context.l10n.settingsMailboxFormAddAddress
                            : context.l10n.settingsMailboxFormSaveChanges,
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

  /// The write-only credential for Postmark or Mailgun, and the URL to give
  /// the provider. A new address has no id yet, so no URL.
  List<Widget> _secretFields() {
    final existing = widget.existing;
    final stored = existing?.hasWebhookSecret ?? false;
    final postmark = _provider == 'postmark';
    final l10n = context.l10n;
    final url = existing == null
        ? null
        : mailboxSetupUrl(_provider, existing.id, ApiConfig.baseUrl);
    return [
      TextField(
        key: const ValueKey('mailbox-webhook-secret'),
        controller: _secret,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: postmark
              ? l10n.settingsMailboxFormSecretPassword
              : l10n.settingsMailboxFormSecretSigningKey,
          helperText:
              '${stored ? l10n.settingsMailboxFormSecretStored : l10n.settingsMailboxFormSecretMissing} '
              '${postmark ? l10n.settingsMailboxFormSecretPostmark : l10n.settingsMailboxFormSecretMailgun}',
          helperMaxLines: 5,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      if (url != null)
        SelectableText(
          postmark
              ? l10n.settingsMailboxFormWebhookUrl(url)
              : l10n.settingsMailboxFormRouteAction(url),
          key: const ValueKey('mailbox-setup-url'),
          style: AppTypography.caption,
        )
      else
        Text(
          l10n.settingsMailboxFormSetupUrlLater,
          style: AppTypography.caption,
        ),
    ];
  }

  Widget _leadSourceField() {
    final async = ref.watch(leadSourcesProvider);
    final answer = shownLeadSources(async);
    final options = pickableSources(answer?.sources ?? const [], _leadSource);
    return DropdownButtonFormField<String>(
      key: const ValueKey('mailbox-lead-source'),
      initialValue: _leadSource.isEmpty ? null : _leadSource,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.l10n.settingsMailboxFormLeadSource,
        helperText: async.hasError
            ? context.l10n.settingsMailboxFormSourcesFailed
            : answer == null
            ? context.l10n.settingsMailboxFormSourcesLoading
            : null,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final source in options)
          DropdownMenuItem(value: source.key, child: Text(source.pickerLabel)),
      ],
      onChanged: (v) => setState(() => _leadSource = v ?? _leadSource),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: AppTypography.overline.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
