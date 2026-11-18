import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/theme.dart';
import '../../data/models/contact.dart';
import '../../data/models/interaction.dart';
import '../../data/models/lead_source.dart';
import '../../providers/contacts_provider.dart';
import '../../providers/duplicates_provider.dart';
import '../../providers/interactions_provider.dart';
import '../../providers/lead_sources_provider.dart';
import '../../routes/app_router.dart';
import '../../services/after_tap.dart';
import '../../widgets/common/custom_fields_display.dart';
import '../../widgets/common/round_action_button.dart';
import '../../widgets/duplicates/duplicates_panel.dart';
import '../../widgets/interactions/after_tap_logging.dart';
import '../../widgets/interactions/record_timeline.dart';
import '../../widgets/objects/related_objects_section.dart';
import '../../l10n/l10n.dart';

/// One contact.
class ContactDetailScreen extends ConsumerStatefulWidget {
  const ContactDetailScreen({super.key, required this.contactId});

  final String contactId;

  @override
  ConsumerState<ContactDetailScreen> createState() =>
      _ContactDetailScreenState();
}

class _ContactDetailScreenState extends ConsumerState<ContactDetailScreen>
    with AfterTapLogging<ContactDetailScreen> {
  Contact? _contact;
  bool _loading = true;
  String? _error;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    ref.invalidate(
      recordDuplicatesProvider((DuplicateModule.contacts, widget.contactId)),
    );
    ref.invalidate(recordInteractionsProvider(_target));
    var notFound = false;
    final contact = await ref
        .read(contactsProvider.notifier)
        .getContact(widget.contactId, onNotFound: () => notFound = true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _contact = contact;
      // Only a 404 says "not found", and it covers both a deleted contact
      // and one this user may not open. Offline or a 500 is "could not load".
      if (contact == null) {
        _error = notFound
            ? context.l10n.contactsDetailNotFound
            : context.l10n.contactsFormLoadFailed;
      }
    });
  }

  InteractionTarget get _target =>
      (home: InteractionHome.contact, id: widget.contactId);

  /// The server's delete rule for this user (`can_delete` on the detail
  /// response), not a copy of it. The DELETE asks the same rule again.
  bool get _canDelete => _contact?.canDelete ?? false;

  Future<void> _confirmDelete() async {
    final contact = _contact;
    if (contact == null || _deleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.contactsDetailDeleteTitle),
        content: Text(context.l10n.contactsDetailDeleteBody(contact.fullName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.commonDelete,
              style: TextStyle(color: AppColors.danger600),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final failure = await ref
        .read(contactsProvider.notifier)
        .deleteContact(contact.id);
    if (!mounted) return;
    setState(() => _deleting = false);

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure), backgroundColor: AppColors.danger600),
      );
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final contact = _contact;
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(
          contact?.fullName ?? context.l10n.contactsDetailTitleFallback,
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (contact != null)
            IconButton(
              icon: const Icon(LucideIcons.edit3, size: 20),
              tooltip: context.l10n.contactsDetailEditTooltip,
              onPressed: () async {
                await context.push('${AppRoutes.contacts}/${contact.id}/edit');
                if (mounted) _load();
              },
            ),
          if (_canDelete)
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 20),
              tooltip: context.l10n.contactsDetailDeleteTooltip,
              onPressed: _deleting ? null : _confirmDelete,
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final contact = _contact;
    if (contact == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.alertCircle, size: 40, color: AppColors.danger500),
            const SizedBox(height: 12),
            Text(
              _error ?? context.l10n.contactsFormLoadFailed,
              textAlign: TextAlign.center,
              style: AppTypography.body,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _load,
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 48),
        children: [
          if (contact.doNotCall) _doNotCallBanner(),
          _reach(contact),
          DuplicatesPanel(
            module: DuplicateModule.contacts,
            recordId: contact.id,
          ),
          _details(contact),
          _customFields(contact),
          _accounts(contact),
          _activity(),
          RelatedObjectsSection(to: 'contact', recordId: contact.id),
        ],
      ),
    );
  }

  /// Loud on purpose. Calling someone who asked not to be called is the kind
  /// of mistake a CRM exists to prevent, and a row in a list of ten would not
  /// stop anyone.
  Widget _doNotCallBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger50,
        border: Border.all(color: AppColors.danger500),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.phoneOff, size: 16, color: AppColors.danger600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.contactsDetailDoNotCall,
              style: AppTypography.caption.copyWith(color: AppColors.danger600),
            ),
          ),
        ],
      ),
    );
  }

  /// Call, Email, Message and WhatsApp. Call stays visible but off for
  /// someone who asked not to be phoned, as on the web.
  Widget _reach(Contact contact) {
    final phone = contact.phone?.trim() ?? '';
    final email = contact.email?.trim() ?? '';
    final name = contact.firstName.trim().isNotEmpty
        ? contact.firstName.trim()
        : contact.fullName;
    final whatsApp = whatsAppUri(contact.phoneE164, contact.firstName);
    void open(Uri uri, InteractionKind kind, {LaunchMode? mode}) =>
        launchAndOfferLog(
          uri,
          kind: kind,
          target: _target,
          personName: name,
          mode: mode ?? LaunchMode.platformDefault,
        );
    return _card(
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: 16,
        runSpacing: 12,
        children: [
          RoundActionButton(
            icon: contact.doNotCall ? LucideIcons.phoneOff : LucideIcons.phone,
            label: contact.doNotCall
                ? context.l10n.contactsFormDoNotCall
                : context.l10n.contactsDetailCall,
            enabled: phone.isNotEmpty && !contact.doNotCall,
            onTap: () =>
                open(Uri(scheme: 'tel', path: phone), InteractionKind.call),
          ),
          RoundActionButton(
            icon: LucideIcons.mail,
            label: context.l10n.contactsDetailEmail,
            enabled: email.isNotEmpty,
            onTap: () =>
                open(Uri(scheme: 'mailto', path: email), InteractionKind.email),
          ),
          RoundActionButton(
            icon: LucideIcons.messageSquare,
            label: context.l10n.contactsDetailMessage,
            enabled: phone.isNotEmpty,
            onTap: () =>
                open(Uri(scheme: 'sms', path: phone), InteractionKind.sms),
          ),
          if (whatsApp != null)
            RoundActionButton(
              icon: LucideIcons.messageCircle,
              label: 'WhatsApp',
              onTap: () => open(
                whatsApp,
                InteractionKind.whatsapp,
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }

  /// Logged calls, meetings, emails and messages, and enquiries. Absent on an
  /// API without them.
  Widget _activity() {
    final async = ref.watch(recordInteractionsProvider(_target));
    final answer = async.value;
    if (async.hasError && answer == null) {
      return _card(
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.contactsDetailActivityFailed,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.invalidate(recordInteractionsProvider(_target)),
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      );
    }
    if (answer == null || !answer.offered) return const SizedBox.shrink();
    final events = [for (final i in answer.items) TimelineEvent.interaction(i)];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.history,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.contactsDetailActivity,
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InteractionsBar(
            answer: answer,
            onLog: () => logActivity(context, ref, _target),
          ),
          if (events.isEmpty)
            Text(
              context.l10n.contactsDetailNothingLogged,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          for (var i = 0; i < events.length; i++)
            TimelineEventRow(event: events[i], isLast: i == events.length - 1),
        ],
      ),
    );
  }

  Widget _details(Contact contact) {
    final l10n = context.l10n;
    final rows = <(String, String?)>[
      (l10n.commonEmail, contact.email),
      (l10n.commonPhone, contact.phone),
      (l10n.contactsDetailTitle, contact.title),
      (l10n.contactsFormDepartment, contact.department),
      (l10n.contactsFormCompany, contact.organization),
      (l10n.contactsDetailLinkedin, contact.linkedinUrl),
      (l10n.contactsFormAddress, _address(contact)),
      (
        l10n.commonAssignedTo,
        contact.assignedToNames.isEmpty
            ? null
            : contact.assignedToNames.join(', '),
      ),
      (
        l10n.commonTags,
        contact.tagNames.isEmpty ? null : contact.tagNames.join(', '),
      ),
      (
        l10n.contactsDetailSource,
        contact.source.isEmpty
            ? null
            : leadSourceLabel(
                contact.source,
                shownLeadSources(ref.watch(leadSourcesProvider))?.sources ??
                    const [],
              ),
      ),
      (l10n.contactsDetailSubSource, contact.sourceDetail),
      (l10n.contactsDetailReference, contact.sourceRef),
      (l10n.commonNotes, contact.description),
    ].where((row) => row.$2 != null && row.$2!.trim().isNotEmpty).toList();

    if (rows.isEmpty) {
      return _card(
        child: Text(
          l10n.contactsDetailNoDetails,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      row.$1,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(child: Text(row.$2!, style: AppTypography.body)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _customFields(Contact contact) {
    final definitions = contact.customFieldDefinitions;
    if (!CustomFieldsDisplay.shows(definitions)) return const SizedBox.shrink();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.listChecks,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.contactsDetailCustomFields,
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CustomFieldsDisplay(
            definitions: definitions,
            values: contact.customFields,
          ),
        ],
      ),
    );
  }

  String? _address(Contact contact) {
    final parts = [
      contact.addressLine,
      contact.city,
      contact.state,
      contact.postcode,
      contact.country,
    ].where((p) => p != null && p.trim().isNotEmpty).join(', ');
    return parts.isEmpty ? null : parts;
  }

  /// The primary FK and the many-to-many are separate relationships, and on
  /// this data the FK is often empty while the many-to-many carries the real
  /// links. Showing only one would make a well-linked contact look unattached.
  Widget _accounts(Contact contact) {
    final links = [
      if (contact.accountId != null && contact.accountName != null)
        ContactAccountLink(id: contact.accountId!, name: contact.accountName!),
      ...contact.linkedAccounts.where((a) => a.id != contact.accountId),
    ];
    if (links.isEmpty) return const SizedBox.shrink();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.building2,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.contactsDetailAccounts(links.length),
                style: AppTypography.label.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final link in links)
            InkWell(
              onTap: () => context.push('${AppRoutes.accounts}/${link.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        link.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body,
                      ),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 16,
                      color: AppColors.gray300,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.gray200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
