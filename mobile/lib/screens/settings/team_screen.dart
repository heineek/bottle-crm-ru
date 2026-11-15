import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../l10n/l10n.dart';
import '../../data/models/team_member.dart';
import '../../providers/profile_provider.dart';
import '../../providers/team_provider.dart';
import '../../widgets/common/common.dart';

/// Team and access: who is in the org, who is an admin, who has been
/// deactivated.
///
/// Every rule here is the server's. `/api/users/` and `/api/user/<id>/` are
/// admin-only and answer 403 to anyone else, they refuse a self-role-change,
/// and they refuse to strip or deactivate the last active admin. This screen
/// hides the controls that would hit those refusals, which is a courtesy so
/// the user is not told "no" after tapping. It is not the boundary: an
/// attacker skipping this UI meets exactly the same three refusals.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final teamAsync = ref.watch(teamProvider);
    // Your own profile id, so your row can withhold the two controls the
    // server refuses on yourself: it answers 400 to a self role change, and
    // deactivating yourself from your own phone is a lockout with no undo.
    // Profile id against profile id, never against the User id: they are
    // different tables and comparing across them silently never matches.
    final myProfileId = ref.watch(profileProvider).value?.id;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.settingsTeamTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      floatingActionButton: teamAsync.value?.forbidden == false
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : _showInviteSheet,
              icon: const Icon(LucideIcons.userPlus, size: 18),
              label: Text(context.l10n.settingsTeamInvite),
            )
          : null,
      body: teamAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: '$error',
          onRetry: () => ref.read(teamProvider.notifier).refresh(),
        ),
        data: (data) =>
            data.forbidden ? const _AdminsOnly() : _body(data, myProfileId),
      ),
    );
  }

  Widget _body(TeamListData data, String? myProfileId) {
    return RefreshIndicator(
      onRefresh: () => ref.read(teamProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _summary(data),
          _header(context.l10n.settingsTeamActiveHeader, data.active.length),
          if (data.active.isEmpty)
            _EmptyRow(text: context.l10n.settingsTeamNobodyActive),
          ...data.active.map((m) => _memberRow(m, data, myProfileId)),
          if (data.inactive.isNotEmpty) ...[
            _header(
              context.l10n.settingsTeamDeactivatedHeader,
              data.inactive.length,
            ),
            ...data.inactive.map((m) => _memberRow(m, data, myProfileId)),
          ],
        ],
      ),
    );
  }

  Widget _summary(TeamListData data) {
    // A live token on a deactivated account is the one number here worth
    // acting on: the login is gone, the token still authenticates.
    final orphanTokens = data.tokensOnDeactivated;
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: orphanTokens > 0 ? AppColors.warning50 : AppColors.surface,
        borderRadius: AppLayout.borderRadiusMd,
        border: Border.all(
          color: orphanTokens > 0 ? AppColors.warning200 : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _stat('${data.active.length}', l10n.settingsTeamStatActive),
              _stat('${data.adminCount}', l10n.settingsTeamStatAdmin),
              if (data.neverSignedInCount > 0)
                _stat(
                  '${data.neverSignedInCount}',
                  l10n.settingsTeamStatNeverSignedIn,
                ),
              if (data.inactive.isNotEmpty)
                _stat(
                  '${data.inactive.length}',
                  l10n.settingsTeamStatDeactivated,
                ),
            ],
          ),
          if (orphanTokens > 0) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.keyRound,
                  size: 14,
                  color: AppColors.warning700,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.settingsTeamOrphanTokens(orphanTokens),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _header(String title, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        '${title.toUpperCase()} ($count)',
        style: AppTypography.overline.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _memberRow(TeamMember member, TeamListData data, String? myProfileId) {
    // The server refuses to demote or deactivate the last admin, so the row
    // offers neither rather than offering a tap that ends in an error.
    final isLastAdmin = data.lastAdmin?.userId == member.userId;
    final isYou = myProfileId != null && member.id == myProfileId;
    final subtitle = [
      if (member.email.isNotEmpty && member.email != member.name) member.email,
      if (member.hasNeverSignedIn) context.l10n.settingsTeamNeverSignedIn,
      if (member.activeTokenCount > 0)
        context.l10n.settingsTeamMemberTokens(member.activeTokenCount),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.gray100)),
      ),
      child: Row(
        children: [
          UserAvatar(name: member.name, size: AvatarSize.md),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _RolePill(role: member.role),
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
          IconButton(
            icon: Icon(
              LucideIcons.ellipsisVertical,
              size: 18,
              color: AppColors.textSecondary,
            ),
            onPressed: _busy
                ? null
                : () => _showActions(member, isLastAdmin, isYou),
          ),
        ],
      ),
    );
  }

  void _showActions(TeamMember member, bool isLastAdmin, bool isYou) {
    final nextRole = member.isAdmin ? 'USER' : 'ADMIN';
    final l10n = context.l10n;
    final withheld = isYou
        ? l10n.settingsTeamWithheldYou
        : isLastAdmin
        ? l10n.settingsTeamWithheldLastAdmin
        : null;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                isYou ? l10n.settingsTeamNameYou(member.name) : member.name,
                style: AppTypography.h3,
              ),
            ),
            if (withheld != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  withheld,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else ...[
              ListTile(
                leading: Icon(LucideIcons.shield, size: 20),
                title: Text(
                  nextRole == 'ADMIN'
                      ? l10n.settingsTeamMakeAdmin
                      : l10n.settingsTeamMakeMember,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _setRole(member, nextRole);
                },
              ),
              ListTile(
                leading: Icon(
                  member.isActive ? LucideIcons.userX : LucideIcons.userCheck,
                  size: 20,
                  color: member.isActive ? AppColors.danger600 : null,
                ),
                title: Text(
                  member.isActive
                      ? l10n.settingsTeamDeactivate
                      : l10n.settingsTeamReactivate,
                ),
                subtitle: member.isActive && member.activeTokenCount > 0
                    ? Text(l10n.settingsTeamTokensStop)
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _setActive(member, !member.isActive);
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _setRole(TeamMember member, String role) async {
    setState(() => _busy = true);
    final response = await ref
        .read(teamProvider.notifier)
        .setRole(userId: member.userId, role: role);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(
      response.success
          ? (role == 'ADMIN'
                ? context.l10n.settingsTeamNowAdmin(member.name)
                : context.l10n.settingsTeamNowMember(member.name))
          : response.message ?? context.l10n.settingsTeamRoleError,
    );
  }

  Future<void> _setActive(TeamMember member, bool isActive) async {
    setState(() => _busy = true);
    final response = await ref
        .read(teamProvider.notifier)
        .setActive(userId: member.userId, isActive: isActive);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(
      response.success
          ? (isActive
                ? context.l10n.settingsTeamActiveAgain(member.name)
                : context.l10n.settingsTeamDeactivated(member.name))
          : response.message ?? context.l10n.settingsTeamStatusError,
    );
  }

  void _showInviteSheet() {
    final emailController = TextEditingController();
    String role = 'USER';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (builderContext, setSheetState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    builderContext.l10n.settingsTeamInviteTitle,
                    style: AppTypography.h3,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: builderContext.l10n.commonEmail,
                      hintText: 'them@company.com',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    builderContext.l10n.settingsTeamRole,
                    style: AppTypography.labelSmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: teamRoles
                        .map(
                          (r) => ChoiceChip(
                            label: Text(
                              r == 'ADMIN'
                                  ? builderContext.l10n.settingsTeamRoleAdmin
                                  : builderContext.l10n.settingsTeamRoleMember,
                            ),
                            selected: role == r,
                            onSelected: (_) => setSheetState(() => role = r),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final email = emailController.text.trim();
                        Navigator.pop(sheetContext);
                        _invite(email, role);
                      },
                      child: Text(builderContext.l10n.settingsTeamSendInvite),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(emailController.dispose);
  }

  Future<void> _invite(String email, String role) async {
    if (email.isEmpty) {
      _snack(context.l10n.settingsTeamEnterEmail);
      return;
    }
    setState(() => _busy = true);
    final response = await ref
        .read(teamProvider.notifier)
        .invite(email: email, role: role);
    if (!mounted) return;
    setState(() => _busy = false);
    // The server's own words on failure: it is the one that knows the address
    // is already in this org, or already an account somewhere else.
    _snack(
      response.success
          ? context.l10n.settingsTeamInvited(email)
          : response.message ?? context.l10n.settingsTeamInviteError,
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'ADMIN';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isAdmin ? AppColors.primary50 : AppColors.gray100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isAdmin
            ? context.l10n.settingsTeamRoleAdmin
            : context.l10n.settingsTeamRoleMember,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isAdmin ? AppColors.primary600 : AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// What a member sees. Not an error: the API is admin-only by design, so
/// offering Retry would be offering a button that fails every time.
class _AdminsOnly extends StatelessWidget {
  const _AdminsOnly();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.lock, size: 36, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(context.l10n.settingsTeamAdminsOnly, style: AppTypography.h3),
            const SizedBox(height: 6),
            Text(
              context.l10n.settingsTeamAdminsOnlyBody,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
              LucideIcons.circleAlert,
              size: 36,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.settingsObjectsTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
