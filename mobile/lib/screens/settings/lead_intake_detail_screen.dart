import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/lead_intake.dart';
import '../../data/models/lead_source.dart';
import '../../providers/auth_provider.dart';
import '../../providers/lead_intakes_provider.dart';
import '../../providers/lead_sources_provider.dart';
import 'lead_capture_screen.dart';
import '../../l10n/l10n.dart';

/// One lead webhook: copy its URL, replace its key (shown once), switch it on
/// or off, and read its newest 50 deliveries. Its field mapping is shown, and
/// edited on the web only.
class LeadIntakeDetailScreen extends ConsumerStatefulWidget {
  const LeadIntakeDetailScreen({super.key, required this.intakeId});

  final String intakeId;

  @override
  ConsumerState<LeadIntakeDetailScreen> createState() =>
      _LeadIntakeDetailScreenState();
}

class _LeadIntakeDetailScreenState
    extends ConsumerState<LeadIntakeDetailScreen> {
  bool _busy = false;

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _copyUrl(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _say(context.l10n.settingsLeadIntakeUrlCopied);
  }

  Future<void> _replaceKey() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.settingsLeadIntakeReplaceTitle),
        content: Text(context.l10n.settingsLeadIntakeReplaceBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.settingsLeadIntakeReplaceKey),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final result = await ref
        .read(leadIntakesProvider.notifier)
        .replaceKey(widget.intakeId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      _say(result.error!);
      return;
    }
    await showIntakeKey(context, keyValue: result.key!);
  }

  Future<void> _toggle(LeadIntake intake) async {
    setState(() => _busy = true);
    final error = await ref
        .read(leadIntakesProvider.notifier)
        .setActive(intake.id, !intake.isActive);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(
      error ??
          (intake.isActive
              ? context.l10n.settingsLeadIntakeTurnedOff
              : context.l10n.settingsLeadIntakeTurnedOn),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isOrgAdminProvider);
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsLeadIntakeTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: !isAdmin ? const _MemberNotice() : _body(),
    );
  }

  Widget _body() {
    final async = ref.watch(leadIntakesProvider);
    if (async.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (async.hasError) {
      return _Centered(
        text: leadIntakesNotOffered(async)
            ? context.l10n.settingsLeadIntakeNotOffered
            : context.l10n.settingsLeadIntakeLoadFailed,
        onRetry: () => ref.read(leadIntakesProvider.notifier).refresh(),
      );
    }
    final intake = async.value!
        .where((i) => i.id == widget.intakeId)
        .firstOrNull;
    if (intake == null) {
      return _Centered(text: context.l10n.settingsLeadIntakeMissing);
    }
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(leadIntakeDeliveriesProvider(intake.id));
        await ref.read(leadIntakesProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 48),
        children: [
          _Summary(intake: intake),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: () => _copyUrl(intake.url),
                  icon: const Icon(LucideIcons.copy, size: 16),
                  label: Text(context.l10n.settingsLeadIntakeCopyUrl),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: _busy ? null : _replaceKey,
                  child: Text(context.l10n.settingsLeadIntakeReplaceKey),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: _busy ? null : () => _toggle(intake),
                  child: Text(
                    intake.isActive
                        ? context.l10n.settingsLeadCaptureTurnOff
                        : context.l10n.settingsLeadCaptureTurnOn,
                  ),
                ),
              ],
            ),
          ),
          if (intake.mapping.isNotEmpty) ...[
            _Header(context.l10n.settingsLeadIntakeFieldMapping),
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final m in intake.mapping)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '${m.from} → ${m.to}',
                        style: AppTypography.caption.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.settingsLeadIntakeMappingOnWeb,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          _Header(context.l10n.settingsLeadIntakeDeliveries),
          _Deliveries(intakeId: intake.id),
        ],
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.intake});

  final LeadIntake intake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final received = intake.lastReceivedAt;
    final source = intake.defaultSource.isEmpty
        ? ''
        : leadSourceLabel(
            intake.defaultSource,
            shownLeadSources(ref.watch(leadSourcesProvider))?.sources ??
                const [],
          );
    final caption = AppTypography.caption.copyWith(
      color: AppColors.textSecondary,
    );
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  intake.name.isEmpty
                      ? context.l10n.settingsLeadCaptureUntitledWebhook
                      : intake.name,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IntakeStatePill(intake: intake),
            ],
          ),
          const SizedBox(height: 6),
          Text(intake.presetLabel, style: caption),
          const SizedBox(height: 10),
          SelectableText(
            intake.url,
            style: AppTypography.caption.copyWith(
              fontFamily: 'monospace',
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            intake.keyHint.isEmpty
                ? context.l10n.settingsLeadIntakeKeyHidden
                : context.l10n.settingsLeadIntakeKeyEnding(intake.keyHint),
            style: caption,
          ),
          if (source.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              intake.sourceDetail.isEmpty
                  ? context.l10n.settingsLeadIntakeArriveAs(source)
                  : context.l10n.settingsLeadIntakeArriveAsDetail(
                      source,
                      intake.sourceDetail,
                    ),
              style: caption,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            received == null
                ? context.l10n.settingsLeadIntakeNothingYet
                : context.l10n.settingsLeadIntakeLastPost(
                    intakeWhen.format(received),
                  ),
            style: caption,
          ),
          if (intake.lastError.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              intake.lastError,
              style: AppTypography.caption.copyWith(
                color: AppColors.warning600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            context.l10n.settingsLeadIntakeAuthHint,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Deliveries extends ConsumerWidget {
  const _Deliveries({required this.intakeId});

  final String intakeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leadIntakeDeliveriesProvider(intakeId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.settingsLeadIntakeDeliveriesFailed,
          style: AppTypography.caption.copyWith(color: AppColors.danger600),
        ),
      ),
      data: (deliveries) {
        if (deliveries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.l10n.settingsLeadIntakeNothingYetDot,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          );
        }
        return Column(
          children: [for (final d in deliveries) _DeliveryRow(delivery: d)],
        );
      },
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.delivery});

  final IntakeDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final color = switch (delivery.result) {
      'created' || 'merged' => AppColors.success600,
      'rejected' => AppColors.danger600,
      _ => AppColors.textSecondary,
    };
    final received = delivery.receivedAt;
    final detail = [
      if (received != null) intakeWhen.format(received),
      if (delivery.externalId.isNotEmpty)
        context.l10n.settingsLeadIntakeExternalId(delivery.externalId),
    ].join(' · ');
    final leadId = delivery.leadId;
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: leadId == null ? null : () => context.push('/leads/$leadId'),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.gray100)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delivery.resultLabel,
                      style: AppTypography.body.copyWith(
                        color: color,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    if (delivery.error.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        delivery.error,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.danger600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (leadId != null)
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: AppColors.gray300,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.overline.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: AppTypography.body, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(context.l10n.appTryAgain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberNotice extends StatelessWidget {
  const _MemberNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsLeadIntakeAdminsOnly,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsLeadIntakeAdminsOnlyBody,
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
