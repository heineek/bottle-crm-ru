import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/api_config.dart';
import '../../core/theme/theme.dart';
import '../../data/api/schema.g.dart' as api;
import '../../data/models/attachment.dart';
import '../../data/models/comment.dart';
import '../../data/models/project.dart';
import '../../data/models/task.dart';
import '../../data/models/time_entry.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/invoices_provider.dart';
import '../../providers/lookup_provider.dart';
import '../../providers/org_modules_provider.dart';
import '../../providers/projects_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../routes/app_routes.dart';
import '../../services/attachment_upload.dart';
import '../../widgets/cards/task_row.dart';
import '../../widgets/common/common.dart';
import '../../widgets/time/bill_time_sheet.dart';
import '../../widgets/time/time_entry_parts.dart';
import 'invoice_amount_sheet.dart';
import 'project_parts.dart';

/// One project: Overview (burn, budget, dates, people, rates), Tasks, Time,
/// Invoices, Files and Comments, the sections the web page has. A section whose
/// module is off is left out, as the web leaves it out.
///
/// Edit and log time follow `can_edit`, delete `can_delete`, and the billing
/// actions `can_bill` (org admins). The API enforces every one of them.
class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  Project? _project;
  bool _loading = true;
  bool _notFound = false;

  List<Task>? _tasks;
  List<TimeEntry>? _entries;
  bool _timeBusy = false;
  Timer? _tick;

  final _note = TextEditingController();
  bool _addingNote = false;
  bool _uploading = false;

  ProjectsNotifier get _api => ref.read(projectsProvider.notifier);

  @override
  void initState() {
    super.initState();
    _load();
    // Redraws a running timer's clock without refetching anything.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && (_entries ?? const []).any((e) => e.isRunning)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var notFound = false;
    final p = await _api.getProject(
      widget.projectId,
      onNotFound: () => notFound = true,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (p != null) {
        _project = p;
      } else if (_project == null) {
        _notFound = notFound;
      }
    });
    if (p == null) return;
    await Future.wait([
      if (ref.read(moduleOnProvider('tasks'))) _loadTasks(),
      if (ref.read(moduleOnProvider('timesheet'))) _loadTime(),
    ]);
  }

  Future<void> _loadTasks() async {
    final tasks = await _api.fetchTasks(widget.projectId);
    if (mounted && tasks != null) setState(() => _tasks = tasks);
  }

  Future<void> _loadTime() async {
    final entries = await _api.fetchTimeEntries(widget.projectId);
    if (mounted && entries != null) setState(() => _entries = entries);
  }

  void _snack(String message, {bool danger = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: danger ? AppColors.danger600 : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final p = _project;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(
                icon: LucideIcons.folderKanban,
                title: _notFound
                    ? context.l10n.projectsNotFound
                    : context.l10n.projectsFormLoadFailed,
                description: _notFound
                    ? context.l10n.projectsNotFoundBody
                    : context.l10n.projectsCheckConnection,
                actionLabel: context.l10n.projectsTryAgain,
                onAction: () {
                  setState(() => _loading = true);
                  _load();
                },
              ),
      );
    }

    final tasksOn = ref.watch(moduleOnProvider('tasks'));
    final timeOn = ref.watch(moduleOnProvider('timesheet'));
    final invoicesOn = ref.watch(moduleOnProvider('invoices'));
    final l10n = context.l10n;
    final tabs = <(String, Widget Function())>[
      (l10n.projectsTabOverview, () => _overview(p)),
      if (tasksOn) (l10n.projectsTabTasks, () => _tasksTab(p)),
      if (timeOn) (l10n.projectsTabTime, () => _timeTab(p)),
      if (invoicesOn) (l10n.projectsTabInvoices, () => _invoicesTab(p)),
      (
        p.attachments.isEmpty
            ? l10n.projectsTabFiles
            : l10n.projectsTabFilesCount(p.attachments.length),
        () => _filesTab(p),
      ),
      (
        p.comments.isEmpty
            ? l10n.projectsTabComments
            : l10n.projectsTabCommentsCount(p.comments.length),
        () => _notesTab(p),
      ),
    ];

    return DefaultTabController(
      // A module switched while the page is open changes the tab count.
      key: ValueKey('$tasksOn$timeOn$invoicesOn'),
      length: tabs.length,
      child: Scaffold(
        backgroundColor: AppColors.surfaceDim,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            tooltip: l10n.commonBack,
            onPressed: () => context.pop(),
          ),
          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (p.canEdit)
              IconButton(
                icon: const Icon(LucideIcons.pencil, size: 20),
                tooltip: l10n.projectsFormEditTitle,
                onPressed: _edit,
              ),
            if (p.canDelete)
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 20),
                tooltip: l10n.projectsDelete,
                onPressed: _confirmDelete,
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary600,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary600,
            labelStyle: AppTypography.label,
            tabs: [for (final t in tabs) Tab(text: t.$1)],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$2()]),
      ),
    );
  }

  Widget _scroll(List<Widget> children) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: children,
    ),
  );

  // ---------------------------------------------------------------------------
  // Overview
  // ---------------------------------------------------------------------------

  bool get _billingOn =>
      (_project?.canBill ?? false) && ref.watch(moduleOnProvider('invoices'));

  /// Bill time also needs Timesheet, and a project whose time can be billed:
  /// a non-billable project's entries never are, as the web has it.
  bool get _billTimeOn =>
      _billingOn &&
      ref.watch(moduleOnProvider('timesheet')) &&
      _project!.billingType != ProjectBillingType.nonBillable &&
      !_project!.isRetainer;

  Widget _overview(Project p) {
    final l10n = context.l10n;
    final dealsOn = ref.watch(moduleOnProvider('deals'));
    final defs =
        ref.watch(customFieldDefinitionsProvider('Project')).value ?? const [];
    return _scroll([
      Text(p.name, style: AppTypography.h2),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ProjectStatusPill(project: p),
          StatusBadge(
            label: billingTypeLabel(p.billingType),
            color: AppColors.gray600,
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (p.account != null)
        ProjectFact(
          icon: LucideIcons.building2,
          label: l10n.projectsFactAccount,
          value: p.account!.name.isEmpty
              ? l10n.projectsFormAccount
              : p.account!.name,
          onTap: () => context.push(
            AppRoutes.accountDetail.replaceFirst(':id', p.account!.id),
          ),
        ),
      if (p.deal != null)
        ProjectFact(
          icon: LucideIcons.briefcase,
          label: l10n.projectsFactFromDeal,
          value: p.deal!.name.isEmpty ? l10n.projectsDeal : p.deal!.name,
          onTap: dealsOn ? () => context.push('/deals/${p.deal!.id}') : null,
        ),
      // Text only: neither client has an estimate page to open.
      if (p.estimateNumber != null)
        ProjectFact(
          icon: LucideIcons.fileCheck,
          label: l10n.projectsFactFromEstimate,
          value: p.estimateNumber!,
        ),
      const SizedBox(height: 12),
      ..._billingActions(p),
      if (p.isRetainer)
        ProjectCard(title: l10n.projectsBillingRetainer, child: _retainer(p)),
      ProjectCard(title: l10n.projectsBudget, child: _budget(p)),
      ProjectCard(
        title: l10n.projectsDates,
        child: Column(
          children: [
            ProjectFact(
              icon: LucideIcons.calendar,
              label: l10n.projectsFactStart,
              value: p.startDate == null
                  ? l10n.projectsNotSet
                  : shortDate(p.startDate!),
            ),
            ProjectFact(
              icon: LucideIcons.calendarClock,
              label: l10n.projectsFactDue,
              value: p.dueDate == null
                  ? l10n.projectsNotSet
                  : shortDate(p.dueDate!),
            ),
          ],
        ),
      ),
      ProjectCard(
        title: l10n.projectsPeople,
        child: p.assignedTo.isEmpty
            ? Text(
                l10n.projectsNobodyAssigned,
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            : Column(
                children: [
                  for (final person in p.assignedTo)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: AssigneeRow(profile: person),
                    ),
                ],
              ),
      ),
      ProjectCard(title: l10n.projectsRates, child: _ratesList(p)),
      if (p.description.trim().isNotEmpty)
        ProjectCard(
          title: l10n.commonDescription,
          child: Text(
            p.description,
            style: AppTypography.body.copyWith(height: 1.5),
          ),
        ),
      if (p.tagNames.isNotEmpty)
        ProjectCard(
          title: l10n.commonTags,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final t in p.tagNames) LabelPill(label: t)],
          ),
        ),
      if (CustomFieldsDisplay.shows(defs))
        ProjectCard(
          title: l10n.projectsFormCustomFields,
          child: CustomFieldsDisplay(definitions: defs, values: p.customFields),
        ),
    ]);
  }

  /// Bill time and, on a fixed fee, Invoice an amount. Only for `can_bill`
  /// with Invoices on; Bill time also needs Timesheet.
  List<Widget> _billingActions(Project p) {
    final billTime = _billTimeOn;
    final usage = p.retainerUsage;
    final billMonth = _billingOn && p.isRetainer && usage?.billableNow == true;
    if (billMonth) {
      return [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _billRetainer,
            icon: const Icon(LucideIcons.receipt, size: 18),
            label: Text(switch (projectMonth(usage!.month)) {
              final month? => context.l10n.projectsBillMonth(month),
              null => context.l10n.projectsBillThisMonth,
            }),
          ),
        ),
        const SizedBox(height: 16),
      ];
    }
    if (!_billingOn || (!billTime && !p.isFixedFee)) return const [];
    return [
      if (billTime)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _billTime,
            icon: const Icon(LucideIcons.receipt, size: 18),
            label: Text(context.l10n.billTimeTitle),
          ),
        ),
      if (billTime && p.isFixedFee) const SizedBox(height: 8),
      if (p.isFixedFee)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _invoiceAmount,
            icon: const Icon(LucideIcons.handCoins, size: 18),
            label: Text(context.l10n.projectsAmountTitle),
          ),
        ),
      const SizedBox(height: 16),
    ];
  }

  /// The fee, the month so far, the carried hours and when it ended. The
  /// usage block is null for an API that predates retainers.
  Widget _retainer(Project p) {
    final l10n = context.l10n;
    final usage = p.retainerUsage;
    final fee = decimalOrNull(p.retainerFee);
    final month = projectMonth(usage?.month);
    String hours(double n) =>
        l10n.projectsHoursCount(double.parse(hoursLabel(n)), hoursLabel(n));
    final rate = decimalOrNull(p.retainerOverageRate);
    final lines = <String>[
      fee == null
          ? l10n.projectsRetainerNoFee
          : l10n.projectsRetainerFee(projectMoney(p, fee)),
      if (usage != null && month != null)
        if (usage.availableHours == null)
          l10n.projectsRetainerUsed(hours(usage.usedHours), month)
        else
          l10n.projectsRetainerUsedOf(
            hoursLabel(usage.usedHours),
            hoursLabel(usage.availableHours!),
            month,
          ),
      if (usage != null && usage.overageHours > 0)
        rate == null
            ? l10n.projectsRetainerOverage(hours(usage.overageHours))
            : l10n.projectsRetainerOverageValue(
                hours(usage.overageHours),
                projectMoney(
                  p,
                  (usage.overageHours * rate * 100).round() / 100,
                ),
              ),
      if (p.retainerCarriedValue > 0)
        l10n.projectsRetainerCarried(hours(p.retainerCarriedValue)),
      if (projectMonth(p.retainerLastMonth) case final last?)
        l10n.projectsRetainerEnded(last),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: AppTypography.body),
          ),
      ],
    );
  }

  Widget _budget(Project p) {
    final bars = burnBars(p);
    final fee = p.budgetAmountValue;
    // Null for a member and while Invoices is off: then there is no line.
    final invoiced = p.burn.invoicedAmount;
    final l10n = context.l10n;
    final lines = <String>[
      l10n.projectsBudgetLogged(
        projectHours(p.burn.loggedHours),
        projectHours(p.burn.billableHours),
      ),
      l10n.projectsBudgetUnbilled(projectMoney(p, p.burn.unbilledValue)),
      if (invoiced != null)
        if (p.isFixedFee && fee != null)
          l10n.projectsBudgetInvoicedOfFee(
            projectMoney(p, invoiced),
            projectMoney(p, fee),
          )
        else
          l10n.projectsBudgetInvoiced(projectMoney(p, invoiced)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bars.isEmpty)
          Text(
            l10n.projectsBudgetNone,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          )
        else
          ...bars,
        const SizedBox(height: 12),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: AppTypography.body),
          ),
      ],
    );
  }

  Widget _ratesList(Project p) {
    final l10n = context.l10n;
    final rate = p.hourlyRateValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rate == null
              ? l10n.projectsRatesNoDefault
              : l10n.projectsRatesDefault(projectMoney(p, rate)),
          style: AppTypography.body,
        ),
        for (final r in p.rates)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              r.value == null
                  ? l10n.projectsRateLineNone(
                      r.name.isEmpty ? l10n.projectsSomeone : r.name,
                    )
                  : l10n.projectsRateLine(
                      r.name.isEmpty ? l10n.projectsSomeone : r.name,
                      projectMoney(p, r.value!),
                    ),
              style: AppTypography.body,
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tasks
  // ---------------------------------------------------------------------------

  Widget _tasksTab(Project p) {
    final tasks = _tasks;
    return _scroll([
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () async {
            await context.push('${AppRoutes.taskCreate}?project=${p.id}');
            if (mounted) _loadTasks();
          },
          icon: const Icon(LucideIcons.plus, size: 16),
          label: Text(context.l10n.projectsNewTask),
        ),
      ),
      const SizedBox(height: 12),
      if (tasks == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (tasks.isEmpty)
        Text(
          context.l10n.projectsNoTasks,
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        )
      else
        // Grouped by status: the phone's take on the web's kanban columns.
        for (final status in TaskStatus.values)
          if (tasks.any((t) => t.status == status)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
              child: Text(
                '${status.label.toUpperCase()} '
                '(${tasks.where((t) => t.status == status).length})',
                style: AppTypography.overline.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            for (final t in tasks.where((t) => t.status == status))
              TaskRow(
                task: t,
                onTap: () async {
                  await context.push('/tasks/${t.id}');
                  if (mounted) _loadTasks();
                },
                onToggle: () async {
                  final res = await ref
                      .read(tasksProvider.notifier)
                      .toggleTaskStatus(t);
                  if (!mounted) return;
                  if (!res.success) {
                    _snack(
                      res.message ?? context.l10n.projectsTaskUpdateFailed,
                      danger: true,
                    );
                  }
                  _loadTasks();
                },
              ),
          ],
    ]);
  }

  // ---------------------------------------------------------------------------
  // Time
  // ---------------------------------------------------------------------------

  /// The caller's own running timer here, if any. An admin's list holds
  /// everyone's entries, and only your own timer is yours to stop.
  TimeEntry? get _myRunning {
    final me = ref.read(myEmailProvider)?.toLowerCase();
    for (final e in _entries ?? const <TimeEntry>[]) {
      if (e.isRunning && (me == null || e.profileName?.toLowerCase() == me)) {
        return e;
      }
    }
    return null;
  }

  List<TaskChoice> get _taskChoices => [
    for (final t in _tasks ?? const <Task>[])
      if (!t.completed) (id: t.id, title: t.title),
  ];

  String? _taskTitle(String? id) {
    if (id == null) return null;
    for (final t in _tasks ?? const <Task>[]) {
      if (t.id == id) return t.title;
    }
    return null;
  }

  Widget _timeTab(Project p) {
    final entries = _entries;
    final running = _myRunning;
    final done = [
      for (final e in entries ?? const <TimeEntry>[])
        if (!e.isRunning) e,
    ];
    return _scroll([
      Row(
        children: [
          _stat(context.l10n.projectsLogged, projectHours(p.burn.loggedHours)),
          const SizedBox(width: 12),
          _stat(
            context.l10n.timeEntryBillable,
            projectHours(p.burn.billableHours),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (running != null)
        RunningTimerCard(
          entry: running,
          isBusy: _timeBusy,
          caption: _taskTitle(running.taskId),
          onStop: () => _stopTimer(running),
        )
      else if (p.canEdit)
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _timeBusy ? null : _startTimer,
            icon: const Icon(LucideIcons.play, size: 16),
            label: Text(context.l10n.projectsStartTimer),
          ),
        ),
      if (p.canEdit) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _timeBusy ? null : _logTime,
            icon: const Icon(LucideIcons.plus, size: 16),
            label: Text(context.l10n.projectsLogTime),
          ),
        ),
      ],
      if (_billTimeOn) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _billTime,
            icon: const Icon(LucideIcons.receipt, size: 16),
            label: Text(context.l10n.billTimeTitle),
          ),
        ),
      ],
      const Divider(height: 32),
      if (entries == null)
        const Center(child: CircularProgressIndicator())
      else if (done.isEmpty)
        Text(
          context.l10n.projectsNoTime,
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        )
      else
        for (final e in done)
          TimeEntryRow(entry: e, detail: _taskTitle(e.taskId)),
    ]);
  }

  Widget _stat(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(value, style: AppTypography.h3),
        ],
      ),
    ),
  );

  Future<void> _startTimer() async {
    String? taskId;
    final choices = _taskChoices;
    if (choices.isNotEmpty) {
      final picked = await showModalBottomSheet<({String? id})>(
        context: context,
        backgroundColor: AppColors.surface,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.l10n.projectsTimerOn,
                    style: AppTypography.h3,
                  ),
                ),
                ListTile(
                  minTileHeight: 48,
                  leading: const Icon(LucideIcons.folderKanban),
                  title: Text(context.l10n.projectsTimerOnProject),
                  onTap: () => Navigator.pop(ctx, (id: null)),
                ),
                for (final t in choices)
                  ListTile(
                    minTileHeight: 48,
                    leading: const Icon(LucideIcons.circleCheck),
                    title: Text(t.title, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(ctx, (id: t.id)),
                  ),
              ],
            ),
          ),
        ),
      );
      if (picked == null || !mounted) return;
      taskId = picked.id;
    }
    setState(() => _timeBusy = true);
    final res = await _api.startTimer(
      widget.projectId,
      taskId: taskId,
      billable: _project!.billingType != ProjectBillingType.nonBillable,
    );
    if (!mounted) return;
    setState(() => _timeBusy = false);
    if (res.success) {
      await _loadTime();
      return;
    }
    final running = res.statusCode == 409 ? runningTimerPath(res.data) : null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.statusCode == 409
              ? context.l10n.projectsTimerAlreadyRunning
              : (res.message ?? context.l10n.projectsTimerStartFailed),
        ),
        backgroundColor: AppColors.danger600,
        behavior: SnackBarBehavior.floating,
        action: running == null
            ? null
            : SnackBarAction(
                label: context.l10n.projectsView,
                textColor: Colors.white,
                onPressed: () => context.push(running),
              ),
      ),
    );
  }

  Future<void> _stopTimer(TimeEntry entry) async {
    setState(() => _timeBusy = true);
    final res = await _api.stopTimer(entry.id);
    if (!mounted) return;
    setState(() => _timeBusy = false);
    if (!res.success) {
      _snack(res.message ?? context.l10n.projectsTimerStopFailed, danger: true);
      return;
    }
    await _load();
  }

  Future<void> _logTime() async {
    final p = _project!;
    final billable = p.billingType != ProjectBillingType.nonBillable;
    final result = await ManualEntrySheet.show(
      context,
      tasks: _taskChoices,
      billableByDefault: billable,
      // A non-billable project keeps every entry non-billable.
      offerBillable: billable,
    );
    if (result == null || !mounted) return;
    setState(() => _timeBusy = true);
    final res = await _api.logTime(
      widget.projectId,
      startedAt: result.startedAt,
      endedAt: result.endedAt,
      billable: result.billable,
      description: result.description,
      taskId: result.taskId,
    );
    if (!mounted) return;
    setState(() => _timeBusy = false);
    if (!res.success) {
      _snack(res.message ?? context.l10n.projectsLogTimeFailed, danger: true);
      return;
    }
    await _load();
  }

  // ---------------------------------------------------------------------------
  // Billing
  // ---------------------------------------------------------------------------

  Future<void> _billTime() async {
    final invoiceId = await BillTimeSheet.show(
      context,
      loadPreview: (upTo) => _api.unbilled(widget.projectId, upTo),
      onBill: (grouping, upTo) => ref
          .read(invoicesProvider.notifier)
          .createFromTimeEntries(
            projectId: widget.projectId,
            upTo: upTo,
            groupBy: grouping.value,
          ),
    );
    await _afterInvoice(invoiceId);
  }

  Future<void> _billRetainer() async {
    final l10n = context.l10n;
    final month = projectMonth(_project!.retainerUsage?.month);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          month == null
              ? l10n.projectsBillThisMonthQuestion
              : l10n.projectsBillMonthQuestion(month),
        ),
        content: Text(l10n.projectsBillMonthBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              month == null
                  ? l10n.projectsBillThisMonth
                  : l10n.projectsBillMonth(month),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await _api.billRetainer(
      widget.projectId,
      month: _project!.retainerUsage?.month,
    );
    if (!mounted) return;
    if (result.error != null || result.id == null) {
      _snack(result.error ?? context.l10n.projectsBillMonthFailed);
      unawaited(_load());
      return;
    }
    await _afterInvoice(result.id);
  }

  Future<void> _invoiceAmount() async {
    final p = _project!;
    final invoiceId = await InvoiceAmountSheet.show(
      context,
      project: p,
      onInvoice: ({amount, percent, description}) => _api.invoiceAmount(
        widget.projectId,
        amount: amount,
        percent: percent,
        description: description,
      ),
    );
    await _afterInvoice(invoiceId);
  }

  Future<void> _afterInvoice(String? invoiceId) async {
    if (invoiceId == null || !mounted) return;
    _snack(context.l10n.ticketsPanelTimeInvoiceCreated);
    unawaited(_load());
    context.push('${AppRoutes.invoices}/$invoiceId');
  }

  // ---------------------------------------------------------------------------
  // Invoices
  // ---------------------------------------------------------------------------

  Widget _invoicesTab(Project p) {
    final fee = p.budgetAmountValue;
    final invoiced = p.burn.invoicedAmount;
    return _scroll([
      ..._billingActions(p),
      if (p.isFixedFee && fee != null && invoiced != null) ...[
        Text(
          context.l10n.projectsBudgetInvoicedOfFee(
            projectMoney(p, invoiced),
            projectMoney(p, fee),
          ),
          style: AppTypography.body,
        ),
        const SizedBox(height: 12),
      ],
      if (p.invoices.isEmpty)
        Text(
          context.l10n.projectsNoInvoices,
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        )
      else
        for (final inv in p.invoices) _invoiceRow(inv),
    ]);
  }

  Widget _invoiceRow(ProjectInvoice inv) {
    final meta = [
      inv.statusLabel,
      if (inv.issueDate != null) shortDate(inv.issueDate!),
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppLayout.borderRadiusMd,
        border: Border.all(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: AppLayout.borderRadiusMd,
        onTap: () => context.push('${AppRoutes.invoices}/${inv.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inv.invoiceNumber.isEmpty
                          ? context.l10n.projectsInvoice
                          : inv.invoiceNumber,
                      style: AppTypography.label,
                    ),
                    Text(
                      meta,
                      style: AppTypography.caption.copyWith(
                        color: inv.status?.color ?? AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                projectMoneyIn(
                  inv.currency ?? _project!.currency,
                  inv.totalAmount,
                ),
                style: AppTypography.label,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Files and notes
  // ---------------------------------------------------------------------------

  Widget _filesTab(Project p) {
    return _scroll([
      if (p.attachments.isEmpty)
        Text(
          context.l10n.projectsNoFiles,
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        )
      else
        for (final a in p.attachments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AttachmentTile(attachment: a, onOpen: _openFile),
          ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: AttachFileButton(isUploading: _uploading, onPressed: _upload),
      ),
    ]);
  }

  Future<void> _upload() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final result = await pickAndUploadAttachment(
      target: AttachmentTarget.project,
      recordId: widget.projectId,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (result.cancelled) return;
    if (!result.succeeded) {
      _snack(result.error!);
      return;
    }
    _applyThread(result.data);
  }

  /// The detail POST answers with the refreshed `ProjectDetail`, whose
  /// comments and attachments replace the ones on screen.
  void _applyThread(Map<String, dynamic>? data) {
    final detail = data == null ? null : api.ProjectDetail.fromJson(data);
    final comments = detail?.comments;
    final attachments = detail?.attachments;
    if (comments == null && attachments == null) {
      _load();
      return;
    }
    setState(() {
      _project = _project!.copyWith(
        comments: comments == null
            ? null
            : [for (final c in comments) Comment.fromJson(c.json)],
        attachments: attachments == null
            ? null
            : [for (final a in attachments) Attachment.fromJson(a.json)],
      );
    });
  }

  Future<void> _openFile(Attachment a) async {
    if (!a.hasFile) {
      _snack(context.l10n.projectsAttachmentNoFile);
      return;
    }
    final result = await downloadAttachment(
      url: ApiConfig.attachmentDownload(a.id),
      fileName: a.fileName,
    );
    if (!mounted || result.success) return;
    _snack(result.error ?? context.l10n.projectsDownloadFailed);
  }

  Widget _notesTab(Project p) {
    return Column(
      children: [
        Expanded(
          child: p.comments.isEmpty
              ? EmptyState(
                  icon: LucideIcons.fileText,
                  title: context.l10n.projectsNoComments,
                  description: context.l10n.projectsNoCommentsBody,
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final c in p.comments)
                      NoteCard(
                        text: c.comment,
                        author: c.authorName,
                        timestamp: c.commentedOn,
                      ),
                  ],
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _note,
                    enabled: !_addingNote,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: context.l10n.projectsAddCommentHint,
                      filled: true,
                      fillColor: AppColors.gray100,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: context.l10n.projectsAddComment,
                  onPressed: _addingNote ? null : _addNote,
                  icon: const Icon(LucideIcons.send, size: 20),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addNote() async {
    final text = _note.text.trim();
    if (text.isEmpty) return;
    setState(() => _addingNote = true);
    final result = await _api.addComment(widget.projectId, text);
    if (!mounted) return;
    setState(() => _addingNote = false);
    if (result.error != null) {
      _snack(result.error!, danger: true);
      return;
    }
    _note.clear();
    _applyThread(result.data);
  }

  // ---------------------------------------------------------------------------
  // Edit and delete
  // ---------------------------------------------------------------------------

  Future<void> _edit() async {
    final saved = await context.push<bool>(
      AppRoutes.projectEditFor(widget.projectId),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.projectsDeleteTitle),
        content: Text(context.l10n.projectsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.l10n.commonDelete,
              style: TextStyle(color: AppColors.danger600),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await _api.delete(widget.projectId);
    if (!mounted) return;
    if (error != null) {
      _snack(error, danger: true);
      return;
    }
    _snack(context.l10n.projectsDeleted);
    context.pop();
  }
}
