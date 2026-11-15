import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/api_config.dart';
import '../../core/theme/theme.dart';
import '../../data/models/attachment.dart';
import '../../data/models/custom_object.dart';
import '../../providers/custom_objects_provider.dart';
import '../../routes/app_router.dart';
import '../../services/attachment_upload.dart';
import '../../widgets/common/common.dart';
import '../../widgets/objects/photo_gallery.dart';
import '../../l10n/l10n.dart';

/// One custom object record, with its links, photos, files and people.
class ObjectRecordDetailScreen extends ConsumerStatefulWidget {
  const ObjectRecordDetailScreen({
    super.key,
    required this.objectKey,
    required this.recordId,
  });

  final String objectKey;
  final String recordId;

  @override
  ConsumerState<ObjectRecordDetailScreen> createState() =>
      _ObjectRecordDetailScreenState();
}

class _ObjectRecordDetailScreenState
    extends ConsumerState<ObjectRecordDetailScreen> {
  ObjectRecord? _record;
  bool _loading = true;
  bool _notFound = false;
  String? _error;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await ref
          .read(customObjectsApiProvider)
          .fetchRecord(widget.objectKey, widget.recordId);
      if (!mounted) return;
      final data = response.data;
      setState(() {
        _loading = false;
        _notFound = response.statusCode == 404;
        if (response.success && data != null) {
          _record = ObjectRecord.fromJson(data);
          _error = null;
        } else if (!_notFound) {
          _error = response.message ?? context.l10n.objectsLoadRecordFailed;
        }
      });
    } on ArgumentError {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = true;
      });
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.danger600 : null,
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              dialogContext.l10n.commonDelete,
              style: TextStyle(color: AppColors.danger600),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteRecord(ObjectDefinition def) async {
    final label = def.summary.label;
    final l10n = context.l10n;
    if (!await _confirm(
      l10n.objectsDeleteRecordTitle(label),
      l10n.objectsDeleteRecordBody,
    )) {
      return;
    }
    final response = await ref
        .read(customObjectsApiProvider)
        .deleteRecord(widget.objectKey, widget.recordId);
    if (!mounted) return;
    if (!response.success) {
      _snack(
        response.message ?? l10n.objectsDeleteRecordFailed(label),
        error: true,
      );
      return;
    }
    ref.invalidate(objectRecordsProvider(widget.objectKey));
    context.pop();
  }

  Future<void> _upload() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final result = await pickAndUploadAttachmentTo(
      url: ApiConfig.objectRecordAttachments(widget.objectKey, widget.recordId),
      field: 'file',
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (result.cancelled) return;
    if (!result.succeeded) {
      _snack(result.error!, error: true);
      return;
    }
    await _load(quiet: true);
  }

  Future<void> _deleteAttachment(RecordAttachment a) async {
    final l10n = context.l10n;
    if (!await _confirm(
      a.isPhoto ? l10n.objectsDeletePhotoTitle : l10n.objectsDeleteFileTitle,
      l10n.objectsDeleteAttachmentBody(a.fileName),
    )) {
      return;
    }
    final response = await ref
        .read(customObjectsApiProvider)
        .deleteAttachment(widget.objectKey, widget.recordId, a.id);
    if (!mounted) return;
    if (!response.success) {
      _snack(response.message ?? l10n.objectsDeleteFileFailed, error: true);
      return;
    }
    await _load(quiet: true);
  }

  Future<void> _openFile(Attachment a) async {
    final l10n = context.l10n;
    if (!a.hasFile) {
      _snack(l10n.objectsNoFile);
      return;
    }
    final result = await downloadAttachment(
      url: ApiConfig.attachmentDownload(a.id),
      fileName: a.fileName,
    );
    if (!mounted || result.success) return;
    _snack(result.error ?? l10n.objectsDownloadFailed);
  }

  @override
  Widget build(BuildContext context) {
    final definition = ref.watch(objectDefinitionProvider(widget.objectKey));
    final l10n = context.l10n;

    return definition.when(
      loading: () => _shell(
        title: l10n.objectsRecordTitle,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _shell(
        title: l10n.objectsRecordTitle,
        body: _Problem(
          message: l10n.objectsLoadRecordFailed,
          onRetry: () =>
              ref.invalidate(objectDefinitionProvider(widget.objectKey)),
        ),
      ),
      data: (def) {
        if (def == null) {
          return _shell(title: l10n.objectsRecordTitle, body: _missing());
        }
        final record = _record;
        if (_loading && record == null) {
          return _shell(
            title: def.summary.label,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (_notFound) {
          return _shell(title: def.summary.label, body: _missing());
        }
        if (record == null) {
          return _shell(
            title: def.summary.label,
            body: _Problem(
              message: _error ?? l10n.objectsLoadRecordFailed,
              onRetry: _load,
            ),
          );
        }
        return _shell(
          title: def.summary.label,
          actions: [
            if (record.canEdit)
              IconButton(
                tooltip: l10n.commonEdit,
                icon: const Icon(LucideIcons.pencil),
                onPressed: () async {
                  await context.push(
                    AppRoutes.objectRecordEdit(widget.objectKey, record.id),
                  );
                  if (mounted) _load(quiet: true);
                },
              ),
            if (record.canDelete)
              IconButton(
                tooltip: l10n.commonDelete,
                icon: Icon(LucideIcons.trash2, color: AppColors.danger600),
                onPressed: () => _deleteRecord(def),
              ),
          ],
          body: _content(def, record),
        );
      },
    );
  }

  Widget _missing() => EmptyState(
    icon: LucideIcons.boxes,
    title: context.l10n.objectsMissingRecord,
  );

  Widget _shell({
    required String title,
    required Widget body,
    List<Widget> actions = const [],
  }) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: actions,
      ),
      body: body,
    );
  }

  Widget _content(ObjectDefinition def, ObjectRecord record) {
    final photos = record.attachments.where((a) => a.isPhoto).toList();
    final files = record.attachments.where((a) => !a.isPhoto).toList();
    final l10n = context.l10n;
    return RefreshIndicator(
      onRefresh: () => _load(quiet: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _card(l10n.objectsDetails, [
                  _field(def.summary.nameLabel, record.name),
                  for (final f in def.customFields)
                    _field(
                      f.label,
                      hasFieldValue(record.customFields[f.key])
                          ? displayValue(f, record.customFields[f.key])
                          : '',
                    ),
                ]),
                if (def.linkFields.isNotEmpty)
                  _card(l10n.objectsLinks, [
                    for (final f in def.linkFields)
                      _linkField(f.label, record.links[f.key]),
                  ]),
                if (photos.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                    child: Text(l10n.objectsPhotos, style: AppTypography.h3),
                  ),
              ]),
            ),
          ),
          if (photos.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: PhotoGallery(photos: photos, onDelete: _deleteAttachment),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (files.isNotEmpty || record.canEdit)
                  _card(l10n.objectsFiles, [
                    if (files.isEmpty) _none(),
                    for (final a in files) _fileRow(a),
                    if (record.canEdit) _attachButton(),
                  ]),
                _card(l10n.objectsPeople, [
                  _field(
                    l10n.objectsAssignedTo,
                    record.assignedTo.isEmpty
                        ? ''
                        : record.assignedTo.map(_personName).join(', '),
                  ),
                  _field(
                    l10n.objectsCreatedBy,
                    record.createdBy == null
                        ? ''
                        : _personName(record.createdBy!),
                  ),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.h3),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
  );

  Widget _none() => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      context.l10n.objectsNone,
      style: AppTypography.body.copyWith(color: AppColors.textTertiary),
    ),
  );

  Widget _field(String label, String value) {
    final empty = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          const SizedBox(height: 2),
          Text(
            empty ? context.l10n.objectsNone : value,
            style: AppTypography.body.copyWith(
              color: empty ? AppColors.textTertiary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkField(String label, LinkValue? value) {
    final records = value?.records ?? const <LinkedRecord>[];
    final hidden = value?.hidden ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          if (records.isEmpty && hidden == 0) _none(),
          for (final r in records) _linkRow(r),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                records.isEmpty
                    ? context.l10n.objectsHidden(hidden)
                    : context.l10n.objectsHiddenMore(hidden),
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _linkRow(LinkedRecord r) {
    final route = linkedRecordRoute(r.object, r.id);
    final name = r.name.isEmpty ? context.l10n.objectsUntitled : r.name;
    if (route == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(name, style: AppTypography.body),
      );
    }
    return InkWell(
      onTap: () => context.push(route),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            name,
            style: AppTypography.body.copyWith(color: AppColors.primary600),
          ),
        ),
      ),
    );
  }

  Widget _attachButton() => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: AttachFileButton(isUploading: _uploading, onPressed: _upload),
    ),
  );

  Widget _fileRow(RecordAttachment a) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: AttachmentTile(
              attachment: a.toAttachment(),
              onOpen: _openFile,
            ),
          ),
          if (a.canDelete)
            IconButton(
              tooltip: context.l10n.objectsDeleteFileTooltip,
              icon: Icon(LucideIcons.trash2, color: AppColors.danger600),
              onPressed: () => _deleteAttachment(a),
            ),
        ],
      ),
    );
  }

  static String _personName(PersonRef p) =>
      p.name.isNotEmpty ? p.name : p.email;
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: AppTypography.h3, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
