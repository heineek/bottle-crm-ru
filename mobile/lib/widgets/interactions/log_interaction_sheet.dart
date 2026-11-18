import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme.dart';
import '../../data/models/interaction.dart';
import '../../l10n/l10n.dart';
import '../../services/after_tap.dart';

/// "Log this call to Maria?" after a tap, or "Log activity" when [tap] is
/// null. The sheet saves through [save] itself, so a failure keeps it open
/// with a retry. True once something was saved.
Future<bool> showLogInteractionSheet(
  BuildContext context, {
  required InteractionTarget target,
  required Future<String?> Function(InteractionDraft draft) save,
  required DateTime Function() clock,
  PendingTap? tap,
  Duration? away,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => LogInteractionSheet(
      target: target,
      save: save,
      clock: clock,
      tap: tap,
      away: away,
    ),
  );
  return saved == true;
}

class LogInteractionSheet extends StatefulWidget {
  const LogInteractionSheet({
    super.key,
    required this.target,
    required this.save,
    required this.clock,
    this.tap,
    this.away,
  });

  final InteractionTarget target;
  final Future<String?> Function(InteractionDraft draft) save;
  final DateTime Function() clock;
  final PendingTap? tap;

  /// Time between the tap and the return, the estimate for a call's length.
  final Duration? away;

  @override
  State<LogInteractionSheet> createState() => _LogInteractionSheetState();
}

class _LogInteractionSheetState extends State<LogInteractionSheet> {
  static const _timedKinds = {InteractionKind.call, InteractionKind.meeting};

  late InteractionKind _kind = widget.tap?.kind ?? InteractionKind.call;
  CallOutcome? _outcome;
  final _note = TextEditingController();
  late final TextEditingController _minutes;

  /// Seconds from the time away, sent as estimated until the field is edited.
  int? _estimate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final away = widget.away;
    if (widget.tap != null && away != null && away > Duration.zero) {
      _estimate = away.inSeconds;
    }
    final minutes = _estimate == null ? null : (_estimate! / 60).round();
    _minutes = TextEditingController(
      text: minutes == null ? '' : '${minutes < 1 ? 1 : minutes}',
    );
  }

  @override
  void dispose() {
    _note.dispose();
    _minutes.dispose();
    super.dispose();
  }

  String get _title {
    final tap = widget.tap;
    final l10n = context.l10n;
    if (tap == null) return l10n.interactionsLogActivity;
    final who = tap.personName.trim();
    return who.isEmpty
        ? l10n.interactionsLogTitle(tap.kind.value)
        : l10n.interactionsLogTitleTo(tap.kind.value, who);
  }

  Future<void> _submit() async {
    int? seconds;
    var estimated = false;
    if (_timedKinds.contains(_kind)) {
      if (_estimate != null) {
        seconds = _estimate;
        estimated = true;
      } else if (_minutes.text.trim().isNotEmpty) {
        final minutes = int.tryParse(_minutes.text.trim());
        if (minutes == null || minutes < 0) {
          setState(() => _error = context.l10n.interactionsDurationInvalid);
          return;
        }
        seconds = minutes * 60;
      }
    }
    final draft = InteractionDraft(
      target: widget.target,
      kind: _kind,
      occurredAt: widget.tap?.tappedAt ?? widget.clock(),
      origin: widget.tap == null ? 'manual' : 'phone_tap',
      durationSeconds: seconds,
      durationEstimated: estimated,
      outcome: _kind == InteractionKind.call ? _outcome : null,
      body: _note.text,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.save(draft);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final failed = _error != null && !_saving;
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.gray300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(_title, style: AppTypography.h3),
                if (widget.tap == null) ...[
                  const SizedBox(height: 12),
                  _chips<InteractionKind>(
                    options: InteractionKind.loggable,
                    selected: _kind,
                    label: interactionKindLabel,
                    onSelected: (k) => setState(() => _kind = k ?? _kind),
                  ),
                ],
                if (_kind == InteractionKind.call) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.interactionsOutcome,
                    style: AppTypography.labelSmall,
                  ),
                  const SizedBox(height: 6),
                  _chips<CallOutcome>(
                    options: CallOutcome.values,
                    selected: _outcome,
                    label: callOutcomeLabel,
                    onSelected: (o) => setState(() => _outcome = o),
                  ),
                ],
                if (_timedKinds.contains(_kind)) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) {
                      if (_estimate != null) setState(() => _estimate = null);
                    },
                    decoration: InputDecoration(
                      labelText: context.l10n.interactionsDuration,
                      suffixText: context.l10n.interactionsMinutesSuffix,
                      helperText: _estimate != null
                          ? context.l10n.interactionsDurationEstimated
                          : null,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 5,
                  inputFormatters: [LengthLimitingTextInputFormatter(10000)],
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: context.l10n.interactionsNote,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: AppTypography.body.copyWith(
                      color: AppColors.danger600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(
                          widget.tap == null
                              ? context.l10n.commonCancel
                              : context.l10n.interactionsSkip,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                failed
                                    ? context.l10n.commonRetry
                                    : context.l10n.interactionsLog,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One choice, or none: tapping the chosen chip again clears it.
  Widget _chips<T>({
    required List<T> options,
    required T? selected,
    required String Function(T) label,
    required ValueChanged<T?> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(label(option)),
            selected: option == selected,
            onSelected: _saving ? null : (on) => onSelected(on ? option : null),
          ),
      ],
    );
  }
}

/// The kind as the sheet and the timeline name it.
String interactionKindLabel(InteractionKind kind) {
  final l10n = appL10n;
  return switch (kind) {
    InteractionKind.call => l10n.interactionsKindCall,
    InteractionKind.meeting => l10n.interactionsKindMeeting,
    InteractionKind.email => l10n.interactionsKindEmail,
    InteractionKind.whatsapp => l10n.interactionsKindWhatsapp,
    InteractionKind.sms => l10n.interactionsKindSms,
    InteractionKind.enquiry => l10n.interactionsKindEnquiry,
  };
}

String callOutcomeLabel(CallOutcome outcome) {
  final l10n = appL10n;
  return switch (outcome) {
    CallOutcome.connected => l10n.interactionsOutcomeConnected,
    CallOutcome.noAnswer => l10n.interactionsOutcomeNoAnswer,
    CallOutcome.voicemail => l10n.interactionsOutcomeVoicemail,
    CallOutcome.busy => l10n.interactionsOutcomeBusy,
    CallOutcome.wrongNumber => l10n.interactionsOutcomeWrongNumber,
  };
}
