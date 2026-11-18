import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../config/api_config.dart';
import '../../core/theme/theme.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/custom_objects_provider.dart';
import '../../data/models/org_module.dart';
import '../../providers/org_modules_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/common/common.dart';

/// More/Settings Screen
/// User profile, app settings, and support options
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  @override
  void initState() {
    super.initState();
    // The first visit asks again after a failure. The shell keeps this screen
    // alive, so later visits ask from its branch switch instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      reloadOrgModulesIfIdle(ref);
      retryFailedCustomObjects(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsMoreTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Section
            _buildProfileSection(),

            // Workspace Section. Destinations that aren't on the bottom nav.
            _buildSectionHeader(context.l10n.settingsMoreSectionWorkspace),
            MenuRow(
              icon: LucideIcons.building2,
              label: context.l10n.settingsMoreAccounts,
              description: context.l10n.settingsMoreAccountsBody,
              onTap: () => context.push(AppRoutes.accounts),
            ),
            MenuRow(
              icon: LucideIcons.users,
              label: context.l10n.settingsMoreContacts,
              description: context.l10n.settingsMoreContactsBody,
              onTap: () => context.push(AppRoutes.contacts),
            ),
            MenuRow(
              icon: LucideIcons.bell,
              label: context.l10n.settingsMoreNotifications,
              description: context.l10n.settingsMoreNotificationsBody,
              onTap: () => context.push(AppRoutes.notifications),
            ),
            for (final key in _workspaceModuleKeys(
              ref.watch(shownModulesProvider),
            ))
              _moduleRow(key),

            Consumer(
              builder: (context, ref, _) {
                final answer = shownCustomObjects(
                  ref.watch(customObjectsProvider),
                );
                final objects = [
                  for (final o in answer?.objects ?? const [])
                    if (o.isActive) o,
                ];
                if (objects.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      context.l10n.settingsMoreSectionObjects,
                    ),
                    for (final o in objects)
                      MenuRow(
                        icon: LucideIcons.boxes,
                        label: o.labelPlural,
                        onTap: () =>
                            context.push(AppRoutes.objectRecords(o.key)),
                      ),
                  ],
                );
              },
            ),

            // Account Section
            _buildSectionHeader(context.l10n.settingsMoreSectionAccount),
            MenuRow(
              icon: LucideIcons.user,
              label: context.l10n.settingsMoreProfileSettings,
              onTap: () => context.push(AppRoutes.profile),
            ),
            // Only worth showing to someone who has somewhere to switch to.
            // The picker and `switchOrganization` both already existed and
            // worked; nothing in the app reached them once an org was chosen,
            // so the only way to change org was to sign out.
            if ((ref.watch(authProvider).organizations?.length ?? 0) > 1)
              MenuRow(
                icon: LucideIcons.building2,
                label: context.l10n.settingsMoreSwitchOrganization,
                description: ref.watch(selectedOrgProvider)?.name,
                onTap: () => context.push(AppRoutes.orgSelection),
              ),

            // Team Section
            _buildSectionHeader(context.l10n.settingsMoreSectionTeam),
            MenuRow(
              icon: LucideIcons.users,
              label: context.l10n.settingsMoreTeam,
              description: context.l10n.settingsMoreTeamBody,
              onTap: () => context.push(AppRoutes.team),
            ),
            // Not admin-gated, matching the web sidebar and the API: the
            // settings reads are open to any member and only the writes are
            // admin-only. Team above is the opposite and is genuinely
            // admin-only, which is why the two sit in separate rows rather
            // than one "Administration" block.
            MenuRow(
              icon: LucideIcons.slidersHorizontal,
              label: context.l10n.settingsMoreOrgSettings,
              description: context.l10n.settingsMoreOrgSettingsBody,
              onTap: () => context.push(AppRoutes.settings),
            ),

            // Preferences used to be a section here, holding a Dark Mode
            // switch that repainted nothing and then announced "Dark mode
            // enabled", and a Language picker offering three languages the app
            // has never had a single string in. Both are gone rather than
            // relabelled: honouring the theme is a repaint of 1,472 hardcoded
            // colour references, and there is no localisation to select.

            // Support Section
            _buildSectionHeader(context.l10n.settingsMoreSectionSupport),
            MenuRow(
              icon: LucideIcons.lifeBuoy,
              label: context.l10n.settingsMoreContactSupport,
              description: context.l10n.settingsMoreContactSupportBody,
              onTap: () => context.push(AppRoutes.help),
            ),
            MenuRow(
              icon: LucideIcons.helpCircle,
              label: context.l10n.settingsMoreHelpCenter,
              onTap: () =>
                  _openOnTheWeb('/docs', context.l10n.settingsMoreHelpCenter),
            ),
            MenuRow(
              icon: LucideIcons.fileText,
              label: context.l10n.settingsMoreTerms,
              onTap: () => _openOnTheWeb(
                '/terms-of-service',
                context.l10n.settingsMoreTerms,
              ),
            ),
            MenuRow(
              icon: LucideIcons.shield,
              label: context.l10n.settingsMorePrivacy,
              onTap: () => _openOnTheWeb(
                '/privacy-policy',
                context.l10n.settingsMorePrivacy,
              ),
            ),

            // Sign Out Button
            const SizedBox(height: 24),
            _buildSignOutButton(),

            // Version Info
            const SizedBox(height: 24),
            Center(
              child: Text(
                context.l10n.settingsMoreVersion('1.0.0'),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  /// The module rows in the org's order; a module the answer has no row for
  /// reads as on and follows in the default order.
  List<String> _workspaceModuleKeys(OrgModulesAnswer? answer) {
    const known = [
      'tasks',
      'goals',
      'knowledge_base',
      'documents',
      'projects',
      'invoices',
      'timesheet',
    ];
    final ordered = <String>[
      if (answer != null)
        for (final m in answer.modules)
          if (known.contains(m.key)) m.key,
    ];
    return [
      for (final key in [
        ...ordered,
        for (final k in known)
          if (!ordered.contains(k)) k,
      ])
        if (answer == null || answer.isOn(key)) key,
    ];
  }

  Widget _moduleRow(String key) => switch (key) {
    'tasks' => MenuRow(
      icon: LucideIcons.checkSquare,
      label: context.l10n.settingsMoreTasks,
      description: context.l10n.settingsMoreTasksBody,
      onTap: () => context.go(AppRoutes.tasks),
    ),
    // Not admin-gated. The list is open to any member and the API narrows it
    // to the goals set for them and their teams; creating and editing are
    // admin-only and live behind the screen.
    'goals' => MenuRow(
      icon: LucideIcons.target,
      label: context.l10n.settingsMoreGoals,
      description: context.l10n.settingsMoreGoalsBody,
      onTap: () => context.push(AppRoutes.goals),
    ),
    'knowledge_base' => MenuRow(
      icon: LucideIcons.bookOpen,
      label: context.l10n.settingsMoreKnowledgeBase,
      description: context.l10n.settingsMoreKnowledgeBaseBody,
      onTap: () => context.push(AppRoutes.solutions),
    ),
    'documents' => MenuRow(
      icon: LucideIcons.folder,
      label: context.l10n.settingsMoreDocuments,
      description: context.l10n.settingsMoreDocumentsBody,
      onTap: () => context.push(AppRoutes.documents),
    ),
    'projects' => MenuRow(
      icon: LucideIcons.folderKanban,
      label: context.l10n.settingsMoreProjects,
      description: context.l10n.settingsMoreProjectsBody,
      onTap: () => context.push(AppRoutes.projects),
    ),
    'invoices' => MenuRow(
      icon: LucideIcons.receipt,
      label: context.l10n.settingsMoreInvoices,
      description: context.l10n.settingsMoreInvoicesBody,
      onTap: () => context.push(AppRoutes.invoices),
    ),
    _ => MenuRow(
      icon: LucideIcons.clock,
      label: context.l10n.settingsMoreTimesheet,
      description: context.l10n.settingsMoreTimesheetBody,
      onTap: () => context.push(AppRoutes.timesheet),
    ),
  };

  Widget _buildProfileSection() {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final org = authState.selectedOrganization;
    final displayName =
        user?.displayName ?? context.l10n.settingsMoreSignedInUser;
    final email = user?.email ?? '';
    final role = org?.role ?? org?.name;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.profile),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary50,
              AppColors.primary100.withValues(alpha: 0.5),
            ],
          ),
        ),
        child: Row(
          children: [
            UserAvatar(
              name: displayName,
              imageUrl: user?.profilePic,
              size: AvatarSize.xl,
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: AppTypography.h2.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (role != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      role,
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            Icon(
              LucideIcons.chevronRight,
              size: 22,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
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

  Widget _buildSignOutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton(
        onPressed: () => _handleSignOut(),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.danger200),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.logOut, size: 20, color: AppColors.danger600),
            const SizedBox(width: 10),
            Text(
              context.l10n.settingsMoreSignOut,
              style: AppTypography.button.copyWith(color: AppColors.danger600),
            ),
          ],
        ),
      ),
    );
  }

  /// Open a page on the marketing site, which is where these documents live.
  /// They were "coming soon" dialogs while the real pages were already
  /// published.
  Future<void> _openOnTheWeb(String path, String label) async {
    final uri = Uri.parse('${ApiConfig.marketingSite}$path');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.settingsMoreCouldNotOpen(label)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleSignOut() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.settingsMoreSignOut),
        content: Text(context.l10n.settingsMoreSignOutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              // Sign out using auth provider
              await ref.read(authProvider.notifier).signOut();

              if (mounted) {
                context.go(AppRoutes.login);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(context.l10n.settingsMoreSignedOut),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text(
              context.l10n.settingsMoreSignOut,
              style: TextStyle(color: AppColors.danger600),
            ),
          ),
        ],
      ),
    );
  }
}
