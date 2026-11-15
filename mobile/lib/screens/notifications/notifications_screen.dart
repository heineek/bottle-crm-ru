import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/l10n.dart';
import '../../services/app_language.dart';
import '../../core/theme/theme.dart';
import '../../data/models/app_notification.dart';
import '../../providers/notifications_provider.dart';
import '../../providers/org_modules_provider.dart';
import '../../widgets/common/common.dart';

/// The notification feed.
///
/// Two things about the real data shaped this. Only the verbs in
/// [producedVerbs] get copy; anything else reads as a plain sentence rather
/// than a raw identifier. And the stored link is a database value: it is
/// matched against known shapes ([AppNotification.destinationPath]) and
/// otherwise ignored, so a row can never navigate this app somewhere of its
/// own choosing.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = true;

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(notificationsProvider);
    final unreadCount = feedAsync.value?.unreadCount ?? 0;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.appNotifications),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text(context.l10n.appMarkAllRead),
            ),
        ],
      ),
      body: feedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: '$error',
          onRetry: () => ref.read(notificationsProvider.notifier).refresh(),
        ),
        data: _body,
      ),
    );
  }

  Widget _body(NotificationFeed feed) {
    final visible = _unreadOnly ? feed.unread : feed.items;

    return RefreshIndicator(
      onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _filterBar(feed),
          if (visible.isEmpty)
            _empty(feed)
          else ...[
            ...visible.map(_row),
            if (feed.legacyLinkCount > 0) _legacyNote(feed.legacyLinkCount),
          ],
        ],
      ),
    );
  }

  Widget _filterBar(NotificationFeed feed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              feed.unreadCount == 0
                  ? context.l10n.appNothingUnread
                  : context.l10n.appUnreadCount(feed.unreadCount),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          // A segmented control rather than a checkbox: two named states read
          // faster than one negated one.
          SegmentedButton<bool>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            segments: [
              ButtonSegment(
                value: true,
                label: Text(context.l10n.appUnreadTab),
              ),
              ButtonSegment(value: false, label: Text(context.l10n.appAllTab)),
            ],
            selected: {_unreadOnly},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _unreadOnly = s.first),
          ),
        ],
      ),
    );
  }

  Widget _empty(NotificationFeed feed) {
    final nothingAtAll = feed.items.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      child: Column(
        children: [
          Icon(LucideIcons.bellOff, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            nothingAtAll
                ? context.l10n.appNoNotifications
                : context.l10n.appNothingUnread,
            style: AppTypography.h3,
          ),
          const SizedBox(height: 6),
          Text(
            ref.watch(moduleOnProvider('tickets'))
                ? context.l10n.appNotificationsHintTickets
                : context.l10n.appNotificationsHint,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (!nothingAtAll && _unreadOnly)
            OutlinedButton(
              onPressed: () => setState(() => _unreadOnly = false),
              child: Text(context.l10n.appShowReadToo),
            ),
        ],
      ),
    );
  }

  Widget _row(AppNotification n) {
    final destination = n.destinationPath;
    final automation = n.verb.startsWith('automation.')
        ? n.automationText() ?? appL10n.appAutomationSentNotification
        : null;
    return InkWell(
      // Tapping opens the ticket and marks it read. With no resolvable ticket
      // the row still marks read, because otherwise the only way to clear an
      // orphaned row would be Mark all read.
      onTap: () => _open(n, destination),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(bottom: BorderSide(color: AppColors.gray100)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread carried by a dot in its own column so every row's text
            // starts on the same x. Ink rather than a warning colour: on a
            // feed that is unread by default, an alarm colour on all of them
            // says "urgent" about everything and so about nothing.
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 8),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: n.isUnread
                      ? AppColors.textPrimary
                      : Colors.transparent,
                ),
              ),
            ),
            if (automation == null)
              UserAvatar(name: n.displayActorName, size: AvatarSize.sm)
            else
              _AutomationIcon(verb: n.verb),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (automation != null)
                    ..._automationLines(n, automation, destination)
                  else
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: n.displayActorName,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: ' ${n.verbPhrase} ',
                            style: AppTypography.body,
                          ),
                          TextSpan(
                            text: n.entityName ?? _missingName(n.verb),
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w500,
                              color: destination != null
                                  ? AppColors.primary600
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if ((n.commentExcerpt ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    // Somebody else's words, quoted rather than restyled as a
                    // card. Interpolated as text and never as markup.
                    Container(
                      padding: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: AppColors.border, width: 2),
                        ),
                      ),
                      child: Text(
                        n.commentExcerpt!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  // Wrap, not Row: the verb note is long, and at a scaled-up
                  // system font the two sit wider than the column they are in.
                  // A Row overflows there; this takes a second line.
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(
                        _relative(n.createdAt),
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (!n.isKnownVerb)
                        Text(
                          context.l10n.appNoProducer(n.verb),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Who, the sentence, and for a message the rule that sent it. The sentence
  /// already names what the row opens, so no entity name follows it; it takes
  /// the link colour when there is somewhere to go. Every string is server
  /// data, shown as text.
  List<Widget> _automationLines(
    AppNotification n,
    String text,
    String? destination,
  ) {
    final source = n.automationSource;
    return [
      Text(
        n.displayActorName,
        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 2),
      Text(
        text,
        style: AppTypography.body.copyWith(
          height: 1.45,
          color: destination != null ? AppColors.primary600 : null,
        ),
      ),
      if (source != null) ...[
        const SizedBox(height: 4),
        Text(
          source,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    ];
  }

  /// The ticket wording only fits the ticket verbs; any other row with no
  /// name shows none.
  static String _missingName(String verb) =>
      verb.startsWith('case.') || verb.startsWith('support.')
      ? appL10n.appUnnamedTicketLower
      : '';

  Widget _legacyNote(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Text(
        appL10n.appLegacyLinks(count),
        style: AppTypography.caption.copyWith(
          color: AppColors.textTertiary,
          height: 1.5,
        ),
      ),
    );
  }

  Future<void> _open(AppNotification n, String? destination) async {
    // Navigate first. Marking read is optimistic in the provider, so the dot
    // has already cleared, and waiting on the round-trip before opening the
    // ticket would put a stall between the tap and the screen.
    if (destination != null) context.push(destination);
    final response = await ref
        .read(notificationsProvider.notifier)
        .markRead(n.id);
    if (!mounted || response.success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(response.message ?? appL10n.appMarkReadFailed),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _markAllRead() async {
    final response = await ref
        .read(notificationsProvider.notifier)
        .markAllRead();
    if (!mounted || response.success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(response.message ?? appL10n.appMarkAllReadFailed),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// "4m ago" / "3h ago" / a date once it stops being useful as an interval.
  String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return appL10n.appRelativeJustNowLower;
    if (diff.inMinutes < 60) {
      return appL10n.appRelativeMinutesAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) return appL10n.appRelativeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return appL10n.appRelativeDaysAgo(diff.inDays);
    return localDateFormat('d MMM', 'MMMd').format(when);
  }
}

/// Stands where the avatar does on a row an automation rule raised.
class _AutomationIcon extends StatelessWidget {
  const _AutomationIcon({required this.verb});

  final String verb;

  @override
  Widget build(BuildContext context) => Container(
    width: AvatarSize.sm.size,
    height: AvatarSize.sm.size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: AppColors.gray100, shape: BoxShape.circle),
    child: Icon(
      switch (verb) {
        'automation.paused' => LucideIcons.circlePause,
        'automation.message' => LucideIcons.zap,
        'automation.failed' || 'automation.limit' => LucideIcons.triangleAlert,
        _ => LucideIcons.bell,
      },
      size: 16,
      color: AppColors.textSecondary,
    ),
  );
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
              child: Text(context.l10n.appTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}
