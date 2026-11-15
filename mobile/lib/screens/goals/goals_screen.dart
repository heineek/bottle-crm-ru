import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/deal.dart' show Currency;
import '../../data/models/sales_goal.dart';
import '../../providers/auth_provider.dart';
import '../../providers/goals_provider.dart';
import '../../providers/settings_provider.dart';
import '../../routes/app_router.dart';
import '../../widgets/common/badge.dart';
import '../../l10n/l10n.dart';

/// Sales goals, and how far along each one is.
///
/// Everything numeric here is the server's. `progress_value` and
/// `progress_percent` are computed over deals in won stages in the period,
/// including ones assigned to people this app never fetches, so nothing on this
/// screen recomputes them.
///
/// Reading is open to any member and the API narrows a non-admin to their own
/// goals and their teams'. Creating, editing and deleting are admin-only, so
/// the compose button and the row chevrons appear for an admin alone. Hiding
/// them is not what keeps a member out.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _apply(GoalFilters filters) {
    ref.read(goalsProvider.notifier).applyFilters(filters);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(goalsProvider);
    final isAdmin = ref.watch(isOrgAdminProvider);
    // Each goal carries its own currency, and a REVENUE figure is printed in
    // it. This is the org's, read from the org settings (which any member may
    // fetch) rather than the stored org record, whose `currency_symbol` no
    // endpoint fills in, and it is only the fallback for a goal from a server
    // that sends no currency.
    final symbol =
        ref.watch(orgSettingsProvider).value?.currencySymbol ??
        Currency.usd.symbol;

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.goalsTitle),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.history),
            tooltip: context.l10n.goalsHistoryTooltip,
            onPressed: () => context.push(AppRoutes.goalHistory),
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              tooltip: context.l10n.goalsNewTooltip,
              onPressed: () => context.push(AppRoutes.goalNew),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorState(
          onRetry: () => ref.read(goalsProvider.notifier).refresh(),
        ),
        data: (data) {
          // An unfiltered empty list is "there are no goals"; a filtered one is
          // "none match", and saying the first when the second is true sends
          // somebody off to create a goal they already have.
          if (data.goals.isEmpty && !data.filters.isFiltered) {
            return _EmptyState(isAdmin: isAdmin);
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(goalsProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                _Filters(
                  controller: _search,
                  filters: data.filters,
                  onChanged: _apply,
                ),
                if (data.goals.isEmpty)
                  _NoMatchState(
                    onClear: () {
                      _search.clear();
                      _apply(const GoalFilters());
                    },
                  )
                else ...[
                  _Summary(totals: data.totals, symbol: symbol),
                  _SectionHeader(context.l10n.goalsSectionGoals),
                  for (final goal in data.goals)
                    _GoalRow(
                      goal: goal,
                      symbol: symbol,
                      onTap: isAdmin
                          ? () => context.push(AppRoutes.goalEditFor(goal.id))
                          : null,
                    ),
                  _Leaderboard(rows: data.leaderboard, symbol: symbol),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A target or an attainment, in the unit its own goal type is measured in.
///
/// Takes the goal type rather than a bare `isMoney` flag, which is what it used
/// to take: "not money" was rendered as deals, so the moment a third type
/// arrived a quota of forty logged activities printed as "40 deals".
///
/// `compactCurrency` keeps a six-figure quota on one line at 390px, where the
/// full number wraps.
///
/// [symbol] is the goal's own currency, through [goalSymbol]: the server counts
/// a REVENUE goal only in its currency, so pricing it in the org's would put
/// the wrong sign on a correct number.
String formatGoalValue(
  double value, {
  required String goalType,
  required String symbol,
}) {
  if (goalType == 'DEALS_CLOSED') {
    return appL10n.goalsDealsCount(value.round());
  }
  if (goalType == 'ACTIVITIES') {
    return appL10n.goalsActivitiesCount(value.round());
  }
  return NumberFormat.compactCurrency(
    symbol: symbol,
    decimalDigits: 0,
  ).format(value);
}

/// The symbol for a goal's currency [code], or [fallback] (the org's) when the
/// server sent none.
String goalSymbol(String? code, String fallback) =>
    code == null ? fallback : Currency.symbolFor(code);

Color goalStatusColour(String status) {
  switch (status) {
    case 'completed':
      return AppColors.success600;
    case 'on_track':
      return AppColors.primary600;
    case 'at_risk':
      return AppColors.warning600;
    case 'behind':
      return AppColors.danger600;
    default:
      return AppColors.gray500;
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.totals, required this.symbol});

  final GoalTotals totals;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String each(double Function(GoalMoneyTotal) pick) => totals.money
        .map(
          (m) => formatGoalValue(
            pick(m),
            goalType: 'REVENUE',
            symbol: goalSymbol(m.currency, symbol),
          ),
        )
        .join(' · ');
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      margin: const EdgeInsets.only(bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row: four stat pairs with their labels do not fit on one
          // line at 390px, and a Row would overflow rather than wrap.
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _Stat(value: '${totals.active}', label: l10n.goalsStatActive),
              // One figure per currency, never added together: there are no
              // exchange rates. Absent when no active goal is revenue.
              if (totals.money.isNotEmpty) ...[
                _Stat(
                  value: each((m) => m.target),
                  label: l10n.goalsStatTargeted,
                ),
                _Stat(
                  value: each((m) => m.achieved),
                  label: l10n.goalsStatAchieved,
                ),
              ],
              _Stat(
                value: '${totals.behind}',
                label: l10n.goalsStatBehind,
                colour: totals.behind > 0 ? AppColors.danger600 : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            // Said out loud because the numbers above would otherwise look like
            // they cover the list below, and the list shows retired goals too.
            totals.count == totals.active
                ? l10n.goalsTotalsAll
                : l10n.goalsTotalsActive(totals.active, totals.count),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.colour});

  final String value;
  final String label;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.h2.copyWith(
            fontWeight: FontWeight.w600,
            color: colour,
          ),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
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
        title,
        style: AppTypography.overline.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal, required this.symbol, this.onTap});

  final SalesGoal goal;
  final String symbol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final own = goalSymbol(goal.currency, symbol);
    final achieved = formatGoalValue(
      goal.progressValue,
      goalType: goal.goalType,
      symbol: own,
    );
    final target = formatGoalValue(
      goal.targetValue,
      goalType: goal.goalType,
      symbol: own,
    );
    final colour = goalStatusColour(goal.status);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: AppColors.surface,
        margin: const EdgeInsets.only(bottom: 1),
        // 12 top and bottom around a three-line body clears 44px comfortably,
        // which matters because the whole row is the tap target for an admin.
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    goal.name,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: goal.isActive
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${goal.progressPercent}%',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colour,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              context.l10n.goalsRowProgress(achieved, target, goal.targetLabel),
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (goal.progressPercent / 100).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: AppColors.gray200,
                valueColor: AlwaysStoppedAnimation(colour),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBadge(label: goalStatusLabel(goal.status), color: colour),
                if (!goal.isActive)
                  StatusBadge(
                    label: context.l10n.goalsRetired,
                    color: AppColors.gray500,
                  ),
                // Named on the row because a weighted goal's progress does not
                // add up to the deals behind it, and somebody checking the
                // arithmetic against the pipeline needs to know that before
                // they file a bug.
                if (goal.weightedTypeCount > 0)
                  StatusBadge(
                    label: context.l10n.goalsWeighted(goal.weightedTypeCount),
                    color: AppColors.gray500,
                  ),
                Text(
                  '${goalPeriodLabel(goal.periodType)} · '
                  '${goalDateRange(goal.periodStart, goal.periodEnd)}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The attainment board.
///
/// Narrowed server-side by the same rule as the list, so a member sees their
/// own standing and their teams' rather than the whole org's. That makes an
/// empty board an ordinary outcome for somebody with no current monthly goal,
/// which is why it says why instead of rendering a bare heading.
class _Leaderboard extends StatelessWidget {
  const _Leaderboard({required this.rows, required this.symbol});

  final List<GoalLeaderRow> rows;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(context.l10n.goalsSectionLeaderboard),
        if (rows.isEmpty)
          Container(
            color: AppColors.surface,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Text(
              context.l10n.goalsLeaderboardEmpty,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          )
        else ...[
          for (final row in rows)
            Container(
              color: AppColors.surface,
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${row.rank}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.user,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // In the row's own unit: the board mixes revenue
                        // goals, each in its currency, with count goals.
                        Text(
                          context.l10n.goalsAchievedOfTarget(
                            formatGoalValue(
                              row.achieved,
                              goalType: row.goalType,
                              symbol: goalSymbol(row.currency, symbol),
                            ),
                            formatGoalValue(
                              row.target,
                              goalType: row.goalType,
                              symbol: goalSymbol(row.currency, symbol),
                            ),
                          ),
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    // Uncapped on purpose. The model caps `progress_percent` at
                    // 100 and the board carries its own, because 104% is the
                    // interesting number on a ranking.
                    '${row.percent}%',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: row.percent >= 100
                          ? AppColors.success600
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              context.l10n.goalsLeaderboardNote,
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.target, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(context.l10n.goalsEmptyTitle, style: AppTypography.h3),
            const SizedBox(height: 8),
            Text(
              isAdmin
                  ? context.l10n.goalsEmptyAdmin
                  // Not "there are none": the list is narrowed to this person,
                  // so an org goal assigned to somebody else is invisible here
                  // and saying otherwise would be false.
                  : context.l10n.goalsEmptyMember,
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

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
            Text(context.l10n.goalsLoadFailed, style: AppTypography.body),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.goalsTryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

/// Search and the two window choices, matching the web filter bar.
///
/// The API does the filtering; nothing here sifts rows already fetched, so a
/// search on the phone and the same search on the web return the same set.
///
/// Search submits on done rather than on every keystroke: each apply is a round
/// trip, and firing one per character would be a request per letter on a phone
/// connection.
class _Filters extends StatelessWidget {
  const _Filters({
    required this.controller,
    required this.filters,
    required this.onChanged,
  });

  final TextEditingController controller;
  final GoalFilters filters;
  final ValueChanged<GoalFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) => onChanged(filters.copyWith(query: value)),
            decoration: InputDecoration(
              hintText: context.l10n.goalsSearchHint,
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              suffixIcon: filters.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(LucideIcons.x, size: 18),
                      tooltip: context.l10n.goalsClearSearch,
                      onPressed: () {
                        controller.clear();
                        onChanged(filters.copyWith(query: ''));
                      },
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: context.l10n.goalsRunningToday,
                  selected: filters.window == 'current',
                  onSelected: (on) =>
                      onChanged(filters.copyWith(window: on ? 'current' : '')),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: context.l10n.goalsNotPaused,
                  selected: filters.window == 'active',
                  onSelected: (on) =>
                      onChanged(filters.copyWith(window: on ? 'active' : '')),
                ),
                for (final period in goalPeriodTypes) ...[
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: goalPeriodLabel(period),
                    selected: filters.periodType == period,
                    onSelected: (on) => onChanged(
                      filters.copyWith(periodType: on ? period : ''),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    // Standard density and a padded tap target on purpose. `VisualDensity
    // .compact` drew these at 34px, under the roughly 44px a thumb needs, and
    // they sit in a horizontal scroller where a mis-tap scrolls the row instead
    // of toggling the filter.
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: false,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

/// The list came back empty because of the filter, not because the org has no
/// goals. Offers the way out rather than only naming the problem.
class _NoMatchState extends StatelessWidget {
  const _NoMatchState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Column(
        children: [
          Icon(LucideIcons.target, size: 36, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            context.l10n.goalsNoMatchTitle,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.goalsNoMatchBody,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onClear,
            child: Text(context.l10n.goalsClearFilter),
          ),
        ],
      ),
    );
  }
}
