import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/l10n.dart';
import '../../core/theme/theme.dart';
import '../../providers/duplicates_provider.dart';

/// Two leads, contacts or accounts side by side, to pick which one to keep.
///
/// The rule the API applies is shown before it runs: the kept record's values
/// stay, its blank fields take the other's, and the other record is deleted
/// once its links, notes and files have moved. There is no undo, so merging
/// asks once more in a dialog that names the record being deleted.
///
/// Keeping one record means deleting the other, so a record can only be kept
/// when the other is one the person may delete (`canDelete`, from the API).
/// That is a hint to spare a refusal; the API decides.
class MergeCompareScreen extends ConsumerStatefulWidget {
  const MergeCompareScreen({
    super.key,
    required this.module,
    required this.recordId,
    required this.otherId,
  });

  final DuplicateModule module;
  final String recordId;
  final String otherId;

  @override
  ConsumerState<MergeCompareScreen> createState() => _MergeCompareScreenState();
}

class _MergeCompareScreenState extends ConsumerState<MergeCompareScreen> {
  MergeSide? _current;
  MergeSide? _other;
  String? _loadError;
  String? _mergeError;
  String? _keep;
  bool _loading = true;
  bool _merging = false;

  DuplicateModule get _module => widget.module;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final api = ref.read(duplicatesApiProvider);
    try {
      final sides = await Future.wait([
        api.side(_module, widget.recordId),
        api.side(_module, widget.otherId),
      ]);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _current = sides[0];
        _other = sides[1];
        _keep = sides[1].canDelete || !sides[0].canDelete
            ? sides[0].id
            : sides[1].id;
      });
    } on MergeSideError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.notFound
            ? context.l10n.appDupLoadGone(_module.name)
            : context.l10n.appDupLoadFailed(_module.name);
      });
    }
  }

  /// How the copy names [side]. Duplicates usually share a name, and "merge
  /// Rosalind Beck into Rosalind Beck" tells nobody which one survives, so
  /// then the two are "this record" (the one this was opened from) and "the
  /// other record". The web says the same.
  String _label(MergeSide side) {
    if (_current!.name != _other!.name) return side.name;
    return side.id == _current!.id
        ? appL10n.appDupThisRecord
        : appL10n.appDupOtherRecord;
  }

  /// Keeping [side] deletes the other one.
  bool _keepable(MergeSide side) =>
      (side.id == _current!.id ? _other! : _current!).canDelete;

  Future<void> _merge() async {
    final current = _current!, other = _other!;
    final kept = _keep == current.id ? current : other;
    final dropped = _keep == current.id ? other : current;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.appDupDeleteQ(_label(dropped))),
        content: Text(
          context.l10n.appDupDeleteBody(_label(kept), _label(dropped)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.appDupMergeAndDelete,
              style: TextStyle(color: AppColors.danger600),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _merging = true;
      _mergeError = null;
    });
    final failure = await ref
        .read(duplicatesApiProvider)
        .merge(_module, kept.id, dropped.id);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _merging = false;
        _mergeError = failure;
      });
      return;
    }
    refreshAfterMerge(ref, _module);
    context.go('/${_module.path}/${kept.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(context.l10n.appDupMergeTitle(_module.name)),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          tooltip: context.l10n.commonBack,
          onPressed: () => context.pop(),
        ),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.alertCircle,
                size: 40,
                color: AppColors.danger500,
              ),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: AppTypography.body,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: Text(context.l10n.commonRetry),
              ),
            ],
          ),
        ),
      );
    }

    final current = _current!, other = _other!;
    final possible = _keepable(current) || _keepable(other);
    final kept = _keep == current.id ? current : other;
    final dropped = _keep == current.id ? other : current;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 48),
      children: [
        Text(
          context.l10n.appDupPickKeep,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        if (_mergeError != null) _refusal(_mergeError!),
        RadioGroup<String>(
          groupValue: _keep,
          onChanged: (value) => setState(() => _keep = value),
          child: Column(
            children: [
              for (final side in [current, other]) _sideCard(side),
            ],
          ),
        ),
        if (possible) ...[
          _afterMerge(kept, dropped),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: _merging ? null : _merge,
            child: Text(
              _merging
                  ? context.l10n.appDupMerging
                  : context.l10n.appDupMergeInto(_label(kept)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          Text(
            context.l10n.appDupCannotMerge(_module.name),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _refusal(String message) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.danger50,
      border: Border.all(color: AppColors.danger200),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      appL10n.appDupNothingMerged(message),
      style: AppTypography.bodySmall.copyWith(color: AppColors.danger700),
    ),
  );

  Widget _sideCard(MergeSide side) {
    final keepable = _keepable(side);
    final chosen = _keep == side.id;
    // A Material rather than a decorated Container, so the tile's ink shows.
    // Flat all the same: no elevation, a border for the edge.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: chosen ? AppColors.primary600 : AppColors.border,
            width: chosen ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioListTile<String>(
              value: side.id,
              enabled: keepable,
              title: Text(
                context.l10n.appDupKeep(_label(side)),
                style: AppTypography.label.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: keepable
                  ? null
                  : Text(
                      context.l10n.appDupKeepForbidden,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _fieldTable(side.fields),
            ),
          ],
        ),
      ),
    );
  }

  Widget _afterMerge(MergeSide kept, MergeSide dropped) {
    final rows = <(String, String)>[
      for (var i = 0; i < kept.fields.length; i++)
        (
          kept.fields[i].$1,
          kept.fields[i].$2.isNotEmpty
              ? kept.fields[i].$2
              : dropped.fields[i].$2,
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.appDupAfterMerge, style: AppTypography.overline),
          const SizedBox(height: 8),
          _fieldTable(rows),
          const SizedBox(height: 8),
          Text(
            context.l10n.appDupAfterMergeBody(_label(dropped), _label(kept)),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldTable(List<(String, String)> rows) => Column(
    children: [
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value.isEmpty ? '—' : value,
                  style: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
