import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/contact.dart';
import '../../providers/contacts_provider.dart';
import '../../providers/duplicates_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/duplicates/duplicates_panel.dart';
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

class _ContactDetailScreenState extends ConsumerState<ContactDetailScreen> {
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
          DuplicatesPanel(
            module: DuplicateModule.contacts,
            recordId: contact.id,
          ),
          _details(contact),
          _accounts(contact),
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
