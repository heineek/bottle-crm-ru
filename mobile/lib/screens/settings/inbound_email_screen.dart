import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/mailbox.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common/badge.dart';
import 'mailbox_form_sheet.dart';

/// The addresses that turn email into tickets.
///
/// **What an address does with mail is not what its switch says.** Three states
/// create nothing (see [MailboxDelivery]), and both clients used to draw two of
/// them as working, silently, because inbound mail has nobody watching it fail.
/// Every row here says which gate it fails.
///
/// Reading is open to every member; every write is admin-only and the server
/// answers 403 to anyone else, whatever this screen shows.
class InboundEmailScreen extends ConsumerWidget {
  const InboundEmailScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Mailbox? existing,
  ) async {
    final state = ref.read(mailboxesProvider).value;
    final payload = await showMailboxFormSheet(
      context,
      existing: existing,
      leadsOffered: state?.leadsOffered ?? false,
      generatedDomain: state?.generatedDomain,
    );
    if (payload == null || !context.mounted) return;
    final notifier = ref.read(mailboxesProvider.notifier);
    final error = existing == null
        ? await notifier.createMailbox(payload)
        : await notifier.updateMailbox(existing.id, payload);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              (existing == null
                  ? context.l10n.settingsInboundEmailAdded
                  : context.l10n.settingsInboundEmailSaved),
        ),
      ),
    );
  }

  Future<void> _turnOff(
    BuildContext context,
    WidgetRef ref,
    Mailbox mailbox,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.settingsInboundEmailTurnOffTitle(mailbox.address),
        ),
        content: Text(mailboxDeactivateExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.settingsInboundEmailLeaveOn),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.settingsInboundEmailTurnOff),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final error = await ref
        .read(mailboxesProvider.notifier)
        .deactivateMailbox(mailbox.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? context.l10n.settingsInboundEmailTurnedOffToast),
      ),
    );
  }

  Future<void> _turnOn(
    BuildContext context,
    WidgetRef ref,
    Mailbox mailbox,
  ) async {
    final error = await ref
        .read(mailboxesProvider.notifier)
        .activateMailbox(mailbox.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? context.l10n.settingsInboundEmailTurnedOnToast),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Mailbox mailbox,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context.l10n.settingsInboundEmailDeleteTitle(mailbox.address),
        ),
        content: Text(mailboxDeleteExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.settingsInboundEmailKeepIt),
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
        .read(mailboxesProvider.notifier)
        .deleteMailbox(mailbox.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? context.l10n.settingsInboundEmailDeleted),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mailboxesProvider);
    final isAdmin = ref.watch(isOrgAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsInboundEmailTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: context.l10n.settingsInboundEmailAdd,
              onPressed: () => _edit(context, ref, null),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.read(mailboxesProvider.notifier).refresh(),
        ),
        data: (state) {
          if (state.mailboxes.isEmpty) return _EmptyState(isAdmin: isAdmin);
          return RefreshIndicator(
            onRefresh: () => ref.read(mailboxesProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _Summary(state: state),
                for (final mailbox in state.mailboxes)
                  _MailboxRow(
                    mailbox: mailbox,
                    dailyLimit: state.dailyLimit,
                    canEdit: isAdmin,
                    onEdit: () => _edit(context, ref, mailbox),
                    onTurnOff: () => _turnOff(context, ref, mailbox),
                    onTurnOn: () => _turnOn(context, ref, mailbox),
                    onDelete: () => _delete(context, ref, mailbox),
                  ),
                _AuthNote(dailyLimit: state.dailyLimit),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final MailboxesState state;

  @override
  Widget build(BuildContext context) {
    final silent = state.silent;
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      margin: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              // Not the server's `active`, which counts the switch. This counts
              // the addresses that would actually open a ticket.
              _Stat(
                value: '${state.delivering}',
                label: context.l10n.settingsInboundEmailStatDelivering,
              ),
              _Stat(
                value: '${state.count}',
                label: context.l10n.settingsInboundEmailStatAddresses,
              ),
              _Stat(
                value: '${state.casesLast30d}',
                label: context.l10n.settingsInboundEmailStatTickets,
              ),
              if (state.deliveringLeads > 0)
                _Stat(
                  value: '${state.deliveringLeads}',
                  label: context.l10n.settingsInboundEmailStatLeads,
                ),
            ],
          ),
          if (silent.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Warning(
              text: silent.length == 1
                  ? context.l10n.settingsInboundEmailSilentOne(
                      silent.first.address,
                    )
                  : context.l10n.settingsInboundEmailSilentMany(silent.length),
            ),
          ],
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 18,
            color: AppColors.warning600,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.h2.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _MailboxRow extends StatelessWidget {
  const _MailboxRow({
    required this.mailbox,
    required this.dailyLimit,
    required this.canEdit,
    required this.onEdit,
    required this.onTurnOff,
    required this.onTurnOn,
    required this.onDelete,
  });

  final Mailbox mailbox;
  final int? dailyLimit;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onTurnOff;
  final VoidCallback onTurnOn;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final delivery = mailbox.delivery;
    final why = mailbox.deliveryExplanation;
    final dropped = mailbox.dropSummary;
    final atLimit = mailbox.limitNotice(dailyLimit);
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mailbox.address,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: delivery.isLive
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusBadge(
                label: mailbox.deliveryLabel,
                color: delivery.isLive
                    ? AppColors.success600
                    : AppColors.gray500,
              ),
              StatusBadge(
                label:
                    mailboxProviderLabels[mailbox.provider] ?? mailbox.provider,
                color: AppColors.gray500,
              ),
              if (!mailbox.createsLeads)
                StatusBadge(
                  label: context.l10n.settingsInboundEmailRowCases(
                    mailbox.casesLast30d,
                  ),
                  color: AppColors.gray500,
                ),
            ],
          ),
          if (dropped != null) ...[
            const SizedBox(height: 6),
            Text(
              dropped,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (atLimit != null) ...[
            const SizedBox(height: 6),
            Text(
              atLimit,
              style: AppTypography.caption.copyWith(
                color: AppColors.warning600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            mailbox.createsLeads
                ? mailbox.opensAs
                : context.l10n.settingsInboundEmailOpensAs(mailbox.opensAs),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (why != null) ...[
            const SizedBox(height: 8),
            Text(
              why,
              style: AppTypography.caption.copyWith(
                color: AppColors.warning600,
              ),
            ),
          ],
          if (canEdit) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: Text(context.l10n.commonEdit),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: mailbox.isActive
                      ? OutlinedButton(
                          onPressed: onTurnOff,
                          child: Text(context.l10n.settingsInboundEmailTurnOff),
                        )
                      : OutlinedButton(
                          onPressed: onTurnOn,
                          child: Text(context.l10n.settingsInboundEmailTurnOn),
                        ),
                ),
                SizedBox(
                  height: 40,
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
          ],
        ],
      ),
    );
  }
}

/// What actually proves a delivery genuine, stated once.
///
/// The web carried a card saying a per-address shared secret did it and that
/// the server minted one on create. Neither is true, so neither client says it.
class _AuthNote extends StatelessWidget {
  const _AuthNote({required this.dailyLimit});

  final int? dailyLimit;

  @override
  Widget build(BuildContext context) {
    final policy = mailboxDropPolicy(dailyLimit);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.settingsInboundEmailAuthTitle,
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            mailboxAuthExplanation,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          if (policy != null) ...[
            const SizedBox(height: 8),
            Text(
              policy,
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mail, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsInboundEmailEmptyTitle,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? context.l10n.settingsInboundEmailEmptyAdmin
                  : context.l10n.settingsInboundEmailEmptyMember,
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
      child: Padding(
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
              context.l10n.settingsInboundEmailLoadError,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.settingsInboundEmailTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
