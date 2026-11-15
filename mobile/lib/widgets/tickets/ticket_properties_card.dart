import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/ticket.dart';
import '../../l10n/l10n.dart';
import '../../services/app_language.dart';

/// Sidebar-style card showing ticket SLA status, escalation count, and
/// watcher count. The same surface the web app shows in its right rail.
///
/// Deadlines and breach flags come from the backend so this view stays in
/// sync with whatever the SLA calculator (business hours, paused windows)
/// decided. Pause icon appears when `slaPausedAt != null`.
class TicketPropertiesCard extends StatelessWidget {
  final Ticket ticket;
  final int? watcherCount;
  final bool isWatching;

  const TicketPropertiesCard({
    super.key,
    required this.ticket,
    this.watcherCount,
    this.isWatching = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
            l10n.ticketsPanelPropsHeading,
            style: AppTypography.overline.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _slaRow(
            l10n,
            label: l10n.ticketsPanelPropsFirstResponse,
            deadline: ticket.firstResponseSlaDeadline,
            met: ticket.firstResponseAt != null,
            metAt: ticket.firstResponseAt,
            breached:
                ticket.isFirstResponseSlaBreached ||
                ticket.isFirstResponseSlaBreachedFromApi,
            atRisk: ticket.isFirstResponseSlaAtRisk,
            paused: ticket.slaPausedAt != null,
          ),
          const Divider(height: 20),
          _slaRow(
            l10n,
            label: l10n.ticketsPanelPropsResolution,
            deadline: ticket.resolutionSlaDeadline,
            met: ticket.resolvedAt != null,
            metAt: ticket.resolvedAt,
            breached: ticket.isResolutionSlaBreachedFromApi,
            atRisk: ticket.isResolutionSlaAtRisk,
            paused: ticket.slaPausedAt != null,
          ),
          if (ticket.escalationCount > 0) ...[
            const Divider(height: 20),
            _iconRow(
              icon: LucideIcons.alertTriangle,
              iconColor: AppColors.danger600,
              label: l10n.ticketsPanelPropsEscalated,
              trailing: l10n.ticketsPanelPropsEscalationCount(
                ticket.escalationCount,
              ),
              trailingColor: AppColors.danger600,
            ),
          ],
          if (watcherCount != null) ...[
            const Divider(height: 20),
            _iconRow(
              icon: isWatching ? LucideIcons.eye : LucideIcons.eyeOff,
              iconColor: isWatching
                  ? AppColors.primary600
                  : AppColors.textSecondary,
              label: isWatching
                  ? l10n.ticketsPanelPropsWatching
                  : l10n.ticketsPanelPropsWatchers,
              trailing: '$watcherCount',
              trailingColor: AppColors.textPrimary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _slaRow(
    AppLocalizations l10n, {
    required String label,
    required DateTime? deadline,
    required bool met,
    required DateTime? metAt,
    required bool breached,
    required bool atRisk,
    required bool paused,
  }) {
    final IconData icon;
    final Color iconColor;
    final String stateText;
    final Color stateColor;

    if (met) {
      icon = LucideIcons.checkCircle;
      iconColor = AppColors.success600;
      stateText = l10n.ticketsPanelPropsMet;
      stateColor = AppColors.success600;
    } else if (breached) {
      icon = LucideIcons.alertCircle;
      iconColor = AppColors.danger600;
      stateText = deadline != null
          ? l10n.ticketsPanelPropsBreached
          : l10n.ticketsPanelPropsOverdue;
      stateColor = AppColors.danger600;
    } else if (paused) {
      icon = LucideIcons.pauseCircle;
      iconColor = AppColors.warning600;
      stateText = l10n.ticketsPanelPropsPaused;
      stateColor = AppColors.warning600;
    } else if (deadline != null) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative) {
        icon = LucideIcons.clock;
        iconColor = AppColors.danger600;
        stateText = l10n.ticketsPanelPropsOverdue;
        stateColor = AppColors.danger600;
      } else if (atRisk) {
        // The amber band. Still counts down rather than switching to a word,
        // because how long is left is the thing worth acting on.
        icon = LucideIcons.alertTriangle;
        iconColor = AppColors.warning600;
        stateText = l10n.ticketsPanelPropsIn(_formatDuration(l10n, remaining));
        stateColor = AppColors.warning600;
      } else {
        icon = LucideIcons.clock;
        iconColor = AppColors.textSecondary;
        stateText = l10n.ticketsPanelPropsIn(_formatDuration(l10n, remaining));
        stateColor = AppColors.textPrimary;
      }
    } else {
      icon = LucideIcons.minusCircle;
      iconColor = AppColors.gray400;
      stateText = l10n.ticketsPanelPropsNotSet;
      stateColor = AppColors.textSecondary;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _subtitle(l10n, deadline: deadline, met: met, metAt: metAt),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Text(
          stateText,
          style: AppTypography.caption.copyWith(
            color: stateColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _subtitle(
    AppLocalizations l10n, {
    required DateTime? deadline,
    required bool met,
    required DateTime? metAt,
  }) {
    if (met && metAt != null) {
      return l10n.ticketsPanelPropsReplied(_formatDate(metAt));
    }
    if (deadline != null) {
      return l10n.ticketsPanelPropsDue(_formatDate(deadline));
    }
    return l10n.ticketsPanelPropsNoSla;
  }

  Widget _iconRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String trailing,
    required Color trailingColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: AppTypography.label)),
        Text(
          trailing,
          style: AppTypography.label.copyWith(
            color: trailingColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatDuration(AppLocalizations l10n, Duration d) {
    if (d.inDays > 0) {
      return l10n.ticketsPanelPropsDaysHours(d.inDays, d.inHours.remainder(24));
    }
    if (d.inHours > 0) {
      return l10n.ticketsPanelPropsHoursMinutes(
        d.inHours,
        d.inMinutes.remainder(60),
      );
    }
    return l10n.ticketsPanelPropsMinutes(d.inMinutes);
  }

  String _formatDate(DateTime t) =>
      '${localDateFormat('MMM d', 'MMMd').format(t)}, '
      '${localDateFormat('HH:mm', 'Hm').format(t)}';
}
