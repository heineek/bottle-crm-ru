import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/automation_provider.dart';
import '../../providers/custom_objects_provider.dart';
import '../../providers/org_apps_provider.dart';
import '../../providers/org_modules_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/common/common.dart';

/// The launcher for the org settings cluster, mirroring `/settings` on the web.
///
/// **Not admin-gated, on purpose.** The reads underneath it are open to any
/// member: `CustomFieldDefinitionListCreateView.get` carries only
/// `IsAuthenticated, HasOrgContext`, and the admin check sits on POST, PUT and
/// DELETE. The web's sidebar says the same in as many words ("the hub is
/// readable by any member"). Gating the read here would hide from a member the
/// definitions that shape the forms they fill in every day, and would be this
/// app disagreeing with the API about who may look.
///
/// Each page hides its own write controls from a non-admin, which is UX rather
/// than a guard: the server answers 403 either way.
///
/// Every settings page the web has is here. Two of the reads underneath are
/// admin-only server-side and say so on arrival rather than here: the reopen
/// policy and the org-wide token list.
class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsHubTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(context.l10n.settingsHubSectionRecords),
            MenuRow(
              icon: LucideIcons.listPlus,
              label: context.l10n.settingsHubCustomFields,
              description: context.l10n.settingsHubCustomFieldsBody,
              onTap: () => context.push(AppRoutes.settingsCustomFields),
            ),
            Consumer(
              builder: (context, ref, _) {
                final answer = shownCustomObjects(
                  ref.watch(customObjectsProvider),
                );
                final show =
                    answer != null &&
                    answer.offered &&
                    (ref.watch(isOrgAdminProvider) ||
                        answer.objects.isNotEmpty);
                if (!show) return const SizedBox.shrink();
                return MenuRow(
                  icon: LucideIcons.boxes,
                  label: context.l10n.settingsHubObjects,
                  description: context.l10n.settingsHubObjectsBody,
                  onTap: () => context.push(AppRoutes.settingsObjects),
                );
              },
            ),
            MenuRow(
              icon: LucideIcons.tags,
              label: context.l10n.settingsHubTags,
              description: context.l10n.settingsHubTagsBody,
              onTap: () => context.push(AppRoutes.settingsTags),
            ),
            _ModuleGate(
              module: 'leads',
              child: MenuRow(
                icon: LucideIcons.squareKanban,
                label: context.l10n.settingsHubLeadPipelines,
                description: context.l10n.settingsHubLeadPipelinesBody,
                onTap: () => context.push(AppRoutes.settingsLeadPipelines),
              ),
            ),
            // Not gated on Leads: deals pick from the same list.
            MenuRow(
              icon: LucideIcons.compass,
              label: context.l10n.settingsHubLeadSources,
              description: context.l10n.settingsHubLeadSourcesBody,
              onTap: () => context.push(AppRoutes.settingsLeadSources),
            ),
            _ModuleGate(
              module: 'deals',
              child: MenuRow(
                icon: LucideIcons.chartNoAxesColumn,
                label: context.l10n.settingsHubDealPipelines,
                description: context.l10n.settingsHubDealPipelinesBody,
                onTap: () => context.push(AppRoutes.settingsDealPipelines),
              ),
            ),
            Consumer(
              builder: (context, ref, _) => ref.watch(productsOnProvider)
                  ? MenuRow(
                      icon: LucideIcons.package,
                      label: context.l10n.settingsHubProducts,
                      description: context.l10n.settingsHubProductsBody,
                      onTap: () => context.push(AppRoutes.products),
                    )
                  : const SizedBox.shrink(),
            ),
            _ModuleGate(
              module: 'tickets',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(context.l10n.settingsHubSectionTickets),
                  MenuRow(
                    icon: LucideIcons.gitBranch,
                    label: context.l10n.settingsHubRouting,
                    description: context.l10n.settingsHubRoutingBody,
                    onTap: () => context.push(AppRoutes.settingsRouting),
                  ),
                  MenuRow(
                    icon: LucideIcons.bellOff,
                    label: context.l10n.settingsHubEscalation,
                    description: context.l10n.settingsHubEscalationBody,
                    onTap: () => context.push(AppRoutes.settingsEscalation),
                  ),
                  MenuRow(
                    icon: LucideIcons.clock,
                    label: context.l10n.settingsHubBusinessHours,
                    description: context.l10n.settingsHubBusinessHoursBody,
                    onTap: () => context.push(AppRoutes.settingsBusinessHours),
                  ),
                  MenuRow(
                    icon: LucideIcons.rotateCcw,
                    label: context.l10n.settingsHubReopen,
                    description: context.l10n.settingsHubReopenBody,
                    onTap: () => context.push(AppRoutes.settingsReopen),
                  ),
                  MenuRow(
                    icon: LucideIcons.messageSquareQuote,
                    label: context.l10n.settingsHubSavedReplies,
                    description: context.l10n.settingsHubSavedRepliesBody,
                    onTap: () => context.push(AppRoutes.settingsMacros),
                  ),
                  MenuRow(
                    icon: LucideIcons.mail,
                    label: context.l10n.settingsHubInboundEmail,
                    description: context.l10n.settingsHubInboundEmailBody,
                    onTap: () => context.push(AppRoutes.settingsInboundEmail),
                  ),
                  MenuRow(
                    icon: LucideIcons.circleCheckBig,
                    label: context.l10n.settingsHubApprovals,
                    description: context.l10n.settingsHubApprovalsBody,
                    onTap: () =>
                        context.push(AppRoutes.settingsTicketApprovals),
                  ),
                ],
              ),
            ),
            _SectionHeader(context.l10n.settingsHubSectionOrganization),
            MenuRow(
              icon: LucideIcons.building2,
              label: context.l10n.settingsHubOrganization,
              description: context.l10n.settingsHubOrganizationBody,
              onTap: () => context.push(AppRoutes.settingsOrganization),
            ),
            // Named for what the server offers: an API without industry apps
            // (a 404) still has the modules page under its old name.
            Consumer(
              builder: (context, ref, _) {
                if (!ref.watch(isOrgAdminProvider)) {
                  return const SizedBox.shrink();
                }
                final apps = ref.watch(shownAppsProvider) != null;
                if (!apps && ref.watch(shownModulesProvider) == null) {
                  return const SizedBox.shrink();
                }
                return MenuRow(
                  icon: LucideIcons.layoutGrid,
                  label: apps
                      ? context.l10n.settingsHubApps
                      : context.l10n.settingsHubModules,
                  description: apps
                      ? context.l10n.settingsHubAppsBody
                      : context.l10n.settingsHubModulesBody,
                  onTap: () => context.push(AppRoutes.settingsApps),
                );
              },
            ),
            MenuRow(
              icon: LucideIcons.keyRound,
              label: context.l10n.settingsHubApiTokens,
              description: context.l10n.settingsHubApiTokensBody,
              onTap: () => context.push(AppRoutes.settingsApiTokens),
            ),
            // Admins only, as on the web: every webhooks route answers a
            // member 403, reads included. The role is a display hint; the API
            // is the gate.
            Consumer(
              builder: (context, ref, _) => ref.watch(isOrgAdminProvider)
                  ? MenuRow(
                      icon: LucideIcons.webhook,
                      label: context.l10n.settingsHubWebhooks,
                      description: context.l10n.settingsHubWebhooksBody,
                      onTap: () => context.push(AppRoutes.settingsWebhooks),
                    )
                  : const SizedBox.shrink(),
            ),
            Consumer(
              builder: (context, ref, _) {
                // Members never ask: the rules answer them 403.
                if (!ref.watch(isOrgAdminProvider) ||
                    automationNotOffered(ref.watch(automationRulesProvider))) {
                  return const SizedBox.shrink();
                }
                return MenuRow(
                  icon: LucideIcons.zap,
                  label: context.l10n.settingsHubAutomation,
                  description: context.l10n.settingsHubAutomationBody,
                  onTap: () => context.push(AppRoutes.settingsAutomation),
                );
              },
            ),
            // Admins only, as on the web: the audit log answers a member 403.
            Consumer(
              builder: (context, ref, _) => ref.watch(isOrgAdminProvider)
                  ? MenuRow(
                      icon: LucideIcons.scrollText,
                      label: context.l10n.settingsHubAuditLog,
                      description: context.l10n.settingsHubAuditLogBody,
                      onTap: () => context.push(AppRoutes.settingsAuditLog),
                    )
                  : const SizedBox.shrink(),
            ),
            // Beside web forms, which it also lists: each is a way in for
            // someone with no account.
            _ModuleGate(
              module: 'leads',
              child: MenuRow(
                icon: LucideIcons.inbox,
                label: context.l10n.settingsHubLeadCapture,
                description: context.l10n.settingsHubLeadCaptureBody,
                onTap: () => context.push(AppRoutes.settingsLeadCapture),
              ),
            ),
            // Filed with the organization cluster rather than with records,
            // beside API tokens. What a published form grants is the ability
            // for a stranger with no account to write into this org, which is
            // an access question; that it arrives as a lead is the smaller
            // half.
            MenuRow(
              icon: LucideIcons.clipboardList,
              label: context.l10n.settingsHubWebForms,
              description: context.l10n.settingsHubWebFormsBody,
              onTap: () => context.push(AppRoutes.settingsWebForms),
            ),
            // Beside web forms for the same reason: it is what a stranger with
            // no account can reach. The public pages are web-only; this is the
            // switch and the address.
            _ModuleGate(
              module: 'knowledge_base',
              child: MenuRow(
                icon: LucideIcons.globe,
                label: context.l10n.settingsHubHelpCenter,
                description: context.l10n.settingsHubHelpCenterBody,
                onTap: () => context.push(AppRoutes.settingsHelpCenter),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
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

/// Shows its child while the module is on.
class _ModuleGate extends ConsumerWidget {
  const _ModuleGate({required this.module, required this.child});

  final String module;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(moduleOnProvider(module)) ? child : const SizedBox.shrink();
}
