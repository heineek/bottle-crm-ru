import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../config/api_config.dart';
import '../../core/theme/theme.dart';
import '../../data/models/support_ticket.dart';
import '../../l10n/l10n.dart';
import '../../providers/support_provider.dart';
import '../../services/app_language.dart';
import '../../services/attachment_upload.dart';

class SupportDetailScreen extends ConsumerStatefulWidget {
  const SupportDetailScreen({super.key, required this.ticketId});
  final String ticketId;

  @override
  ConsumerState<SupportDetailScreen> createState() =>
      _SupportDetailScreenState();
}

class _SupportDetailScreenState extends ConsumerState<SupportDetailScreen> {
  final _reply = TextEditingController();
  SupportTicket? _ticket;
  PlatformFile? _attachment;
  String? _error;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.surfaceDim,
    appBar: AppBar(
      title: Text(_ticket?.reference ?? context.l10n.supportDetailTitle),
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _errorState()
        : RefreshIndicator(onRefresh: _load, child: _content(_ticket!)),
  );

  Widget _content(SupportTicket ticket) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
    children: [
      Text(ticket.subject, style: AppTypography.h2),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _chip(ticket.status.label, ticket.status.color),
          _chip(ticket.category.label, AppColors.gray500),
          _chip(ticket.priorityLabel, AppColors.gray500),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        ticket.assigned
            ? context.l10n.supportDetailAssigned
            : context.l10n.supportDetailUnassigned,
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      ),
      const SizedBox(height: 24),
      Text(
        context.l10n.supportDetailConversation,
        style: AppTypography.overline,
      ),
      const SizedBox(height: 10),
      ...ticket.messages.map(_message),
      const SizedBox(height: 18),
      if (ticket.canReply) _composer() else _closedMessage(),
    ],
  );

  Widget _message(SupportMessage message) => Align(
    alignment: message.isStaff ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 720),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: message.isStaff ? AppColors.success200 : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  message.authorLabel,
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _stamp(message.createdAt.toLocal()),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          if (message.body.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(message.body, style: AppTypography.body),
          ],
          if (message.hasAttachment) ...[
            const SizedBox(height: 9),
            TextButton.icon(
              onPressed: () => _download(message),
              icon: const Icon(LucideIcons.download, size: 17),
              label: Text(message.attachmentName!),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _composer() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _reply,
          minLines: 4,
          maxLines: 8,
          maxLength: 10000,
          decoration: InputDecoration(
            labelText: context.l10n.supportDetailReply,
            alignLabelWithHint: true,
            hintText: context.l10n.supportDetailReplyHint,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _sending ? null : _pickAttachment,
              icon: const Icon(LucideIcons.paperclip),
              label: Text(
                _attachment?.name ?? context.l10n.supportDetailAttach,
              ),
            ),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(LucideIcons.send),
              label: Text(
                _sending
                    ? context.l10n.supportDetailSending
                    : context.l10n.supportDetailSend,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _closedMessage() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(context.l10n.supportDetailClosed),
  );

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: AppTypography.caption.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _load,
            child: Text(context.l10n.supportTryAgain),
          ),
        ],
      ),
    ),
  );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(supportTicketsProvider.notifier)
        .getTicket(widget.ticketId);
    if (!mounted) return;
    setState(() {
      _ticket = result.ticket;
      _error = result.error;
      _loading = false;
    });
  }

  Future<void> _pickAttachment() async {
    final result = await selectAttachment();
    if (!mounted || result.cancelled) return;
    if (result.error != null) {
      _snack(result.error!);
      return;
    }
    setState(() => _attachment = result.file);
  }

  Future<void> _send() async {
    if (_reply.text.trim().isEmpty && _attachment == null) {
      _snack(context.l10n.supportDetailReplyEmpty);
      return;
    }
    setState(() => _sending = true);
    final result = await ref
        .read(supportTicketsProvider.notifier)
        .reply(
          ticketId: widget.ticketId,
          body: _reply.text,
          attachment: _attachment,
        );
    await clearAttachmentPickerCache();
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result.success) {
        _ticket = result.ticket;
        _attachment = null;
        _reply.clear();
      }
    });
    if (!result.success) {
      _snack(result.error ?? context.l10n.supportDetailReplyFailed);
    }
  }

  Future<void> _download(SupportMessage message) async {
    final result = await downloadAttachment(
      url: ApiConfig.supportMessageAttachment(message.id),
      fileName: message.attachmentName!,
    );
    if (!mounted || result.success) return;
    _snack(result.error ?? context.l10n.supportDetailDownloadFailed);
  }

  // Two formats rather than one pattern, so English keeps its comma and
  // other languages get their own day-month order.
  String _stamp(DateTime t) =>
      '${localDateFormat('d MMM', 'MMMd').format(t)}, '
      '${localDateFormat('HH:mm', 'Hm').format(t)}';

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
