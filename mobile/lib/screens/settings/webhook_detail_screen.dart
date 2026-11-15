import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/webhook.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/webhooks_provider.dart';
import 'webhook_form_sheet.dart';
import 'webhooks_screen.dart';

/// One webhook, mirroring `/settings/webhooks/<id>` on the web: send a test,
/// switch it on or off, rotate its secret, edit it, delete it, and read its
/// delivery log with a Redeliver on each settled row.
///
/// Sending is asynchronous. A test is queued as a `ping` and appears in the
/// log as Pending; pull to refresh shows the answer.
class WebhookDetailScreen extends ConsumerStatefulWidget {
  const WebhookDetailScreen({super.key, required this.webhookId});

  final String webhookId;

  @override
  ConsumerState<WebhookDetailScreen> createState() =>
      _WebhookDetailScreenState();
}

class _WebhookDetailScreenState extends ConsumerState<WebhookDetailScreen> {
  int _offset = 0;
  bool _busy = false;

  ({String id, int offset}) get _pageKey =>
      (id: widget.webhookId, offset: _offset);

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<String?> Function() action, String done) async {
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    _say(error ?? done);
    ref.invalidate(webhookDeliveriesProvider(_pageKey));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _rotate() async {
    final ok = await _confirm(
      context.l10n.settingsWebhookDetailRotateTitle,
      context.l10n.settingsWebhookDetailRotateBody,
      context.l10n.settingsWebhookDetailRotateNow,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final result = await ref
        .read(webhooksProvider.notifier)
        .rotate(widget.webhookId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.error != null) {
      _say(result.error!);
      return;
    }
    await showWebhookSecret(
      context,
      title: context.l10n.settingsWebhookDetailRotatedTitle,
      secret: result.secret ?? '',
    );
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      context.l10n.settingsWebhookDetailDeleteTitle,
      context.l10n.settingsWebhookDetailDeleteBody,
      context.l10n.settingsWebhookDetailDeletePermanently,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final error = await ref
        .read(webhooksProvider.notifier)
        .remove(widget.webhookId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _say(error);
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _edit(WebhookEndpoint endpoint, WebhooksState state) async {
    final draft = await showWebhookFormSheet(
      context,
      catalogue: state.catalogue,
      initial: endpoint,
    );
    if (draft == null || !mounted) return;
    await _run(
      () => ref.read(webhooksProvider.notifier).save(endpoint.id, draft),
      context.l10n.settingsWebhookDetailSaved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isOrgAdminProvider);
    final async = isAdmin ? ref.watch(webhooksProvider) : null;
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsWebhookDetailTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: !isAdmin
          ? const WebhooksMemberNotice()
          : async!.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => WebhookErrorState(
                message: context.l10n.settingsWebhookDetailLoadError,
                onRetry: () => ref.read(webhooksProvider.notifier).refresh(),
              ),
              data: (state) {
                final endpoint = state.byId(widget.webhookId);
                if (endpoint == null) {
                  return Center(
                    child: Text(
                      context.l10n.settingsWebhookDetailNotFound,
                      style: AppTypography.body,
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(webhookDeliveriesProvider(_pageKey));
                    await ref.read(webhooksProvider.notifier).refresh();
                  },
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 48),
                    children: [
                      _Summary(endpoint: endpoint),
                      _Actions(
                        endpoint: endpoint,
                        busy: _busy,
                        onTest: () => _run(
                          () => ref
                              .read(webhooksProvider.notifier)
                              .sendTest(endpoint.id),
                          context.l10n.settingsWebhookDetailTestQueued,
                        ),
                        onToggle: () => _run(
                          () => ref
                              .read(webhooksProvider.notifier)
                              .setActive(endpoint.id, !endpoint.isActive),
                          endpoint.isActive
                              ? context.l10n.settingsWebhookDetailTurnedOff
                              : context.l10n.settingsWebhookDetailTurnedOn,
                        ),
                        onEdit: () => _edit(endpoint, state),
                        onRotate: _rotate,
                        onDelete: _delete,
                      ),
                      _SectionHeader(
                        context.l10n.settingsWebhookDetailEvents(
                          endpoint.events.length,
                        ),
                      ),
                      Container(
                        color: AppColors.surface,
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final name in endpoint.events)
                              Chip(label: Text(name)),
                          ],
                        ),
                      ),
                      _SectionHeader(
                        context.l10n.settingsWebhookDetailDeliveries,
                      ),
                      _Deliveries(
                        pageKey: _pageKey,
                        canRedeliver: endpoint.isActive && !_busy,
                        onRedeliver: (id) => _run(
                          () =>
                              ref.read(webhooksProvider.notifier).redeliver(id),
                          context.l10n.settingsWebhookDetailRedelivered,
                        ),
                        onPage: (offset) => setState(() => _offset = offset),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.endpoint});

  final WebhookEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      margin: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  endpoint.title,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              WebhookStatePill(endpoint: endpoint),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            endpoint.url,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.settingsWebhookDetailSecretLine(
              endpoint.formatLabel,
              endpoint.secretHint,
            ),
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.settingsWebhookDetailAnswersFor(endpoint.creatorLabel),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (endpoint.disabledReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              endpoint.disabledReason,
              style: AppTypography.caption.copyWith(
                color: AppColors.warning600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsWebhookDetailAnswersNote,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.endpoint,
    required this.busy,
    required this.onTest,
    required this.onToggle,
    required this.onEdit,
    required this.onRotate,
    required this.onDelete,
  });

  final WebhookEndpoint endpoint;
  final bool busy;
  final VoidCallback onTest;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onRotate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const size = Size(0, 48);
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (endpoint.isActive)
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: size),
              onPressed: busy ? null : onTest,
              icon: const Icon(LucideIcons.send, size: 16),
              label: Text(context.l10n.settingsWebhookDetailSendTest),
            ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: size),
            onPressed: busy ? null : onToggle,
            child: Text(
              endpoint.isActive
                  ? context.l10n.settingsWebhookDetailTurnOff
                  : endpoint.disabledReason.isNotEmpty
                  ? context.l10n.settingsWebhookDetailReEnable
                  : context.l10n.settingsWebhookDetailTurnOn,
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: size),
            onPressed: busy ? null : onEdit,
            child: Text(context.l10n.commonEdit),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: size),
            onPressed: busy ? null : onRotate,
            child: Text(context.l10n.settingsWebhookDetailRotateSecret),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              foregroundColor: AppColors.danger600,
            ),
            onPressed: busy ? null : onDelete,
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
  }
}

class _Deliveries extends ConsumerWidget {
  const _Deliveries({
    required this.pageKey,
    required this.canRedeliver,
    required this.onRedeliver,
    required this.onPage,
  });

  final ({String id, int offset}) pageKey;
  final bool canRedeliver;
  final ValueChanged<String> onRedeliver;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(webhookDeliveriesProvider(pageKey));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.settingsWebhookDetailDeliveriesError,
          style: AppTypography.caption.copyWith(color: AppColors.danger600),
        ),
      ),
      data: (page) {
        if (page.deliveries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.l10n.settingsWebhookDetailDeliveriesEmpty,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          );
        }
        final offset = pageKey.offset;
        return Column(
          children: [
            for (final d in page.deliveries)
              _DeliveryRow(
                delivery: d,
                onRedeliver: canRedeliver && d.canRedeliver
                    ? () => onRedeliver(d.id)
                    : null,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  if (offset > 0)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => onPage(
                        (offset - webhookDeliveryPageSize) < 0
                            ? 0
                            : offset - webhookDeliveryPageSize,
                      ),
                      child: Text(context.l10n.settingsWebhookDetailNewer),
                    ),
                  const Spacer(),
                  if (offset + webhookDeliveryPageSize < page.count)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: () => onPage(offset + webhookDeliveryPageSize),
                      child: Text(context.l10n.settingsWebhookDetailOlder),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.delivery, this.onRedeliver});

  final WebhookDelivery delivery;
  final VoidCallback? onRedeliver;

  @override
  Widget build(BuildContext context) {
    final color = switch (delivery.status) {
      WebhookDelivery.succeeded => AppColors.success600,
      WebhookDelivery.failed => AppColors.danger600,
      _ => AppColors.textSecondary,
    };
    final detail = [
      if (delivery.responseStatus != null) 'HTTP ${delivery.responseStatus}',
      if (delivery.error.isNotEmpty) delivery.error,
      context.l10n.settingsWebhookDetailTries(delivery.attempts),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.gray100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  delivery.event,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  delivery.statusLabel,
                  style: AppTypography.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onRedeliver != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onRedeliver,
              child: Text(context.l10n.settingsWebhookDetailRedeliver),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

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
