import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/invoice_template.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/invoice_extras_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/common/badge.dart';
import 'invoice_shell.dart';
import 'invoice_template_form_screen.dart' show swatchColor;

/// PDF templates: the catalogue, and the writes an admin can make from a phone.
///
/// Reading is open to every member, since knowing which template an invoice
/// will print in is useful to whoever raised it. Creating, editing and
/// re-pointing the default are admin-only, which the API enforces
/// (`_forbid_non_admin_template`); the controls below are hidden from everyone
/// else as a courtesy, not as the check.
///
/// **The layout itself is still edited on the web.** A template's body is
/// org-authored HTML and CSS that WeasyPrint renders server-side, it never
/// leaves the admin-only editor route, and a two-pane markup editor is not a
/// 390px screen. Everything else about a template is ordinary form input, so
/// that is what the form screen owns, and a save from here leaves the markup
/// untouched.
class InvoiceTemplatesScreen extends ConsumerWidget {
  const InvoiceTemplatesScreen({super.key});

  Future<void> _setDefault(
    BuildContext context,
    WidgetRef ref,
    InvoiceTemplate template,
  ) async {
    final error = await ref
        .read(invoiceTemplatesProvider.notifier)
        .setDefault(template.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? context.l10n.invoicesTemplatesDefaultSnack(template.name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(invoiceTemplatesProvider);
    final isAdmin = ref.watch(isOrgAdminProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.invoicesTemplatesTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: context.l10n.invoicesTemplatesNewTooltip,
              onPressed: () => context.push(AppRoutes.invoiceTemplateNew),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => InvoiceErrorState(
          message: context.l10n.invoicesTemplatesLoadError,
          onRetry: () => ref.read(invoiceTemplatesProvider.notifier).refresh(),
        ),
        data: (templates) {
          if (templates.isEmpty) {
            return InvoiceEmptyState(
              icon: LucideIcons.layoutTemplate,
              message: context.l10n.invoicesTemplatesEmpty,
              detail: isAdmin
                  ? context.l10n.invoicesTemplatesEmptyAdmin
                  : context.l10n.invoicesTemplatesEmptyMember,
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(invoiceTemplatesProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final t in templates)
                  _TemplateCard(
                    template: t,
                    canManage: isAdmin,
                    onEdit: () =>
                        context.push(AppRoutes.invoiceTemplateEditFor(t.id)),
                    onSetDefault: () => _setDefault(context, ref, t),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    context.l10n.invoicesTemplatesWebNote,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.canManage,
    required this.onEdit,
    required this.onSetDefault,
  });

  final InvoiceTemplate template;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final primary = swatchColor(template.primaryColor);

    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (primary != null) ...[
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.gray200),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (canManage)
                IconButton(
                  icon: const Icon(LucideIcons.pencil, size: 18),
                  tooltip: context.l10n.invoicesTemplatesEditTooltip,
                  onPressed: onEdit,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (template.isDefault)
                StatusBadge(
                  label: context.l10n.invoicesTemplatesDefault,
                  color: AppColors.success600,
                ),
              if (template.hasLogo)
                Text(
                  context.l10n.invoicesTemplatesLogo,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              // Whether custom markup exists, never what it says.
              if (template.hasCustomHtml)
                Text(
                  context.l10n.invoicesTemplatesCustomLayout,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              Text(
                template.usedOnInvoices == 0
                    ? context.l10n.invoicesTemplatesUnused
                    : context.l10n.invoicesProductUsedOn(
                        template.usedOnInvoices,
                      ),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          // Making a template the default is a swap, not a toggle: the model
          // clears the flag on every other row in one transaction. So the one
          // already holding it gets no control, because there is nothing to
          // offer that would not leave the org without a default.
          if (canManage && !template.isDefault) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: onSetDefault,
                child: Text(context.l10n.invoicesTemplatesUseForNew),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
