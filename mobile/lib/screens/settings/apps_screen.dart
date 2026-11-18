import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/org_app.dart';
import '../../data/models/org_module.dart';
import '../../data/models/org_settings.dart' show sampleDataResult;
import '../../providers/auth_provider.dart';
import '../../providers/org_apps_provider.dart';
import '../../providers/org_modules_provider.dart';
import '../../widgets/common/badge.dart';
import 'app_preview_sheet.dart';
import 'modules_section.dart';
import '../../l10n/l10n.dart';
import '../../services/app_language.dart';

/// Settings › Apps: the industry apps, the modules, then sample data, as on the
/// web. Admin only, as every write here is on the server.
///
/// A server without `/api/apps/` (404) shows no apps section and keeps the
/// screen it had, titled Modules.
class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen> {
  /// The app whose action is running, or '' while sample data clears. One
  /// write at a time: two installs racing would each preview a stale org.
  String? _busyId;

  bool get _busy => _busyId != null;

  void _say(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _start(OrgApp app, AppAction action) async {
    if (_busy) return;
    final notifier = ref.read(orgAppsProvider.notifier);
    setState(() => _busyId = app.id);
    final asked = await notifier.preview(app.id, action);
    if (!mounted) return;
    setState(() => _busyId = null);
    final preview = asked.preview;
    if (preview == null) {
      _say(asked.error ?? context.l10n.settingsAppsPreviewFailed);
      return;
    }

    final choice = await showAppPreviewSheet(
      context,
      app: app,
      preview: preview,
    );
    if (choice == null || !mounted) return;

    setState(() => _busyId = app.id);
    final error = switch (action) {
      AppAction.install => await notifier.install(
        app.id,
        sampleData: choice.sampleData,
      ),
      AppAction.upgrade => await notifier.upgrade(app.id),
      AppAction.remove => await notifier.remove(app.id),
    };
    if (!mounted) return;
    setState(() => _busyId = null);
    _say(
      error ??
          switch (action) {
            AppAction.install => context.l10n.settingsAppsInstalled(app.name),
            AppAction.upgrade => context.l10n.settingsAppsUpdated(app.name),
            AppAction.remove => context.l10n.settingsAppsRemoved(app.name),
          },
    );
  }

  Future<void> _clearSampleData() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.settingsAppsClearTitle),
        content: Text(ctx.l10n.settingsAppsClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.commonCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger600),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.settingsAppsClear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = '');
    final result = await ref.read(orgAppsProvider.notifier).clearSampleData();
    if (!mounted) return;
    setState(() => _busyId = null);
    _say(
      result.error ??
          sampleDataResult(deleted: result.deleted, retained: result.retained),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isOrgAdminProvider);
    final apps = ref.watch(shownAppsProvider);
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(
          apps == null
              ? context.l10n.settingsAppsModulesTitle
              : context.l10n.settingsAppsTitle,
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: isAdmin ? _body(apps) : const _MemberNotice(),
    );
  }

  Widget _body(OrgAppsAnswer? apps) {
    final async = ref.watch(orgAppsProvider);
    final modules = ref.watch(shownModulesProvider);
    bool moduleOn(String key) => modules?.isOn(key) ?? true;
    String moduleLabel(String key) =>
        modules?.labelOf(key) ?? defaultModuleLabels[key] ?? key;
    final l10n = context.l10n;
    final parts = ref.watch(productsOnProvider)
        ? l10n.settingsAppsPartsWithProducts
        : l10n.settingsAppsParts;

    return ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (apps != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(l10n.settingsAppsIndustryApps, style: AppTypography.h3),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text(
              l10n.settingsAppsIntro(parts),
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final app in apps.apps)
            _AppCard(
              app: app,
              busy: _busy,
              moduleOn: moduleOn,
              moduleLabel: moduleLabel,
              onAction: (action) => _start(app, action),
            ),
        ] else if (async.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (async.hasError)
          _AppsError(onRetry: () => ref.invalidate(orgAppsProvider)),
        ModulesSection(showHeading: apps != null),
        _SampleData(busy: _busy, onClear: _clearSampleData),
      ],
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.app,
    required this.busy,
    required this.moduleOn,
    required this.moduleLabel,
    required this.onAction,
  });

  final OrgApp app;
  final bool busy;
  final bool Function(String module) moduleOn;
  final String Function(String module) moduleLabel;
  final void Function(AppAction action) onAction;

  String? _statusLine(AppLocalizations l10n) {
    switch (app.status) {
      case AppStatus.notInstalled:
        return null;
      case AppStatus.removed:
        return l10n.settingsAppsStatusRemoved;
      case AppStatus.installed:
        final by = app.installedByName;
        final at = app.installedAt;
        final line = StringBuffer(
          l10n.settingsAppsVersionInstalled(app.installedVersion ?? '?'),
        );
        if (by != null) line.write(l10n.settingsAppsInstalledBy(by));
        if (at != null) {
          final date = localDateFormat('d MMM y', 'yMMMd').format(at);
          line.write(l10n.settingsAppsInstalledOn(date));
        }
        line.write('.');
        if (app.updateAvailable) {
          line.write(
            app.version == app.installedVersion
                ? l10n.settingsAppsUpdateSkipped
                : l10n.settingsAppsVersionAvailable(app.version),
          );
        }
        return line.toString();
    }
  }

  String? _skippedLine(AppLocalizations l10n) {
    if (app.status != AppStatus.installed || app.skippedModules.isEmpty) {
      return null;
    }
    final names = app.skippedModules.map(moduleLabel).join(', ');
    final count = app.skippedModules.length;
    final waiting = app.skippedModules.where((m) => !moduleOn(m)).toList();
    final tail = waiting.isNotEmpty
        ? l10n.settingsAppsSwitchOn(count)
        : app.updateAvailable
        ? l10n.settingsAppsUpdateAddsNow
        : '';
    return '${l10n.settingsAppsSkipped(count, names)}$tail';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _statusLine(l10n);
    final skipped = _skippedLine(l10n);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  app.name,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (app.status == AppStatus.installed)
                StatusBadge(
                  label: l10n.settingsAppsBadgeInstalled,
                  color: AppColors.success600,
                )
              else if (app.status == AppStatus.removed)
                StatusBadge(
                  label: l10n.settingsAppsBadgeRemoved,
                  color: AppColors.gray500,
                ),
            ],
          ),
          if (app.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              app.description,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: 6),
            Text(
              status,
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
          if (skipped != null) ...[
            const SizedBox(height: 6),
            Text(
              skipped,
              style: AppTypography.caption.copyWith(
                color: AppColors.warning700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (i, action) in app.actions.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _button(l10n, action)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _button(AppLocalizations l10n, AppAction action) {
    final onPressed = busy ? null : () => onAction(action);
    return SizedBox(
      height: 44,
      child: switch (action) {
        AppAction.install => FilledButton(
          onPressed: onPressed,
          child: Text(l10n.settingsAppsInstall),
        ),
        AppAction.upgrade => FilledButton(
          onPressed: onPressed,
          child: Text(l10n.settingsAppsUpdate),
        ),
        AppAction.remove => OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger600),
          child: Text(l10n.settingsAppsRemove),
        ),
      },
    );
  }
}

class _SampleData extends StatelessWidget {
  const _SampleData({required this.busy, required this.onClear});

  final bool busy;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onClear,
              icon: const Icon(LucideIcons.trash2, size: 16),
              label: Text(context.l10n.settingsAppsClearButton),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsAppsClearHint,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppsError extends StatelessWidget {
  const _AppsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.settingsAppsLoadFailed,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.appTryAgain),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberNotice extends StatelessWidget {
  const _MemberNotice();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.lock, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            context.l10n.settingsAppsMemberNotice,
            style: AppTypography.body,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
