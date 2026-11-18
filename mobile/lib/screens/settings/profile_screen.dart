import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/l10n.dart';
import '../../providers/language_provider.dart';
import '../../core/theme/theme.dart';
import '../../data/models/profile.dart';
import '../../providers/org_modules_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/settings_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/common/common.dart';
import '../../widgets/common/push_prompt.dart';
import '../../widgets/forms/unsaved_changes.dart';

/// Profile view/edit screen.
///
/// API contract: PATCH /api/profile/ accepts `name` (on User) and `phone`
/// (on Profile). Everything else is read-only by API design.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _editing = false;
  bool _saving = false;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _enterEdit(Profile profile) {
    _nameController.text = profile.user.name ?? '';
    _phoneController.text = profile.phone ?? '';
    setState(() => _editing = true);
  }

  /// Only counts while the fields are actually on screen. Outside edit mode
  /// the controllers still hold whatever was last typed, and prompting about
  /// that on the way out would be nonsense.
  bool get _hasUnsavedChanges {
    if (!_editing) return false;
    final profile = ref.read(profileProvider).value;
    if (profile == null) return false;
    return _nameController.text.trim() != (profile.user.name ?? '') ||
        _phoneController.text.trim() != (profile.phone ?? '');
  }

  void _cancelEdit() {
    FocusScope.of(context).unfocus();
    setState(() => _editing = false);
  }

  Future<void> _save(Profile current) async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final nameChanged = name != (current.user.name ?? '');
    final phoneChanged = phone != (current.phone ?? '');
    if (!nameChanged && !phoneChanged) {
      _cancelEdit();
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final ok = await ref
        .read(profileProvider.notifier)
        .save(
          name: nameChanged ? name : null,
          phone: phoneChanged ? phone : null,
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) _editing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.l10n.settingsProfileUpdated
              : context.l10n.settingsProfileUpdateFailed,
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ok ? AppColors.success600 : AppColors.danger600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(profileProvider);
    return UnsavedChangesGuard(
      hasUnsavedChanges: () => _hasUnsavedChanges,
      isSaving: _saving,
      child: Scaffold(
        backgroundColor: AppColors.surfaceDim,
        appBar: AppBar(
          title: Text(context.l10n.settingsProfileTitle),
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: _saving
                ? null
                : () =>
                      leaveForm(context, hasUnsavedChanges: _hasUnsavedChanges),
          ),
          actions: [
            if (async.value != null && !_editing)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  onPressed: () => _enterEdit(async.value!),
                  icon: const Icon(LucideIcons.edit3, size: 20),
                  tooltip: context.l10n.settingsProfileEditProfile,
                  color: AppColors.primary600,
                ),
              ),
          ],
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _buildError(e),
          data: (profile) => _buildBody(profile),
        ),
      ),
    );
  }

  Widget _buildError(Object e) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 40, color: AppColors.gray400),
          const SizedBox(height: 12),
          Text(
            context.l10n.settingsProfileLoadFailed,
            style: AppTypography.label,
          ),
          const SizedBox(height: 4),
          Text(
            '$e',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => ref.read(profileProvider.notifier).refresh(),
            child: Text(context.l10n.commonRetry),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(Profile profile) {
    return RefreshIndicator(
      onRefresh: () => ref.read(profileProvider.notifier).refresh(),
      child: ListView(
        children: [
          _buildHeader(profile),
          const SizedBox(height: 16),
          if (_editing) _buildEditForm(profile) else _buildReadOnly(profile),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(Profile profile) {
    final displayName = profile.user.name?.trim().isNotEmpty == true
        ? profile.user.name!
        : profile.user.displayName;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
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
      child: Column(
        children: [
          UserAvatar(
            name: displayName,
            imageUrl: profile.user.profilePic,
            size: AvatarSize.xxl,
          ),
          const SizedBox(height: 14),
          Text(
            displayName,
            style: AppTypography.h2,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            profile.user.email,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (profile.role != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                profile.role!,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.primary700,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
          if (!_editing) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _enterEdit(profile),
              icon: const Icon(LucideIcons.edit3, size: 16),
              label: Text(context.l10n.settingsProfileEditProfile),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary700,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: AppColors.primary200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadOnly(Profile profile) {
    final workLinks = [
      'goals',
      'timesheet',
      'tasks',
    ].any((key) => ref.watch(moduleOnProvider(key)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context.l10n.settingsProfileSectionPersonal),
        _InfoRow(
          icon: LucideIcons.user,
          label: context.l10n.commonName,
          value: profile.user.name?.trim().isNotEmpty == true
              ? profile.user.name!
              : '—',
        ),
        _InfoRow(
          icon: LucideIcons.mail,
          label: context.l10n.commonEmail,
          value: profile.user.email,
        ),
        _InfoRow(
          icon: LucideIcons.phone,
          label: context.l10n.commonPhone,
          value: profile.phone?.trim().isNotEmpty == true
              ? profile.phone!
              : '—',
        ),
        _sectionHeader(context.l10n.settingsProfileSectionOrganization),
        if (profile.org != null)
          _InfoRow(
            icon: LucideIcons.building2,
            label: context.l10n.settingsProfileOrganization,
            value: profile.org!.name,
          ),
        if (profile.role != null)
          _InfoRow(
            icon: LucideIcons.shield,
            label: context.l10n.settingsProfileRole,
            value: profile.role!,
          ),
        if (profile.dateOfJoining != null)
          _InfoRow(
            icon: LucideIcons.calendar,
            label: context.l10n.settingsProfileJoined,
            value: DateFormat.yMMMMd().format(profile.dateOfJoining!),
          ),
        // The web profile page shows these two; this screen did not, so the
        // same person read differently depending on which client they opened.
        _InfoRow(
          icon: LucideIcons.users,
          label: context.l10n.settingsProfileTeams,
          value: profile.teams.isEmpty
              ? context.l10n.settingsProfileTeamsNone
              : profile.teams.join(', '),
        ),
        _InfoRow(
          icon: LucideIcons.logIn,
          label: context.l10n.settingsProfileLastSignedIn,
          value: profile.lastLogin == null
              ? context.l10n.settingsProfileNotRecorded
              : DateFormat.yMMMMd().add_jm().format(
                  profile.lastLogin!.toLocal(),
                ),
        ),
        _sectionHeader(context.l10n.settingsProfileSectionAccess),
        _InfoRow(
          icon: LucideIcons.target,
          label: context.l10n.settingsProfileSales,
          value: profile.hasSalesAccess
              ? context.l10n.settingsProfileEnabled
              : context.l10n.settingsProfileDisabled,
        ),
        _InfoRow(
          icon: LucideIcons.megaphone,
          label: context.l10n.settingsProfileMarketing,
          value: profile.hasMarketingAccess
              ? context.l10n.settingsProfileEnabled
              : context.l10n.settingsProfileDisabled,
        ),
        _sectionHeader(context.l10n.settingsProfileSectionAlerts),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: profile.leadAlertsEmail,
          onChanged: (v) => _setAlerts(email: v),
          title: Text(context.l10n.settingsProfileLeadAlertsEmail),
          subtitle: Text(
            context.l10n.settingsProfileLeadAlertsEmailBody,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: profile.leadAlertsPush,
          onChanged: (v) => _setAlerts(push: v),
          title: Text(context.l10n.settingsProfileLeadAlertsPush),
          subtitle: Text(
            context.l10n.settingsProfileLeadAlertsPushBody,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        _sectionHeader(context.l10n.settingsProfileSectionYourAccount),
        // Your OWN tokens, not the settings screen: that one is the admin's
        // org-wide oversight list and answers a member 403.
        _LinkRow(
          icon: LucideIcons.keyRound,
          label: context.l10n.settingsProfileApiTokens,
          detail: context.l10n.settingsProfileApiTokensDetail,
          trailing: _tokenCount(),
          onTap: () => context.push(AppRoutes.profileTokens),
        ),
        _LinkRow(
          icon: LucideIcons.languages,
          label: context.l10n.profileLanguageRow,
          detail: lookupAppLocalizations(
            Locale(ref.watch(languageProvider)),
          ).languageName,
          onTap: () => context.push(AppRoutes.profileLanguage),
        ),
        if (ref.watch(moduleOnProvider('tasks')))
          _LinkRow(
            icon: LucideIcons.calendarDays,
            label: context.l10n.settingsProfileCalendarFeed,
            detail: context.l10n.settingsProfileCalendarFeedDetail,
            onTap: () => context.push(AppRoutes.profileCalendarFeed),
          ),
        if (workLinks) _sectionHeader(context.l10n.settingsProfileSectionWork),
        if (ref.watch(moduleOnProvider('goals')))
          _LinkRow(
            icon: LucideIcons.target,
            label: context.l10n.settingsProfileGoals,
            detail: context.l10n.settingsProfileGoalsDetail,
            onTap: () => context.push(AppRoutes.goals),
          ),
        if (ref.watch(moduleOnProvider('timesheet')))
          _LinkRow(
            icon: LucideIcons.clock,
            label: context.l10n.settingsProfileTimesheet,
            detail: context.l10n.settingsProfileTimesheetDetail,
            onTap: () => context.push(AppRoutes.timesheet),
          ),
        if (ref.watch(moduleOnProvider('tasks')))
          _LinkRow(
            icon: LucideIcons.circleCheck,
            label: context.l10n.settingsProfileTasks,
            detail: context.l10n.settingsProfileTasksDetail,
            onTap: () => context.push(AppRoutes.tasks),
          ),
      ],
    );
  }

  Future<void> _setAlerts({bool? email, bool? push}) async {
    final ok = await ref
        .read(profileProvider.notifier)
        .setLeadAlerts(email: email, push: push);
    if (ok && push == true) await requestPushPermission();
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.settingsProfileAlertsFailed),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// How many of your tokens are live, or null while it is still loading.
  ///
  /// Read from the same self-scoped provider the tokens screen uses, so
  /// opening one warms the other rather than asking twice.
  String? _tokenCount() {
    final tokens = ref.watch(myAccessTokensProvider).value;
    if (tokens == null) return null;
    return '${tokens.where((t) => t.isLive).length}';
  }

  Widget _buildEditForm(Profile profile) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context.l10n.settingsProfileSectionEditable,
            padding: false,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsProfileEditableHint,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            maxLength: 255,
            decoration: InputDecoration(
              labelText: context.l10n.settingsProfileFullName,
              border: const OutlineInputBorder(),
              counterText: '',
              prefixIcon: const Icon(LucideIcons.user, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: context.l10n.commonPhone,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(LucideIcons.phone, size: 18),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _cancelEdit,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(context.l10n.commonCancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(profile),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.gray900,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(context.l10n.settingsProfileSaveChanges),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {bool padding = true}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padding ? 16 : 0, 16, 16, 6),
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

/// A row that goes somewhere. Same shape as `_InfoRow` so the list reads as
/// one thing, with a 56px minimum height because it is a tap target and the
/// info rows around it are not.
class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String detail;
  final String? trailing;
  final VoidCallback onTap;

  const _LinkRow({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.gray100)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w500,
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
              if (trailing != null) ...[
                Text(
                  trailing!,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.gray100)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
