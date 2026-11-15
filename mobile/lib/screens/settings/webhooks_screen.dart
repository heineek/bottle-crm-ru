import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/webhook.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/org_modules_provider.dart';
import '../../providers/webhooks_provider.dart';
import '../../routes/app_router.dart';
import 'webhook_form_sheet.dart';

/// Outbound webhooks: the list, mirroring `/settings/webhooks` on the web.
///
/// **Admin-only to read.** Every `/api/webhooks/` route answers a member 403,
/// because a hook URL is often a credential of its own and every endpoint
/// receives copies of records. The screen gates on role rather than issuing a
/// request it knows will fail.
class WebhooksScreen extends ConsumerWidget {
  const WebhooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isOrgAdminProvider);
    final async = isAdmin ? ref.watch(webhooksProvider) : null;
    final canAdd = async?.value != null && !async!.value!.atLimit;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsWebhooksTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: !isAdmin ? const WebhooksMemberNotice() : const _AdminBody(),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () => _create(context, ref),
              icon: const Icon(LucideIcons.plus),
              label: Text(context.l10n.settingsWebhooksNewButton),
            )
          : null,
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final catalogue = ref.read(webhooksProvider).value?.catalogue ?? const [];
    final draft = await showWebhookFormSheet(context, catalogue: catalogue);
    if (draft == null || !context.mounted) return;
    final result = await ref.read(webhooksProvider.notifier).create(draft);
    if (!context.mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    if (result.secret != null) {
      await showWebhookSecret(
        context,
        title: context.l10n.settingsWebhooksCreatedTitle,
        secret: result.secret!,
      );
    }
  }
}

/// The one place a signing secret is shown. Nothing keeps a copy after the
/// dialog closes, and nothing logs it on the way here.
Future<void> showWebhookSecret(
  BuildContext context, {
  required String title,
  required String secret,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctx.l10n.settingsWebhooksSecretOnce,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                secret,
                style: AppTypography.caption.copyWith(
                  fontFamily: 'monospace',
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: secret));
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(content: Text(ctx.l10n.settingsWebhooksSecretCopied)),
            );
          },
          icon: const Icon(LucideIcons.copy, size: 16),
          label: Text(ctx.l10n.settingsWebhookCopy),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ctx.l10n.commonDone),
        ),
      ],
    ),
  );
}

class WebhooksMemberNotice extends StatelessWidget {
  const WebhooksMemberNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
              context.l10n.settingsWebhooksAdminsOnly,
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.settingsWebhooksMemberBody,
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

class _AdminBody extends ConsumerWidget {
  const _AdminBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(webhooksProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => WebhookErrorState(
        message: context.l10n.settingsWebhooksLoadError,
        onRetry: () => ref.read(webhooksProvider.notifier).refresh(),
      ),
      data: (state) => RefreshIndicator(
        onRefresh: () => ref.read(webhooksProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            if (state.endpoints.isEmpty)
              const _Empty()
            else
              for (final endpoint in state.endpoints)
                _EndpointRow(endpoint: endpoint),
            if (state.atLimit)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(
                  context.l10n.settingsWebhooksAtLimit(state.limit),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            const _Footnote(),
          ],
        ),
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.endpoint});

  final WebhookEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: () => context.push(AppRoutes.settingsWebhook(endpoint.id)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                      endpoint.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      endpoint.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${endpoint.formatLabel} · '
                      '${context.l10n.settingsWebhooksEventCount(endpoint.events.length)}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      context.l10n.settingsWebhooksBy(endpoint.creatorLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              WebhookStatePill(endpoint: endpoint),
            ],
          ),
        ),
      ),
    );
  }
}

class WebhookStatePill extends StatelessWidget {
  const WebhookStatePill({super.key, required this.endpoint});

  final WebhookEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    final (label, color) = endpoint.isActive
        ? (context.l10n.settingsWebhooksStateSending, AppColors.success600)
        : endpoint.disabledReason.isNotEmpty
        ? (context.l10n.settingsWebhooksStatePaused, AppColors.warning600)
        : (context.l10n.settingsWebhooksStateOff, AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Empty extends ConsumerWidget {
  const _Empty();

  /// "a lead, deal, ticket or other record", naming only modules that are on.
  static String changed(
    AppLocalizations l10n, {
    required bool leads,
    required bool deals,
    required bool tickets,
  }) {
    final kinds = [
      if (leads) l10n.settingsWebhooksKindLead,
      if (deals) l10n.settingsWebhooksKindDeal,
      if (tickets) l10n.settingsWebhooksKindTicket,
      l10n.settingsWebhooksKindOther,
    ];
    if (kinds.length == 1) return l10n.settingsWebhooksKindRecord;
    return l10n.settingsWebhooksKindsJoin(
      kinds.sublist(0, kinds.length - 1).join(', '),
      kinds.last,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kinds = changed(
      context.l10n,
      leads: ref.watch(moduleOnProvider('leads')),
      deals: ref.watch(moduleOnProvider('deals')),
      tickets: ref.watch(moduleOnProvider('tickets')),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
      child: Column(
        children: [
          Icon(LucideIcons.webhook, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 14),
          Text(
            context.l10n.settingsWebhooksEmptyTitle,
            style: AppTypography.h3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsWebhooksEmptyBody(kinds),
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Text(
        context.l10n.settingsWebhooksFootnote,
        style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

class WebhookErrorState extends StatelessWidget {
  const WebhookErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
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
              message,
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.settingsWebhookTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
