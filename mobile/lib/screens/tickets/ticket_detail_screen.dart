import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/theme.dart';
import '../../data/models/attachment.dart';
import '../../data/models/ticket.dart';
import '../../data/models/comment.dart';
import 'close_with_children_dialog.dart';
import 'macro_picker_sheet.dart';
import '../../data/models/macro.dart';
import '../../data/models/email_message.dart';
import '../../data/models/org_settings.dart';
import '../../providers/auth_provider.dart';
import '../../providers/lookup_provider.dart';
import '../../providers/org_modules_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/tickets_provider.dart';
import '../../config/api_config.dart';
import '../../services/api_service.dart' show ApiResponse;
import '../../services/attachment_upload.dart';
import '../../data/models/lookup_models.dart';
import '../../widgets/common/common.dart';
import '../../widgets/common/mention_text.dart';
import '../../widgets/forms/multi_select_sheet.dart';
import '../../widgets/tickets/ticket_approval_panel.dart';
import '../../widgets/tickets/ticket_properties_card.dart';
import '../../widgets/tickets/ticket_solutions_panel.dart';
import '../../widgets/tickets/ticket_time_panel.dart';
import '../../widgets/objects/related_objects_section.dart';
import '../../l10n/l10n.dart';
import '../../services/app_language.dart';

/// Ticket Detail Screen, Overview / Comments / Activity tabs.
class TicketDetailScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const TicketDetailScreen({super.key, required this.ticketId});

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _commentController = TextEditingController();

  TicketDetailResult? _detail;

  /// Other open tickets on the same account. Context beside the ticket, so a
  /// failure here leaves it empty rather than failing the screen.
  List<Ticket> _alsoOpen = const [];
  TicketWatchers? _watchers;
  TicketTreeNode? _tree;
  bool _isLoading = true;
  bool _isAddingComment = false;

  /// A macro picked into the composer whose actions ride along as chips, and
  /// the chips still on. They apply right after the reply posts. Null when no
  /// macro with actions is in the composer.
  Macro? _composerMacro;
  List<String> _keptActions = const [];
  bool _isUploadingAttachment = false;
  _ThreadSegment _segment = _ThreadSegment.public;

  /// Why the ticket could not be loaded, when it was not a 404 (offline, a
  /// server error): shown with a retry. A 404 leaves this null and [_detail]
  /// null, and reads as "not found".
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchDetail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final notifier = ref.read(ticketsProvider.notifier);
    String? failure;
    Future<TicketDetailResult?> loadDetail() async {
      try {
        return await notifier.getTicketDetail(widget.ticketId);
      } on TicketLoadFailure catch (e) {
        failure = e.message;
        return null;
      }
    }

    final results = await Future.wait([
      loadDetail(),
      notifier.getWatchers(widget.ticketId),
      notifier.fetchTree(widget.ticketId),
    ]);
    if (!mounted) return;
    final detail = results[0] as TicketDetailResult?;
    if (detail != null && detail.ticketObj.id != widget.ticketId) {
      // This ticket was merged, and the API answered with the one it was
      // merged into. Open that one in this screen's place, as the web
      // redirects, so every action here names the surviving ticket.
      context.pushReplacement('/tickets/${detail.ticketObj.id}');
      return;
    }
    setState(() {
      _isLoading = false;
      _detail = detail;
      _watchers = results[1] as TicketWatchers?;
      _tree = results[2] as TicketTreeNode?;
      _error = failure;
    });

    // Second request, after the ticket, because it needs the account id the
    // detail response carries. The web rail asks the same question the same
    // way; the phone showed nothing at all.
    final accountId = detail?.ticketObj.accountId;
    if (accountId == null || accountId.isEmpty) {
      if (mounted) setState(() => _alsoOpen = const []);
      return;
    }
    final siblings = await notifier.getAlsoOpenOnAccount(
      accountId: accountId,
      excludeTicketId: widget.ticketId,
    );
    if (mounted) setState(() => _alsoOpen = siblings);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_detail == null) {
      // A 404 is the same answer for a missing ticket and one the caller may
      // not open, so "not found" says both and offers no retry: asking again
      // gets the same answer. Anything else (offline, a server error) may
      // work next time, so it says what went wrong and offers one.
      final notFound = _error == null;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  notFound ? LucideIcons.fileX : LucideIcons.cloudOff,
                  size: 48,
                  color: AppColors.gray400,
                ),
                const SizedBox(height: 16),
                Text(
                  notFound
                      ? context.l10n.ticketsDetailNotFound
                      : context.l10n.ticketsDetailLoadFailed,
                  style: AppTypography.h3,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _error ?? context.l10n.ticketsDetailNotFoundBody,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!notFound) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _fetchDetail,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(context.l10n.commonRetry),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final c = _detail!.ticketObj;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.pop(),
        ),
        title: Text(
          c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.h3,
        ),
        actions: [
          IconButton(
            tooltip: (_watchers?.isCurrentUserWatching ?? false)
                ? context.l10n.ticketsDetailUnwatch
                : context.l10n.ticketsDetailWatch,
            icon: Icon(
              (_watchers?.isCurrentUserWatching ?? false)
                  ? LucideIcons.eye
                  : LucideIcons.eyeOff,
              color: (_watchers?.isCurrentUserWatching ?? false)
                  ? AppColors.primary600
                  : AppColors.textSecondary,
            ),
            onPressed: _toggleWatch,
          ),
          // Every change to the ticket takes its write rule on the server,
          // which `comment_permission` reports. A reader (a watcher) is not
          // offered an edit the API would answer 403.
          if (_canWrite)
            IconButton(
              tooltip: context.l10n.commonEdit,
              icon: const Icon(LucideIcons.pencil),
              onPressed: () async {
                final result = await context.push(
                  '/tickets/${widget.ticketId}/edit',
                );
                if (result == true && mounted) _fetchDetail();
              },
            ),
          IconButton(
            tooltip: context.l10n.ticketsDetailMore,
            icon: const Icon(LucideIcons.moreVertical),
            onPressed: _openActionSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary600,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary600,
          indicatorWeight: 2,
          labelStyle: AppTypography.label,
          tabs: [
            Tab(text: context.l10n.ticketsDetailTabOverview),
            Tab(text: context.l10n.ticketsDetailTabComments),
            Tab(text: context.l10n.ticketsDetailTabFiles),
            Tab(text: context.l10n.ticketsDetailTabActivity),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildHeaderStrip(c),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverview(c),
                _buildCommentsTab(c),
                _buildFilesTab(),
                _buildActivityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStrip(Ticket c) {
    return Container(
      width: double.infinity,
      color: AppColors.surfaceDim,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              c.status.label,
              style: AppTypography.caption.copyWith(
                color: c.status.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.priority.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.flag, size: 12, color: c.priority.color),
                const SizedBox(width: 4),
                Text(
                  c.priority.label,
                  style: AppTypography.caption.copyWith(
                    color: c.priority.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  c.ticketType.icon,
                  size: 12,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  c.ticketType.label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (c.isFirstResponseSlaBreached)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.danger100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.alertTriangle,
                    size: 12,
                    color: AppColors.danger600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.ticketsDetailSlaBreached,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.danger600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverview(Ticket c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TicketPropertiesCard(
            ticket: c,
            watcherCount: _watchers?.count,
            isWatching: _watchers?.isCurrentUserWatching ?? false,
          ),
          if ((_detail?.mergedFromCases ?? const []).isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildMergedFromCard(_detail!.mergedFromCases),
          ],
          if (_shouldShowTree(c)) ...[
            const SizedBox(height: 16),
            _buildTreeCard(c),
          ],
          if (ref.watch(moduleOnProvider('timesheet'))) ...[
            const SizedBox(height: 16),
            TicketTimePanel(ticketId: c.id, canLogTime: _canWrite),
          ],
          const SizedBox(height: 16),
          if (ref.watch(moduleOnProvider('knowledge_base')))
            TicketSolutionsPanel(
              ticketId: c.id,
              linked: _detail?.linkedSolutions ?? const [],
              onChanged: _fetchDetail,
              canEdit: _canWrite,
            ),
          TicketApprovalPanel(
            ticketId: c.id,
            approvalRule: _detail?.approvalRule,
            canWrite: _canWrite,
            isOpen: openTicketStatuses.contains(c.status),
          ),
          const SizedBox(height: 16),
          _card(
            title: context.l10n.ticketsDetailInfoTitle,
            child: Column(
              children: [
                _InfoRow(
                  icon: LucideIcons.fileText,
                  label: context.l10n.ticketsDetailInfoName,
                  value: c.name,
                ),
                const Divider(height: 24),
                _InfoRow(
                  icon: LucideIcons.building2,
                  label: context.l10n.ticketsDetailInfoAccount,
                  value:
                      c.accountName ?? context.l10n.ticketsDetailInfoNoAccount,
                ),
                const Divider(height: 24),
                _InfoRow(
                  icon: LucideIcons.calendar,
                  label: context.l10n.ticketsDetailInfoCreated,
                  value: _formatDate(c.createdAt),
                ),
                if (c.closedOn != null) ...[
                  const Divider(height: 24),
                  _InfoRow(
                    icon: LucideIcons.checkCircle,
                    label: context.l10n.ticketsDetailInfoClosed,
                    value: _formatDate(c.closedOn!),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _card(
            title: context.l10n.ticketsDetailAssignedTo,
            child: Row(
              children: [
                UserAvatar(name: c.assignedToName, size: AvatarSize.md),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(c.assignedToName, style: AppTypography.label),
                ),
              ],
            ),
          ),
          if (c.contactNames.isNotEmpty) ...[
            const SizedBox(height: 16),
            _card(
              title: c.contactNames.length == 1
                  ? context.l10n.ticketsDetailReportedBy
                  : context.l10n.ticketsDetailPeopleCount(
                      c.contactNames.length,
                    ),
              child: Column(
                children: [
                  for (final name in c.contactNames)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          UserAvatar(name: name, size: AvatarSize.sm),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(name, style: AppTypography.label),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (c.description != null && c.description!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _card(
              title: context.l10n.commonDescription,
              child: Text(
                c.description!,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
          // The account's other open tickets. Empty when the ticket has no
          // account, or when it is the only one open, so the card appears only
          // when it has something to say.
          if (_alsoOpen.isNotEmpty) ...[
            const SizedBox(height: 16),
            _card(
              title: c.accountName == null
                  ? context.l10n.ticketsDetailAlsoOpenOnThisAccount
                  : context.l10n.ticketsDetailAlsoOpenOn(c.accountName!),
              child: Column(
                children: [
                  for (final sibling in _alsoOpen)
                    _AlsoOpenRow(
                      ticket: sibling,
                      // Same literal every other jump to a ticket uses in
                      // this file; there is no builder on AppRoutes for it.
                      onTap: () => context.push('/tickets/${sibling.id}'),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          RelatedObjectsSection(to: 'ticket', recordId: c.id),
          const SizedBox(height: 84),
        ],
      ),
    );
  }

  Widget _buildCommentsTab(Ticket c) {
    final internalIds = _detail?.internalCommentIds ?? const {};
    final allComments = c.comments;
    final emails = _detail?.emails ?? const [];

    final filteredComments = switch (_segment) {
      _ThreadSegment.public =>
        allComments.where((cm) => !internalIds.contains(cm.id)).toList(),
      _ThreadSegment.internal =>
        allComments.where((cm) => internalIds.contains(cm.id)).toList(),
      _ThreadSegment.emails => const <Comment>[],
    };

    final canCompose =
        (_detail?.commentPermission ?? false) &&
        _segment != _ThreadSegment.emails;

    return Column(
      children: [
        _buildThreadSegments(
          publicCount: allComments
              .where((cm) => !internalIds.contains(cm.id))
              .length,
          internalCount: allComments
              .where((cm) => internalIds.contains(cm.id))
              .length,
          emailsCount: emails.length,
        ),
        Expanded(
          child: _segment == _ThreadSegment.emails
              ? _buildEmailsList(emails)
              : _buildCommentsList(filteredComments, internalIds),
        ),
        if (canCompose) _buildCommentComposer(),
      ],
    );
  }

  Widget _buildThreadSegments({
    required int publicCount,
    required int internalCount,
    required int emailsCount,
  }) {
    Widget chip(_ThreadSegment seg, String label, IconData icon, int count) {
      final selected = _segment == seg;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _segment = seg),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? AppColors.border : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: selected
                      ? AppColors.primary600
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                // Flexible, so a third of a 390px screen with large text
                // truncates the label instead of overflowing the segment.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: selected
                          ? AppColors.primary600
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: AppTypography.caption.copyWith(
                      color: selected
                          ? AppColors.primary600
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          chip(
            _ThreadSegment.public,
            context.l10n.ticketsDetailThreadPublic,
            LucideIcons.messageSquare,
            publicCount,
          ),
          chip(
            _ThreadSegment.internal,
            context.l10n.ticketsDetailThreadInternal,
            LucideIcons.lock,
            internalCount,
          ),
          chip(
            _ThreadSegment.emails,
            context.l10n.ticketsDetailThreadEmails,
            LucideIcons.mail,
            emailsCount,
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsList(List<Comment> comments, Set<String> internalIds) {
    if (comments.isEmpty) {
      return EmptyState(
        icon: _segment == _ThreadSegment.internal
            ? LucideIcons.lock
            : LucideIcons.messageSquare,
        title: _segment == _ThreadSegment.internal
            ? context.l10n.ticketsDetailNoInternalNotes
            : context.l10n.ticketsDetailNoComments,
        description: _segment == _ThreadSegment.internal
            ? context.l10n.ticketsDetailInternalNotesHint
            : context.l10n.ticketsDetailFirstCommentHint,
      );
    }
    final handles = mentionHandles(ref.watch(usersProvider));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: comments.length,
      itemBuilder: (context, i) {
        final comment = comments[i];
        return _CommentTile(
          comment: comment,
          isInternal: internalIds.contains(comment.id),
          handles: handles,
        );
      },
    );
  }

  Widget _buildEmailsList(List<EmailMessage> emails) {
    if (emails.isEmpty) {
      return EmptyState(
        icon: LucideIcons.mail,
        title: context.l10n.ticketsDetailNoEmails,
        description: context.l10n.ticketsDetailNoEmailsHint,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: emails.length,
      itemBuilder: (context, i) => _EmailTile(email: emails[i]),
    );
  }

  Widget _buildCommentComposer() {
    final isInternal = _segment == _ThreadSegment.internal;
    final macro = _composerMacro;
    final chips = macro == null
        ? const <({String key, String label})>[]
        : macroActionChips(
            macro,
          ).where((c) => _keptActions.contains(c.key)).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chips.isNotEmpty) ...[
              // The macro's actions, applied right after this reply posts.
              // Each can be taken off; what is left is what applies.
              Text(
                context.l10n.ticketsDetailAlsoOnSend,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final chip in chips)
                    _MacroActionChip(
                      key: ValueKey('macro-action-${chip.key}'),
                      label: chip.label,
                      onRemove: _isAddingComment
                          ? null
                          : () => setState(
                              () => _keptActions = _keptActions
                                  .where((k) => k != chip.key)
                                  .toList(),
                            ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            _buildComposerRow(isInternal),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerRow(bool isInternal) {
    return Row(
      children: [
        IconButton(
          tooltip: context.l10n.ticketsDetailMention,
          icon: const Icon(LucideIcons.atSign, size: 20),
          color: AppColors.textSecondary,
          onPressed: _isAddingComment ? null : _pickMention,
        ),
        IconButton(
          tooltip: context.l10n.ticketsDetailSavedReply,
          icon: const Icon(LucideIcons.messageSquareQuote, size: 20),
          color: AppColors.textSecondary,
          onPressed: _isAddingComment ? null : _pickMacro,
        ),
        Expanded(
          child: TextField(
            controller: _commentController,
            enabled: !_isAddingComment,
            decoration: InputDecoration(
              hintText: isInternal
                  ? context.l10n.ticketsDetailHintInternalNote
                  : context.l10n.ticketsDetailHintEmailCustomer,
              hintStyle: AppTypography.body.copyWith(
                color: AppColors.textTertiary,
              ),
              filled: true,
              fillColor: isInternal ? AppColors.warning50 : AppColors.gray100,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
            maxLines: null,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            color: _isAddingComment
                ? AppColors.gray400
                : (isInternal ? AppColors.warning600 : AppColors.primary600),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: _isAddingComment
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.send, color: Colors.white, size: 20),
            onPressed: _isAddingComment ? null : _addComment,
          ),
        ),
      ],
    );
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final isInternal = _segment == _ThreadSegment.internal;
    setState(() => _isAddingComment = true);
    final response = await ref
        .read(ticketsProvider.notifier)
        .addComment(widget.ticketId, text, isInternal: isInternal);
    if (!mounted) return;

    if (!response.success) {
      setState(() => _isAddingComment = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.message ?? context.l10n.ticketsDetailAddCommentFailed,
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.danger600,
        ),
      );
      return;
    }

    // The kept macro actions apply now that the reply is out, the order the
    // web uses: a refusal (the close approval, a merged ticket) is reported
    // after the customer has been answered, and the reply is not undone.
    final macro = _composerMacro;
    final kept = _keptActions;
    if (macro != null && kept.isNotEmpty) {
      await _applyComposerMacro(macro, kept);
      if (!mounted) return;
    }

    // The POST response already returns the fresh `comments` and
    // `internal_notes` arrays, re-fold them into the existing _detail
    // instead of refetching the whole envelope + watchers + tree (which
    // is what made the screen feel like a full reload).
    final data = response.data;
    final current = _detail;
    if (data != null && current != null) {
      final tagged = <_TaggedCommentLocal>[];
      for (final c in (data['comments'] as List<dynamic>? ?? [])) {
        if (c is Map<String, dynamic>) {
          tagged.add(
            _TaggedCommentLocal(
              comment: Comment.fromJson(c),
              isInternal: false,
            ),
          );
        }
      }
      for (final c in (data['internal_notes'] as List<dynamic>? ?? [])) {
        if (c is Map<String, dynamic>) {
          tagged.add(
            _TaggedCommentLocal(comment: Comment.fromJson(c), isInternal: true),
          );
        }
      }
      tagged.sort(
        (a, b) => b.comment.commentedOn.compareTo(a.comment.commentedOn),
      );

      setState(() {
        _isAddingComment = false;
        _commentController.clear();
        _detail = TicketDetailResult(
          ticketObj: current.ticketObj.copyWith(
            comments: tagged.map((t) => t.comment).toList(),
          ),
          activities: current.activities,
          emails: current.emails,
          mergedFromCases: current.mergedFromCases,
          linkedSolutions: current.linkedSolutions,
          attachments: current.attachments,
          commentPermission: current.commentPermission,
          canMerge: current.canMerge,
          internalCommentIds: tagged
              .where((t) => t.isInternal)
              .map((t) => t.comment.id)
              .toSet(),
        );
      });
    } else {
      setState(() {
        _isAddingComment = false;
        _commentController.clear();
      });
    }
  }

  // ===========================================================================
  // FILES TAB
  // ===========================================================================

  /// Attachments on a ticket. `CaseDetailView` has always returned these and
  /// nothing on the phone read them, so a screenshot attached to a ticket, the
  /// single most useful thing on a support record, was invisible here.
  Widget _buildFilesTab() {
    final attachments = _detail?.attachments ?? const <Attachment>[];
    if (attachments.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchDetail,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.paperclip,
                    size: 48,
                    color: AppColors.gray400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.ticketsDetailNoFiles,
                    style: AppTypography.h3,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _canWrite
                        ? context.l10n.ticketsDetailAttachHint
                        : context.l10n.ticketsDetailNothingAttached,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (_canWrite) ...[
                    const SizedBox(height: 12),
                    AttachFileButton(
                      isUploading: _isUploadingAttachment,
                      onPressed: _pickAndUploadAttachment,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetchDetail,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: attachments.length + (_canWrite ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => index == attachments.length
            ? Align(
                alignment: Alignment.centerLeft,
                child: AttachFileButton(
                  isUploading: _isUploadingAttachment,
                  onPressed: _pickAndUploadAttachment,
                ),
              )
            : AttachmentTile(
                attachment: attachments[index],
                onOpen: _openAttachment,
              ),
      ),
    );
  }

  /// Download an attachment through the API, with the token attached. See the
  /// note on `Attachment.filePath` for why the stored path is not a URL.
  Future<void> _openAttachment(Attachment attachment) async {
    if (!attachment.hasFile) {
      _snack(context.l10n.ticketsDetailAttachmentNoFile);
      return;
    }
    final result = await downloadAttachment(
      url: ApiConfig.attachmentDownload(attachment.id),
      fileName: attachment.fileName,
    );
    if (!mounted || result.success) return;
    _snack(result.error ?? context.l10n.ticketsDetailDownloadFailed);
  }

  /// Attach a file to this ticket.
  Future<void> _pickAndUploadAttachment() async {
    if (_isUploadingAttachment || _detail == null) return;
    setState(() => _isUploadingAttachment = true);

    final result = await pickAndUploadAttachment(
      target: AttachmentTarget.ticket,
      recordId: widget.ticketId,
    );

    if (!mounted) return;
    setState(() => _isUploadingAttachment = false);

    if (result.cancelled) return;
    if (!result.succeeded) {
      _snack(result.error!);
      return;
    }

    final attachmentsData = result.data?['attachments'];
    if (attachmentsData is List && _detail != null) {
      setState(() {
        _detail = _detail!.copyWith(
          attachments: attachmentsData
              .whereType<Map<String, dynamic>>()
              .map(Attachment.fromJson)
              .toList(),
        );
      });
    } else {
      await _fetchDetail();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildActivityTab() {
    final activities = _detail?.activities ?? [];
    if (activities.isEmpty) {
      return Center(
        child: EmptyState(
          icon: LucideIcons.clock,
          title: context.l10n.ticketsDetailNoActivity,
          description: context.l10n.ticketsDetailNoActivityHint,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: activities.length,
      itemBuilder: (context, i) {
        final a = activities[i];
        return _ActivityTile(activity: a);
      },
    );
  }

  Future<void> _pickMention() async {
    final users = ref.read(usersProvider);
    final picked = await showModalBottomSheet<UserLookup>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, controller) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.ticketsDetailMentionSomeone,
                style: AppTypography.h3,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: users.length,
                itemBuilder: (_, i) {
                  final u = users[i];
                  return InkWell(
                    onTap: () => Navigator.pop(context, u),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          UserAvatar(name: u.displayName, size: AvatarSize.xs),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  u.displayName,
                                  style: AppTypography.body.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  u.email,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;

    // Backend mention regex matches `@local-part` (the slug before "@").
    // Inserting "@$local " also auto-adds them as a watcher.
    final local = picked.email.split('@').first;
    final token = '@$local ';
    final text = _commentController.text;
    final sel = _commentController.selection;
    final insertAt = sel.isValid ? sel.start : text.length;
    final next = text.replaceRange(insertAt, insertAt, token);
    _commentController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: insertAt + token.length),
    );
  }

  /// Insert a saved reply, expanded against this ticket.
  ///
  /// Inserted at the cursor rather than replacing the box, so a macro can be
  /// dropped into a reply already part-written. Nothing is sent: the agent
  /// still reads it and presses send, which is the point of expanding it into
  /// the composer instead of posting it.
  Future<void> _pickMacro() async {
    final pick = await showMacroPickerSheet(context, widget.ticketId);
    if (pick == null || !mounted) return;

    // A macro with no text was applied in the sheet; the ticket changed.
    if (pick.appliedSummary != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pick.appliedSummary!),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchDetail();
      return;
    }

    final chips = macroActionChips(pick.macro);
    setState(() {
      _composerMacro = chips.isEmpty ? null : pick.macro;
      _keptActions = chips.map((c) => c.key).toList();
    });

    final rendered = pick.text ?? '';
    if (rendered.isEmpty) return;
    final text = _commentController.text;
    final sel = _commentController.selection;
    final insertAt = sel.isValid ? sel.start : text.length;
    final insertEnd = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(insertAt, insertEnd, rendered);
    _commentController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: insertAt + rendered.length),
    );
  }

  /// Apply the composer macro's kept actions after a reply went out, then
  /// clear the chips and reload, since the ticket may have changed.
  Future<void> _applyComposerMacro(Macro macro, List<String> kept) async {
    final result = await applyMacro(
      macroId: macro.id,
      ticketId: widget.ticketId,
      only: kept,
    );
    if (!mounted) return;
    setState(() {
      _composerMacro = null;
      _keptActions = const [];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.error == null
              ? result.summary!
              : context.l10n.ticketsDetailMacroNotApplied('${result.error}'),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: result.error == null ? null : AppColors.danger600,
      ),
    );
    await _fetchDetail();
  }

  Future<void> _toggleWatch() async {
    final current = _watchers?.isCurrentUserWatching ?? false;
    final ok = await ref
        .read(ticketsProvider.notifier)
        .setWatching(widget.ticketId, !current);
    if (!mounted) return;
    if (ok) {
      // Refetch watcher state instead of optimistic toggle so the count
      // stays accurate even if multiple subscribed-via paths flip.
      final fresh = await ref
          .read(ticketsProvider.notifier)
          .getWatchers(widget.ticketId);
      if (mounted) setState(() => _watchers = fresh);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            current
                ? context.l10n.ticketsDetailUnwatchFailed
                : context.l10n.ticketsDetailWatchFailed,
          ),
          backgroundColor: AppColors.danger600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool get _isAdmin => ref.read(isOrgAdminProvider);

  /// The ticket's write rule, as the server answered it (`comment_permission`
  /// on the detail). Gates every change this screen offers: edit, status,
  /// priority, reassign, close, link, time, attachments, solutions, approval
  /// requests. Watching is a read and stays open to readers.
  bool get _canWrite => _detail?.commentPermission == true;

  void _openActionSheet() {
    final c = _detail?.ticketObj;
    if (c == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        // Scrolls so an admin's full set of rows, with labels wrapping under
        // large text, never overflows the sheet's height cap.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (_canWrite)
                _actionRow(
                  icon: LucideIcons.users,
                  label: context.l10n.ticketsDetailActionReassign,
                  onTap: () {
                    Navigator.pop(context);
                    _reassign(c);
                  },
                ),
              if (_canWrite)
                _actionRow(
                  icon: LucideIcons.circleDot,
                  label: context.l10n.ticketsDetailActionChangeStatus,
                  onTap: () {
                    Navigator.pop(context);
                    _changeStatus(c);
                  },
                ),
              if (_canWrite)
                _actionRow(
                  icon: LucideIcons.flag,
                  label: context.l10n.ticketsDetailActionChangePriority,
                  onTap: () {
                    Navigator.pop(context);
                    _changePriority(c);
                  },
                ),
              if (_canWrite && c.status != TicketStatus.closed)
                _actionRow(
                  icon: LucideIcons.checkCircle,
                  iconColor: AppColors.success600,
                  label: context.l10n.ticketsDetailActionClose,
                  onTap: () {
                    Navigator.pop(context);
                    _closeTicket(c);
                  },
                ),
              // The server answers `can_merge` (admin or the ticket's creator)
              // and refuses the merge itself for anyone else.
              if (_detail?.canMerge == true)
                _actionRow(
                  icon: LucideIcons.gitMerge,
                  label: context.l10n.ticketsDetailActionMerge,
                  onTap: () {
                    Navigator.pop(context);
                    _mergeInto(c);
                  },
                ),
              if (_canWrite)
                _actionRow(
                  icon: LucideIcons.link,
                  label: c.parentSummary == null
                      ? context.l10n.ticketsDetailActionLinkParent
                      : context.l10n.ticketsDetailActionChangeParent,
                  onTap: () {
                    Navigator.pop(context);
                    _linkParent(c);
                  },
                ),
              if (_canWrite &&
                  c.childCount > 0 &&
                  c.status != TicketStatus.closed)
                _actionRow(
                  icon: LucideIcons.checkCheck,
                  iconColor: AppColors.success600,
                  label: context.l10n.ticketsDetailActionCloseWithChildren,
                  onTap: () {
                    Navigator.pop(context);
                    _closeWithChildren(c);
                  },
                ),
              if (_isAdmin)
                _actionRow(
                  icon: LucideIcons.trash2,
                  iconColor: AppColors.danger600,
                  label: context.l10n.ticketsDetailActionDelete,
                  labelColor: AppColors.danger600,
                  onTap: () {
                    Navigator.pop(context);
                    _deleteTicket(c);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Color? labelColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? AppColors.textSecondary),
            const SizedBox(width: 16),
            // Expanded so a long label wraps instead of overflowing: the
            // detach row names the parent, and a ticket subject has no limit
            // a 390px sheet can hold.
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  color: labelColor ?? AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reassign(Ticket c) async {
    final users = ref.read(usersProvider);
    final initial = users.where((u) => c.assignedToIds.contains(u.id)).toList();
    final result = await MultiSelectSheet.show<UserLookup>(
      context: context,
      title: context.l10n.ticketsDetailReassignTitle,
      items: users,
      initialSelection: initial,
      labelOf: (u) => u.displayName,
      searchText: (u) => '${u.email} ${u.displayName}',
      leadingOf: (u) => UserAvatar(name: u.displayName, size: AvatarSize.xs),
    );
    if (result == null || !mounted) return;
    await _applyUpdate({
      'assigned_to': result.map((u) => u.id).toList(),
    }, context.l10n.ticketsDetailReassigned);
  }

  Future<void> _changeStatus(Ticket c) async {
    final picked = await _showEnumPicker<TicketStatus>(
      title: context.l10n.ticketsDetailActionChangeStatus,
      options: TicketStatus.settable,
      current: c.status,
      labelOf: (s) => s.label,
      colorOf: (s) => s.color,
    );
    if (picked == null || picked == c.status || !mounted) return;

    // A close sends no `closed_on`: the server dates it today in the org's
    // timezone.
    await _applyUpdate({
      'status': picked.value,
    }, context.l10n.ticketsDetailStatusUpdated);
  }

  Future<void> _changePriority(Ticket c) async {
    final picked = await _showEnumPicker<TicketPriority>(
      title: context.l10n.ticketsDetailActionChangePriority,
      options: TicketPriority.values,
      current: c.priority,
      labelOf: (p) => p.label,
      colorOf: (p) => p.color,
    );
    if (picked == null || picked == c.priority || !mounted) return;
    await _applyUpdate({
      'priority': picked.value,
    }, context.l10n.ticketsDetailPriorityUpdated);
  }

  Future<void> _closeTicket(Ticket c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.ticketsDetailCloseConfirmTitle),
        content: Text(context.l10n.ticketsDetailCloseConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.ticketsDetailActionClose),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _applyUpdate({
      'status': TicketStatus.closed.value,
    }, context.l10n.ticketsDetailTicketClosed);
  }

  Future<void> _mergeInto(Ticket c) async {
    // The candidates come from the server, which lists only the tickets this
    // merge would accept. The loaded list is not a safe source: it holds
    // tickets the caller did not create, which a non-admin's merge refuses.
    final tickets = ref.read(ticketsProvider.notifier);
    final target = await showModalBottomSheet<Ticket>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, controller) => _TicketPickerSheet(
          title: context.l10n.ticketsDetailMergeIntoTitle,
          controller: controller,
          search: (query) => tickets.mergeTargets(c.id, search: query),
        ),
      ),
    );
    if (target == null) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.ticketsDetailMergeConfirmTitle),
        content: Text(
          context.l10n.ticketsDetailMergeConfirmBody(c.name, target.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.ticketsDetailMergeButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await ref
        .read(ticketsProvider.notifier)
        .mergeInto(c.id, target.id);
    if (!mounted) return;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.ticketsDetailMergedInto(target.name)),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Source now redirects on detail fetch, pop back to the list so the
      // user isn't stuck on a now-redirecting ticket.
      context.pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? context.l10n.ticketsDetailMergeFailed),
          backgroundColor: AppColors.danger600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _unmergeSource(MergedFromSummary src) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.ticketsDetailUnmergeConfirmTitle),
        content: Text(context.l10n.ticketsDetailUnmergeConfirmBody(src.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.ticketsDetailUnmergeButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final res = await ref.read(ticketsProvider.notifier).unmerge(src.id);
    if (!mounted) return;
    if (res.success) {
      await _fetchDetail();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.ticketsDetailUnmerged(src.name)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? context.l10n.ticketsDetailUnmergeFailed),
          backgroundColor: AppColors.danger600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteTicket(Ticket c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.ticketsDetailDeleteConfirmTitle),
        content: Text(context.l10n.ticketsDetailDeleteConfirmBody(c.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger600),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final response = await ref
        .read(ticketsProvider.notifier)
        .deleteTicket(widget.ticketId);
    if (!mounted) return;
    if (response.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.ticketsDetailTicketDeleted),
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.message ?? context.l10n.ticketsDetailDeleteFailed,
          ),
          backgroundColor: AppColors.danger600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _applyUpdate(
    Map<String, dynamic> patch,
    String successMessage,
  ) async {
    final response = await ref
        .read(ticketsProvider.notifier)
        .updateTicket(widget.ticketId, patch);
    if (!mounted) return;
    if (response.success) {
      await _fetchDetail();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.message ?? context.l10n.ticketsDetailUpdateFailed,
          ),
          backgroundColor: AppColors.danger600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<T?> _showEnumPicker<T>({
    required String title,
    required List<T> options,
    required T current,
    required String Function(T) labelOf,
    Color Function(T)? colorOf,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.gray300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: AppTypography.h3),
            ),
            for (final opt in options)
              InkWell(
                onTap: () => Navigator.pop(context, opt),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      if (colorOf != null) ...[
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colorOf(opt),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Text(
                          labelOf(opt),
                          style: AppTypography.body.copyWith(
                            fontWeight: opt == current
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: opt == current
                                ? AppColors.primary600
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (opt == current)
                        Icon(
                          LucideIcons.check,
                          size: 20,
                          color: AppColors.primary600,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  bool _shouldShowTree(Ticket c) {
    if (c.parentSummary != null) return true;
    if (c.childCount > 0) return true;
    if (c.isProblem) return true;
    return false;
  }

  Widget _buildTreeCard(Ticket c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppLayout.borderRadiusLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.gitBranch, size: 16, color: AppColors.gray600),
              const SizedBox(width: 8),
              Text(
                context.l10n.ticketsDetailLinkedTickets,
                style: AppTypography.overline.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (c.isProblem) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    context.l10n.ticketsDetailProblem,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.danger700,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (c.parentSummary != null)
            InkWell(
              // A parent the viewer cannot open would only answer 404.
              onTap: c.parentSummary!.restricted
                  ? null
                  : () => context.push('/tickets/${c.parentSummary!.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.arrowUp,
                      size: 14,
                      color: AppColors.gray500,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.ticketsDetailParent,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                          Text(
                            c.parentSummary!.name,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w500,
                              fontStyle: c.parentSummary!.restricted
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              color: c.parentSummary!.restricted
                                  ? AppColors.textTertiary
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (c.parentSummary!.status != null)
                      StatusBadge.fromTicketStatus(
                        TicketStatus.fromString(c.parentSummary!.status),
                      ),
                  ],
                ),
              ),
            ),
          if (_tree != null && _tree!.children.isNotEmpty) ...[
            const Divider(height: 20),
            // Tree shows up to PARENT_MAX_DEPTH (3). We render the root-down
            // view since the user opened a node inside it.
            ..._treeRows(_tree!, depth: 0),
            if (_tree!.truncated)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.l10n.ticketsDetailTreeTruncated,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
          ] else if (c.parentSummary == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                context.l10n.ticketsDetailLinkedCount(c.childCount),
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _treeRows(TicketTreeNode node, {required int depth}) {
    final rows = <Widget>[];
    // Don't render the root again. It's the parent we already showed above.
    if (depth > 0) {
      rows.add(
        InkWell(
          // A ticket the viewer cannot open would only answer 404.
          onTap: node.restricted
              ? null
              : () => context.push('/tickets/${node.id}'),
          child: Padding(
            padding: EdgeInsets.fromLTRB((depth - 1) * 16.0, 6, 0, 6),
            child: Row(
              children: [
                Icon(
                  LucideIcons.cornerDownRight,
                  size: 14,
                  color: AppColors.gray400,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: AppTypography.body.copyWith(
                      fontWeight: node.isFocused
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontStyle: node.restricted
                          ? FontStyle.italic
                          : FontStyle.normal,
                      color: node.isFocused
                          ? AppColors.primary600
                          : node.restricted
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                if (node.status != null)
                  StatusBadge.fromTicketStatus(
                    TicketStatus.fromString(node.status),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    for (final child in node.children) {
      rows.addAll(_treeRows(child, depth: depth + 1));
    }
    return rows;
  }

  Future<void> _linkParent(Ticket c) async {
    // For "detach", offer the action up-front when a parent already exists.
    if (c.parentSummary != null) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.gray300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.l10n.ticketsDetailParentTicket,
                  style: AppTypography.h3,
                ),
              ),
              _actionRow(
                icon: LucideIcons.replace,
                label: context.l10n.ticketsDetailPickDifferentParent,
                onTap: () => Navigator.pop(context, 'pick'),
              ),
              _actionRow(
                icon: LucideIcons.unlink,
                iconColor: AppColors.danger600,
                // Unlinking needs write on this ticket only, so a hidden
                // parent can still be left; it just is not named.
                label: c.parentSummary!.restricted
                    ? context.l10n.ticketsDetailDetachFromParentTicket
                    : context.l10n.ticketsDetailDetachFrom(
                        c.parentSummary!.name,
                      ),
                labelColor: AppColors.danger600,
                onTap: () => Navigator.pop(context, 'detach'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (!mounted) return;
      if (picked == 'detach') {
        await _applyLink(
          c.id,
          null,
          context.l10n.ticketsDetailDetachedFromParent,
        );
        return;
      }
      if (picked != 'pick') return;
    }

    if (!mounted) return;
    final candidates = ref
        .read(ticketsListProvider)
        .where(
          (t) =>
              t.id != c.id &&
              t.status != TicketStatus.duplicate &&
              t.id != c.parentSummary?.id,
        )
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.ticketsDetailNoLinkCandidates),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final parent = await showModalBottomSheet<Ticket>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, controller) => _TicketPickerSheet(
          title: context.l10n.ticketsDetailLinkToParentTitle,
          tickets: candidates,
          controller: controller,
        ),
      ),
    );
    if (parent == null) return;
    if (!mounted) return;
    await _applyLink(
      c.id,
      parent.id,
      context.l10n.ticketsDetailLinkedTo(parent.name),
    );
  }

  Future<void> _applyLink(
    String id,
    String? parentId,
    String successMessage,
  ) async {
    final res = await ref
        .read(ticketsProvider.notifier)
        .linkParent(id, parentId);
    if (!mounted) return;
    if (res.success) {
      await _fetchDetail();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? context.l10n.ticketsDetailLinkFailed),
          backgroundColor: AppColors.danger600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _closeWithChildren(Ticket c) async {
    // **The org setting decides how this prompt starts.** That is the whole of
    // what `Org.auto_close_children_on_parent_close` does for a person:
    // `CaseCloseWithChildrenView` reads it only when the caller omits
    // `cascade`, and this app always sends it, so hardcoding `true` here made
    // the setting inert. The settings screen says "starts ticked"/"starts
    // unticked"; this is the line that has to make that true.
    final orgSettings = await ref
        .read(orgSettingsProvider.future)
        .catchError(
          // A settings read that fails must not block closing a ticket. Falling
          // back to the model default (false) is the safer of the two: it offers
          // not to close children rather than offering to.
          (_) => const OrgSettings(),
        );
    if (!mounted) return;

    // The tickets that would actually close, from the tree this screen already
    // loaded. `childCount` was what this used to pass, and it counts direct
    // children whether open or closed, so the prompt could offer to close
    // three tickets that were closed last week and stay silent about an open
    // grandchild that was about to close.
    final openBelow = _tree?.openDescendantsOf(c.id) ?? const [];

    final choice = await showCloseWithChildrenDialog(
      context,
      ticketName: c.name,
      openNames: [for (final node in openBelow) node.name],
      startsTicked: orgSettings.autoCloseChildren,
      truncated: _tree?.subtreeTruncatedFor(c.id) ?? false,
    );
    if (choice == null || !mounted) return;
    final cascade = choice.cascade;

    final res = await ref
        .read(ticketsProvider.notifier)
        .closeWithChildren(
          c.id,
          cascade: cascade,
          resolutionComment: choice.comment,
        );
    if (!mounted) return;
    if (res.success) {
      await _fetchDetail();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              cascadeCloseMessage(
                cascade: cascade,
                cascaded: cascadedCount(res.data),
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? context.l10n.ticketsDetailCloseFailed),
          backgroundColor: AppColors.danger600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildMergedFromCard(List<MergedFromSummary> sources) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppLayout.borderRadiusLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.gitMerge, size: 16, color: AppColors.gray600),
              const SizedBox(width: 8),
              Text(
                context.l10n.ticketsDetailMergedFrom,
                style: AppTypography.overline.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final src in sources) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      src.name,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  // Offered only where the server says this caller may
                  // unmerge (admin, or creator of both tickets).
                  if (src.canUnmerge)
                    TextButton(
                      // Themed buttons carry an infinite minimum width, which a
                      // Row does not bound. Without this the row fails to lay
                      // out and the screen paints nothing. See
                      // AppLayout.buttonMinSizeInRow.
                      style: TextButton.styleFrom(
                        minimumSize: AppLayout.buttonMinSizeInRow,
                      ),
                      onPressed: () => _unmergeSource(src),
                      child: Text(context.l10n.ticketsDetailUnmergeButton),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppLayout.borderRadiusLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.overline.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      localDateFormat('MMM d, y', 'yMMMd').format(date);
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
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.gray400),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.overline.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: AppTypography.body),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  final bool isInternal;
  final Set<String> handles;

  const _CommentTile({
    required this.comment,
    required this.isInternal,
    required this.handles,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isInternal ? AppColors.warning50 : AppColors.gray50,
        borderRadius: AppLayout.borderRadiusLg,
        border: Border.all(
          color: isInternal ? AppColors.warning200 : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isInternal) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.lock, size: 11, color: AppColors.warning700),
                  const SizedBox(width: 3),
                  Text(
                    context.l10n.ticketsDetailCommentInternal,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.warning700,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          MentionText(
            comment.comment,
            handles: handles,
            style: AppTypography.body.copyWith(
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              UserAvatar(name: comment.authorName, size: AvatarSize.xs),
              const SizedBox(width: 8),
              Text(
                comment.authorName,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeAgo(context, comment.commentedOn),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _timeAgo(BuildContext context, DateTime t) {
  final l = context.l10n;
  final diff = DateTime.now().difference(t);
  if (diff.inDays > 30) {
    return l.ticketsDetailAgoMonths((diff.inDays / 30).floor());
  }
  if (diff.inDays > 0) return l.ticketsDetailAgoDays(diff.inDays);
  if (diff.inHours > 0) return l.ticketsDetailAgoHours(diff.inHours);
  if (diff.inMinutes > 0) return l.ticketsDetailAgoMinutes(diff.inMinutes);
  return l.ticketsDetailJustNow;
}

enum _ThreadSegment { public, internal, emails }

class _TaggedCommentLocal {
  final Comment comment;
  final bool isInternal;
  const _TaggedCommentLocal({required this.comment, required this.isInternal});
}

class _TicketPickerSheet extends StatefulWidget {
  final String title;

  /// Tickets filtered here, by name or account, as the user types.
  final List<Ticket> tickets;

  /// When set, the list comes from the server instead: called with the query
  /// (debounced while typing) and shown as answered, never filtered here.
  final Future<ApiResponse<List<Ticket>>> Function(String query)? search;
  final ScrollController controller;
  const _TicketPickerSheet({
    required this.title,
    required this.controller,
    this.tickets = const [],
    this.search,
  });

  @override
  State<_TicketPickerSheet> createState() => _TicketPickerSheetState();
}

class _TicketPickerSheetState extends State<_TicketPickerSheet> {
  String _query = '';
  Timer? _debounce;

  /// Bumped per server search, so a slow answer to an older query is dropped
  /// rather than replacing a newer one.
  int _searchSeq = 0;
  bool _searching = false;
  String? _searchError;
  List<Ticket> _results = const [];

  @override
  void initState() {
    super.initState();
    if (widget.search != null) _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    if (widget.search == null) return;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(value),
    );
  }

  Future<void> _runSearch(String query) async {
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    final response = await widget.search!(query);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _searching = false;
      _searchError = response.success ? null : response.message;
      _results = response.data ?? const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = widget.search != null
        ? _results
        : q.isEmpty
        ? widget.tickets
        : widget.tickets
              .where(
                (t) =>
                    t.name.toLowerCase().contains(q) ||
                    (t.accountName?.toLowerCase().contains(q) ?? false),
              )
              .toList();
    final Widget? placeholder = filtered.isNotEmpty
        ? null
        : _searching
        ? const CircularProgressIndicator()
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _searchError ?? context.l10n.ticketsDetailNoMatchingTickets,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          );
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.gray300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(widget.title, style: AppTypography.h3),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.l10n.ticketsDetailSearchTicketsHint,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              filled: true,
              fillColor: AppColors.gray50,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        Expanded(
          child: placeholder != null
              ? Center(child: placeholder)
              : ListView.builder(
                  controller: widget.controller,
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final t = filtered[i];
                    return InkWell(
                      onTap: () => Navigator.pop(context, t),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: t.priority.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t.name,
                                    style: AppTypography.body.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (t.accountName != null)
                                    Text(
                                      t.accountName!,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            StatusBadge.fromTicketStatus(t.status),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmailTile extends StatelessWidget {
  final EmailMessage email;
  const _EmailTile({required this.email});

  @override
  Widget build(BuildContext context) {
    final isInbound = email.isInbound;
    final timestamp = email.receivedAt ?? email.createdAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppLayout.borderRadiusLg,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isInbound
                      ? AppColors.primary100
                      : AppColors.success100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isInbound
                          ? LucideIcons.arrowDownLeft
                          : LucideIcons.arrowUpRight,
                      size: 11,
                      color: isInbound
                          ? AppColors.primary700
                          : AppColors.success700,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      isInbound
                          ? context.l10n.ticketsDetailEmailInbound
                          : context.l10n.ticketsDetailEmailOutbound,
                      style: AppTypography.caption.copyWith(
                        color: isInbound
                            ? AppColors.primary700
                            : AppColors.success700,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (timestamp != null)
                Text(
                  _timeAgo(context, timestamp),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (email.subject != null && email.subject!.isNotEmpty) ...[
            Text(
              email.subject!,
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
          ],
          if (email.fromAddress != null && email.fromAddress!.isNotEmpty)
            Text(
              context.l10n.ticketsDetailEmailFrom(email.fromAddress!),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          if (email.toAddresses.isNotEmpty)
            Text(
              context.l10n.ticketsDetailEmailTo(email.toAddresses.join(', ')),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          if (email.bodyText != null && email.bodyText!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              email.bodyText!,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
                height: 1.5,
              ),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final Map<String, dynamic> activity;
  const _ActivityTile({required this.activity});

  @override
  Widget build(BuildContext context) {
    final action = activity['action'] as String? ?? '';
    final actionDisplay = activity['action_display'] as String? ?? action;
    final freeText = (activity['description'] as String?) ?? '';
    final metadata = activity['metadata'] is Map<String, dynamic>
        ? activity['metadata'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final userEmail =
        activity['user_email'] as String? ??
        ((activity['user'] as Map<String, dynamic>?)?['email'] as String?);
    final humanized = activity['humanized_time'] as String?;
    final timestampRaw = activity['timestamp'] ?? activity['created_at'];
    DateTime? timestamp;
    if (timestampRaw is String) timestamp = DateTime.tryParse(timestampRaw);

    final detail = _describe(
      context.l10n,
      action,
      actionDisplay,
      metadata,
      freeText,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppLayout.borderRadiusMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _iconBg(action),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconFor(action), size: 14, color: _iconColor(action)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (userEmail != null && userEmail.isNotEmpty) userEmail,
                    if (humanized != null && humanized.isNotEmpty)
                      humanized
                    else if (timestamp != null)
                      _timeAgo(context, timestamp),
                  ].join(' · '),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build a human-readable line for the activity. Falls back to the
  /// backend's `action_display` for verbs we don't render specially.
  String _describe(
    AppLocalizations l,
    String action,
    String actionDisplay,
    Map<String, dynamic> meta,
    String freeText,
  ) {
    String beforeAfter(String fallback) {
      final before = meta['before']?.toString();
      final after = meta['after']?.toString();
      if (before != null && after != null) {
        return '$fallback: $before → $after';
      }
      return fallback;
    }

    switch (action) {
      case 'CREATE':
        return l.ticketsDetailActCreated;
      case 'UPDATE':
        final changes = meta['changes'];
        if (changes is Map<String, dynamic> && changes.isNotEmpty) {
          final fields = changes.keys
              .map((k) => k.replaceAll('_', ' '))
              .join(', ');
          return l.ticketsDetailActUpdatedFields(fields);
        }
        return l.ticketsDetailActUpdated;
      case 'STATUS_CHANGED':
        return beforeAfter(l.ticketsDetailActStatusChanged);
      case 'PRIORITY_CHANGED':
        return beforeAfter(l.ticketsDetailActPriorityChanged);
      case 'COMMENT':
        return l.ticketsDetailActComment;
      case 'ASSIGN':
        return l.ticketsDetailActAssign;
      case 'LINKED_SOLUTION':
        return l.ticketsDetailActLinkedSolution;
      case 'UNLINKED_SOLUTION':
        return l.ticketsDetailActUnlinkedSolution;
      case 'LINKED_PARENT':
        return l.ticketsDetailActLinkedParent;
      case 'UNLINKED_PARENT':
        return l.ticketsDetailDetachedFromParent;
      case 'WATCHED':
        return l.ticketsDetailActWatched;
      case 'UNWATCHED':
        return l.ticketsDetailActUnwatched;
      case 'MENTIONED':
        return l.ticketsDetailActMentioned;
      case 'APPROVAL_REQUESTED':
        return l.ticketsDetailActApprovalRequested;
      case 'APPROVED':
        return l.ticketsDetailActApproved;
      case 'REJECTED':
        return l.ticketsDetailActRejected;
      case 'APPROVAL_CANCELLED':
        return l.ticketsDetailActApprovalCancelled;
      case 'ESCALATED':
        return l.ticketsDetailActEscalated;
      case 'REOPENED':
        return l.ticketsDetailActReopened;
      case 'MERGED':
        return l.ticketsDetailActMerged;
      case 'MERGE_TARGET':
        return l.ticketsDetailActMergeTarget;
      case 'UNMERGED':
      case 'UNMERGE_TARGET':
        return l.ticketsDetailActUnmerged;
      case 'ROUTED':
        return l.ticketsDetailActRouted;
      case 'TIME_LOGGED':
        final minutes = meta['minutes'];
        if (minutes is num) {
          return l.ticketsDetailActTimeLoggedMinutes(minutes.round());
        }
        return l.ticketsDetailActTimeLogged;
      case 'PARENT_CLOSED_CASCADE':
        return l.ticketsDetailActParentCascade;
      default:
        if (freeText.isNotEmpty) return freeText;
        return actionDisplay.isNotEmpty ? actionDisplay : action;
    }
  }

  IconData _iconFor(String action) {
    switch (action) {
      case 'CREATE':
        return LucideIcons.plus;
      case 'STATUS_CHANGED':
        return LucideIcons.circleDot;
      case 'PRIORITY_CHANGED':
        return LucideIcons.flag;
      case 'COMMENT':
        return LucideIcons.messageSquare;
      case 'ASSIGN':
        return LucideIcons.users;
      case 'LINKED_SOLUTION':
      case 'UNLINKED_SOLUTION':
        return LucideIcons.bookOpen;
      case 'LINKED_PARENT':
      case 'UNLINKED_PARENT':
        return LucideIcons.gitBranch;
      case 'WATCHED':
      case 'UNWATCHED':
        return LucideIcons.eye;
      case 'MENTIONED':
        return LucideIcons.atSign;
      case 'APPROVAL_REQUESTED':
      case 'APPROVED':
      case 'REJECTED':
      case 'APPROVAL_CANCELLED':
        return LucideIcons.shieldCheck;
      case 'ESCALATED':
        return LucideIcons.alertTriangle;
      case 'REOPENED':
        return LucideIcons.refreshCw;
      case 'MERGED':
      case 'MERGE_TARGET':
      case 'UNMERGED':
      case 'UNMERGE_TARGET':
        return LucideIcons.gitMerge;
      case 'TIME_LOGGED':
        return LucideIcons.clock;
      case 'DELETE':
        return LucideIcons.trash2;
      default:
        return LucideIcons.activity;
    }
  }

  Color _iconColor(String action) {
    switch (action) {
      case 'ESCALATED':
      case 'REJECTED':
      case 'DELETE':
        return AppColors.danger600;
      case 'APPROVED':
      case 'CREATE':
        return AppColors.success600;
      case 'PRIORITY_CHANGED':
      case 'APPROVAL_REQUESTED':
        return AppColors.warning600;
      default:
        return AppColors.primary600;
    }
  }

  Color _iconBg(String action) {
    switch (action) {
      case 'ESCALATED':
      case 'REJECTED':
      case 'DELETE':
        return AppColors.danger50;
      case 'APPROVED':
      case 'CREATE':
        return AppColors.success50;
      case 'PRIORITY_CHANGED':
      case 'APPROVAL_REQUESTED':
        return AppColors.warning50;
      default:
        return AppColors.primary50;
    }
  }
}

/// One other open ticket on the same account.
///
/// A full-width tap target at 48px, because the card sits low on a phone
/// screen and a thumb reaching it is aiming without looking.
class _AlsoOpenRow extends StatelessWidget {
  const _AlsoOpenRow({required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: ticket.status.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.name,
                    style: AppTypography.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${ticket.status.label} · ${ticket.priority.label}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// One macro action on the composer, which can be taken off before sending.
///
/// Not an [InputChip]: a chip holds its label to one line and fades the rest,
/// so "Assign: A, B, C" was cut off at 390px. Here the label wraps, so what
/// will apply can be read in full, and the remove button keeps a 48px target.
class _MacroActionChip extends StatelessWidget {
  const _MacroActionChip({super.key, required this.label, this.onRemove});

  final String label;

  /// Null while the reply is sending, which disables the remove button.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: AppLayout.borderRadiusMd,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, style: AppTypography.labelSmall)),
          IconButton(
            onPressed: onRemove,
            tooltip: context.l10n.ticketsDetailDoNotApply,
            icon: const Icon(LucideIcons.x, size: 16),
          ),
        ],
      ),
    );
  }
}
