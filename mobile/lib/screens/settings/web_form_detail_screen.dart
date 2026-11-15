import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/custom_field_definition.dart';
import '../../data/models/web_form.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/lookup_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/web_forms_provider.dart';
import '../../widgets/common/badge.dart';
import 'web_form_field_sheet.dart';

/// One web form: the editor, mirroring `/settings/web-forms/[id]` on the web.
///
/// FIVE SECTIONS, ONE SAVE
/// Fields, Behaviour, Spam, Embed and Activity. The first three save together,
/// because a per-section save would mean three requests, three failure states,
/// and an ordering question nobody asked.
///
/// REORDERING WITHOUT A DRAG GESTURE
/// `ReorderableListView` provides the drag; the up/down buttons beside it
/// provide the same move without one. Both go through [_move], so they cannot
/// disagree. The drag handle is an explicit `ReorderableDragStartListener`
/// rather than a long-press on the row: a child's own gesture recognizer wins
/// the arena against an enclosing drag, so a row that is itself the drag target
/// stops being draggable the moment anything inside it handles a press. Tapping
/// a row opens its edit sheet, which is exactly that situation.
///
/// THE TARGET DECIDES THE VOCABULARY
/// A lead form offers Lead columns and Lead custom fields; a ticket form offers
/// ticket fields and Case custom fields and sets the ticket's priority and
/// type. The target is chosen at creation and shown, not edited, here: the
/// server refuses to change it once the form has submissions.
///
/// PUBLISHING IS NOT A SWITCH
/// It has its own endpoint, which validates the source state and the form's
/// shape. `is_published` is read-only on the update serializer, so a switch
/// bound to it would look like it worked and do nothing.
///
/// THE CAPTCHA SECRET IS WRITE-ONLY
/// The API never returns it, so the box is always empty and empty means
/// "unchanged". Sending a blank would wipe a working secret on any unrelated
/// save, and Turnstile fails closed, so nothing would show until the next
/// visitor was refused.
class WebFormDetailScreen extends ConsumerStatefulWidget {
  const WebFormDetailScreen({super.key, required this.formId});

  final String formId;

  @override
  ConsumerState<WebFormDetailScreen> createState() =>
      _WebFormDetailScreenState();
}

class _WebFormDetailScreenState extends ConsumerState<WebFormDetailScreen> {
  /// The editable copy, seeded from the server once and owned here from then
  /// on. Null until the first load resolves.
  WebForm? _draft;
  String _loadedId = '';

  final _name = TextEditingController();
  final _submitLabel = TextEditingController();
  final _successMessage = TextEditingController();
  final _redirectUrl = TextEditingController();
  final _origins = TextEditingController();
  final _captchaSiteKey = TextEditingController();
  final _captchaSecret = TextEditingController();
  final _rotationCap = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _submitLabel.dispose();
    _successMessage.dispose();
    _redirectUrl.dispose();
    _origins.dispose();
    _captchaSiteKey.dispose();
    _captchaSecret.dispose();
    _rotationCap.dispose();
    super.dispose();
  }

  /// Copy the server's form into the editable state.
  ///
  /// Guarded on the id so an ordinary refresh (after a publish, say) does not
  /// discard what somebody is halfway through typing.
  void _seed(WebForm form) {
    if (_loadedId == form.id) return;
    _loadedId = form.id;
    _draft = form;
    _name.text = form.name;
    _submitLabel.text = form.submitButtonLabel;
    _successMessage.text = form.successMessageText;
    _redirectUrl.text = form.redirectUrl;
    _origins.text = form.allowedOrigins.join('\n');
    _captchaSiteKey.text = form.captchaSiteKey;
    _rotationCap.text = form.rotationCap?.toString() ?? '';
    // Deliberately not seeded: there is nothing to seed it with, and an empty
    // box is what "leave the stored one alone" looks like.
    _captchaSecret.clear();
  }

  /// Move the row at [oldIndex] to [newIndex].
  ///
  /// `newIndex` is the position the row ends up at, not an insertion point:
  /// this is wired to `onReorderItem`, which already adjusts for the row being
  /// lifted out. The older `onReorder` did not, and the off-by-one that
  /// followed is why a downward drag used to land a row short of where it was
  /// dropped. The up/down buttons call straight into this with the index they
  /// mean, so both paths agree.
  void _move(int oldIndex, int newIndex) {
    final draft = _draft;
    if (draft == null) return;
    if (newIndex < 0 ||
        newIndex >= draft.fields.length ||
        newIndex == oldIndex) {
      return;
    }
    final fields = [...draft.fields];
    final moved = fields.removeAt(oldIndex);
    fields.insert(newIndex, moved);
    setState(() => _draft = draft.copyWith(fields: fields));
  }

  Future<void> _editField(
    WebFormField? existing,
    List<CustomFieldDefinition> customFields,
  ) async {
    final draft = _draft;
    if (draft == null) return;

    final inUse = {
      for (final field in draft.fields)
        if (field.builtinField.isNotEmpty) field.builtinField,
    };

    final result = await showWebFormFieldSheet(
      context,
      existing: existing,
      target: draft.target,
      customFields: customFields,
      builtinFieldsInUse: inUse,
    );
    if (result == null) return;

    final fields = [...draft.fields];
    final at = existing == null ? -1 : fields.indexOf(existing);
    if (at >= 0) {
      fields[at] = result;
    } else {
      fields.add(result);
    }
    setState(() => _draft = draft.copyWith(fields: fields));
  }

  void _removeField(WebFormField field) {
    final draft = _draft;
    if (draft == null) return;
    final fields = [...draft.fields]..remove(field);
    setState(() => _draft = draft.copyWith(fields: fields));
  }

  List<String> _readOrigins() {
    return _origins.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;

    // An empty box is "no cap". The box takes up to six digits and nothing
    // else, so anything in it parses; the server refuses a cap of 0.
    final capText = _rotationCap.text.trim();
    final cap = int.tryParse(capText);

    final payload = draft
        .copyWith(
          rotationCap: cap,
          clearRotationCap: cap == null,
          name: _name.text.trim(),
          submitButtonLabel: _submitLabel.text.trim(),
          successMessageText: _successMessage.text,
          redirectUrl: _redirectUrl.text.trim(),
          allowedOrigins: _readOrigins(),
          captchaSiteKey: _captchaSiteKey.text.trim(),
        )
        .toJson(captchaSecret: _captchaSecret.text);

    setState(() => _saving = true);
    final error = await ref
        .read(webFormsProvider.notifier)
        .updateWebForm(draft.id, payload);
    if (!mounted) return;
    setState(() => _saving = false);

    if (error == null) {
      // Re-read so the editor shows what was stored rather than what was sent.
      _loadedId = '';
      ref.invalidate(webFormDetailProvider(draft.id));
      _captchaSecret.clear();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? context.l10n.settingsWebFormDetailChangesSaved),
      ),
    );
  }

  Future<void> _togglePublished(WebForm form) async {
    final notifier = ref.read(webFormsProvider.notifier);

    if (form.isPublished) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.settingsWebFormDetailUnpublishTitle),
          content: Text(context.l10n.settingsWebFormDetailUnpublishBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.settingsWebFormDetailKeepLive),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger600),
              child: Text(context.l10n.settingsWebFormDetailUnpublishConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final error = await notifier.unpublish(form.id);
      if (!mounted) return;
      _afterStateChange(
        form.id,
        error,
        context.l10n.settingsWebFormDetailUnpublishedSnack,
      );
      return;
    }

    final error = await notifier.publish(form.id);
    if (!mounted) return;
    _afterStateChange(
      form.id,
      error,
      context.l10n.settingsWebFormDetailPublishedSnack,
    );
  }

  void _afterStateChange(String id, String? error, String success) {
    if (error == null) {
      _loadedId = '';
      ref.invalidate(webFormDetailProvider(id));
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error ?? success)));
  }

  Future<void> _delete(WebForm form) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsWebFormDetailDeleteTitle),
        content: Text(context.l10n.settingsWebFormDetailDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.settingsWebFormDetailKeepIt),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger600),
            child: Text(context.l10n.settingsWebFormDetailDeletePermanently),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final error = await ref
        .read(webFormsProvider.notifier)
        .removeWebForm(form.id);
    if (!mounted) return;
    if (error == null) {
      context.pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  /// [copied] is the whole confirmation, e.g. "iframe snippet copied".
  Future<void> _copy(String text, String Function() copied) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(copied())));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(webFormDetailProvider(widget.formId));
    final isAdmin = ref.watch(isOrgAdminProvider);
    final profiles = ref.watch(usersProvider);
    final tags = ref.watch(tagsProvider);
    final allCustomFields =
        ref.watch(customFieldsProvider).value?.fields ??
        const <CustomFieldDefinition>[];

    return async.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.settingsWebFormDetailTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '$error'.replaceFirst('Exception: ', ''),
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      data: (detail) {
        _seed(detail.form);
        final draft = _draft!;
        final blocker = draft.publishBlocker;
        final l10n = context.l10n;
        final isTicket = draft.isTicket;
        // Only the target model's active definitions. The server refuses any
        // other, so offering one would only buy a 400 on save.
        final model = customFieldModelFor(draft.target);
        final customFields = allCustomFields
            .where((d) => d.targetModel == model && d.isActive)
            .toList(growable: false);
        // Stored rotation members the chips cannot offer, for the same reason.
        final offListMembers = draft.storedRotationMembers
            .where((m) => !profiles.any((p) => p.id == m.id))
            .toList(growable: false);
        final lastAssigned = draft.rotationLastAssigned;
        // The stored assignee when the picker cannot offer them, because they
        // were deactivated after being chosen. Without an item of their own the
        // dropdown has no match for its value, and dropping them would clear
        // the assignee as a side effect of an unrelated save.
        final stored = draft.storedAssignee;
        final offList =
            stored != null && !profiles.any((p) => p.id == stored.id)
            ? stored
            : null;

        return Scaffold(
          backgroundColor: AppColors.surfaceDim,
          appBar: AppBar(
            title: Text(detail.form.name),
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 1,
            actions: [
              if (isAdmin)
                IconButton(
                  icon: const Icon(LucideIcons.trash2),
                  tooltip: l10n.settingsWebFormDetailDeleteTooltip,
                  onPressed: () => _delete(detail.form),
                ),
            ],
          ),
          bottomNavigationBar: isAdmin
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving
                              ? l10n.settingsWebFormDetailSaving
                              : l10n.settingsWebFormDetailSaveChanges,
                        ),
                      ),
                    ),
                  ),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _StatusCard(
                form: detail.form,
                isAdmin: isAdmin,
                blocker: blocker,
                onToggle: () => _togglePublished(detail.form),
              ),

              _SectionHeader(
                l10n.settingsWebFormDetailFields,
                subtitle: l10n.settingsWebFormDetailFieldsSub,
              ),
              _FieldList(
                fields: draft.fields,
                isAdmin: isAdmin,
                onReorder: _move,
                onEdit: (field) => _editField(field, customFields),
                onRemove: _removeField,
              ),
              if (isAdmin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () => _editField(null, customFields),
                      icon: const Icon(LucideIcons.plus, size: 16),
                      label: Text(l10n.settingsWebFormDetailAddField),
                    ),
                  ),
                ),

              _SectionHeader(
                l10n.settingsWebFormDetailBehaviour,
                subtitle: isTicket
                    ? l10n.settingsWebFormDetailBehaviourSubTicket
                    : l10n.settingsWebFormDetailBehaviourSubLead,
              ),
              _Panel(
                children: [
                  _Text(
                    controller: _name,
                    label: l10n.commonName,
                    helper: l10n.settingsWebFormNameHelper,
                    enabled: isAdmin,
                  ),
                  _Text(
                    controller: _submitLabel,
                    label: l10n.settingsWebFormDetailSubmitButton,
                    enabled: isAdmin,
                    maxLength: 64,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: draft.successMode,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.settingsWebFormDetailAfterSuccess,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: WebForm.successMessage,
                        child: Text(l10n.settingsWebFormDetailShowMessage),
                      ),
                      DropdownMenuItem(
                        value: WebForm.successRedirect,
                        child: Text(l10n.settingsWebFormDetailRedirectToUrl),
                      ),
                    ],
                    onChanged: isAdmin
                        ? (value) => setState(
                            () => _draft = draft.copyWith(successMode: value),
                          )
                        : null,
                  ),
                  if (draft.redirectsOnSuccess)
                    _Text(
                      controller: _redirectUrl,
                      label: l10n.settingsWebFormDetailRedirectUrl,
                      helper: l10n.settingsWebFormDetailRedirectHelper,
                      enabled: isAdmin,
                      keyboardType: TextInputType.url,
                    )
                  else
                    _Text(
                      controller: _successMessage,
                      label: l10n.settingsWebFormDetailSuccessMessage,
                      enabled: isAdmin,
                      minLines: 2,
                      maxLines: 4,
                    ),
                  if (!draft.isTicket)
                    DropdownButtonFormField<String>(
                      initialValue: draft.assignmentMode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.settingsWebFormDetailAssignNewLeads,
                        helperText: l10n.settingsWebFormDetailAssignHelper,
                        helperMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: WebForm.assignPerson,
                          child: Text(l10n.settingsWebFormDetailToOnePerson),
                        ),
                        DropdownMenuItem(
                          value: WebForm.assignRotation,
                          child: Text(l10n.settingsWebFormDetailRotateMembers),
                        ),
                      ],
                      onChanged: isAdmin
                          ? (value) => setState(
                              () => _draft = draft.copyWith(
                                assignmentMode: value,
                              ),
                            )
                          : null,
                    ),
                  if (!draft.isTicket && draft.isRotation) ...[
                    _MultiPick(
                      label: l10n.settingsWebFormDetailRotateBetween,
                      empty: l10n.settingsWebFormDetailRotateEmpty,
                      options: [
                        for (final member in offListMembers)
                          (
                            id: member.id,
                            name: member.isActive
                                ? member.displayName
                                : l10n.settingsWebFormDetailDeactivated(
                                    member.displayName,
                                  ),
                          ),
                        for (final profile in profiles)
                          (id: profile.id, name: profile.displayName),
                      ],
                      selected: draft.rotationMembers,
                      enabled: isAdmin,
                      onChanged: (ids) => setState(
                        () => _draft = draft.copyWith(rotationMembers: ids),
                      ),
                    ),
                    Text(
                      [
                        l10n.settingsWebFormDetailRotationHint,
                        if (detail.form.isRotation)
                          lastAssigned == null
                              ? l10n.settingsWebFormDetailLastAssignedNobody
                              : l10n.settingsWebFormDetailLastAssigned(
                                  lastAssigned.displayName,
                                ),
                      ].join(' '),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    _Text(
                      controller: _rotationCap,
                      label: l10n.settingsWebFormDetailCapLabel,
                      hint: l10n.settingsWebFormDetailCapHint,
                      helper: l10n.settingsWebFormDetailCapHelper,
                      enabled: isAdmin,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ] else
                    DropdownButtonFormField<String?>(
                      initialValue: draft.assignTo,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: isTicket
                            ? l10n.settingsWebFormDetailAssignTicketsTo
                            : l10n.settingsWebFormDetailAssignLeadsTo,
                        helperText:
                            offList != null &&
                                !offList.isActive &&
                                draft.assignTo == offList.id
                            ? isTicket
                                  ? l10n.settingsWebFormDetailDeactivatedTicketHelper
                                  : l10n.settingsWebFormDetailDeactivatedLeadHelper
                            : null,
                        helperMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l10n.settingsWebFormDetailNobody),
                        ),
                        if (offList != null)
                          DropdownMenuItem(
                            value: offList.id,
                            child: Text(
                              offList.isActive
                                  ? offList.displayName
                                  : l10n.settingsWebFormDetailDeactivated(
                                      offList.displayName,
                                    ),
                            ),
                          ),
                        for (final profile in profiles)
                          DropdownMenuItem(
                            value: profile.id,
                            child: Text(profile.displayName),
                          ),
                      ],
                      onChanged: isAdmin
                          ? (value) => setState(
                              () => _draft = value == null
                                  ? draft.copyWith(clearAssignTo: true)
                                  : draft.copyWith(assignTo: value),
                            )
                          : null,
                    ),
                  if (draft.isTicket) ...[
                    DropdownButtonFormField<String>(
                      initialValue: draft.ticketPriority,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.settingsWebFormDetailTicketPriority,
                        helperText: l10n.settingsWebFormDetailPriorityHelper,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final p in ticketPriorities)
                          DropdownMenuItem(
                            value: p,
                            child: Text(_priorityLabel(l10n, p)),
                          ),
                      ],
                      onChanged: isAdmin
                          ? (value) => setState(
                              () => _draft = draft.copyWith(
                                ticketPriority: value,
                              ),
                            )
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: draft.ticketType,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.settingsWebFormDetailTicketType,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(l10n.settingsWebFormDetailNoType),
                        ),
                        for (final t in ticketTypes)
                          DropdownMenuItem(
                            value: t,
                            child: Text(_ticketTypeLabel(l10n, t)),
                          ),
                      ],
                      onChanged: isAdmin
                          ? (value) => setState(
                              () => _draft = draft.copyWith(
                                ticketType: value ?? '',
                              ),
                            )
                          : null,
                    ),
                  ],
                  _MultiPick(
                    label: isTicket
                        ? l10n.settingsWebFormDetailNotifyTicket
                        : l10n.settingsWebFormDetailNotifyLead,
                    empty: l10n.settingsWebFormDetailNobodyElse,
                    options: [
                      for (final profile in profiles)
                        (id: profile.id, name: profile.displayName),
                    ],
                    selected: draft.notifyProfiles,
                    enabled: isAdmin,
                    onChanged: (ids) => setState(
                      () => _draft = draft.copyWith(notifyProfiles: ids),
                    ),
                  ),
                  _MultiPick(
                    label: isTicket
                        ? l10n.settingsWebFormDetailTagTicket
                        : l10n.settingsWebFormDetailTagLead,
                    empty: l10n.settingsWebFormDetailNoTags,
                    options: [
                      for (final tag in tags) (id: tag.id, name: tag.name),
                    ],
                    selected: draft.tags,
                    enabled: isAdmin,
                    onChanged: (ids) =>
                        setState(() => _draft = draft.copyWith(tags: ids)),
                  ),
                ],
              ),

              _SectionHeader(
                l10n.settingsWebFormDetailSpam,
                subtitle: l10n.settingsWebFormDetailSpamSub,
              ),
              _Panel(
                children: [
                  _Text(
                    controller: _origins,
                    label: l10n.settingsWebFormDetailOrigins,
                    helper: l10n.settingsWebFormDetailOriginsHelper,
                    enabled: isAdmin,
                    minLines: 2,
                    maxLines: 5,
                  ),
                  // Its own Material. `_Panel` paints the surface colour, and
                  // a ListTile draws its ink splash on the nearest Material
                  // ancestor, so without this the row is tappable and looks
                  // inert.
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      value: draft.rejectDisposableEmail,
                      onChanged: isAdmin
                          ? (value) => setState(
                              () => _draft = draft.copyWith(
                                rejectDisposableEmail: value,
                              ),
                            )
                          : null,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.settingsWebFormDetailRejectDisposable),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: draft.captchaProvider,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.settingsWebFormDetailChallenge,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: WebForm.captchaNone,
                        child: Text(l10n.settingsWebFormDetailChallengeNone),
                      ),
                      const DropdownMenuItem(
                        value: WebForm.captchaTurnstile,
                        child: Text('Cloudflare Turnstile'),
                      ),
                    ],
                    onChanged: isAdmin
                        ? (value) => setState(
                            () =>
                                _draft = draft.copyWith(captchaProvider: value),
                          )
                        : null,
                  ),
                  if (draft.usesTurnstile) ...[
                    _Text(
                      controller: _captchaSiteKey,
                      label: l10n.settingsWebFormDetailSiteKey,
                      enabled: isAdmin,
                    ),
                    _Text(
                      controller: _captchaSecret,
                      label: l10n.settingsWebFormDetailSecret,
                      hint: detail.form.hasCaptchaSecret
                          ? l10n.settingsWebFormDetailSecretStoredHint
                          : l10n.settingsWebFormDetailSecretPasteHint,
                      helper: detail.form.hasCaptchaSecret
                          ? l10n.settingsWebFormDetailSecretStoredHelper
                          : l10n.settingsWebFormDetailSecretMissingHelper,
                      enabled: isAdmin,
                      obscure: true,
                    ),
                  ],
                ],
              ),

              _SectionHeader(
                l10n.settingsWebFormDetailEmbed,
                subtitle: l10n.settingsWebFormDetailEmbedSub,
              ),
              _Snippet(
                title: 'iframe',
                note: l10n.settingsWebFormDetailIframeNote,
                code: detail.form.embedHtml,
                onCopy: () => _copy(
                  detail.form.embedHtml,
                  () => context.l10n.settingsWebFormDetailIframeCopied,
                ),
              ),
              _Snippet(
                title: 'script',
                note: l10n.settingsWebFormDetailScriptNote,
                code: detail.form.embedJs,
                warning: detail.form.allowedOrigins.isEmpty
                    ? l10n.settingsWebFormDetailScriptWarning
                    : null,
                onCopy: () => _copy(
                  detail.form.embedJs,
                  () => context.l10n.settingsWebFormDetailScriptCopied,
                ),
              ),

              _SectionHeader(
                l10n.settingsWebFormDetailActivity,
                subtitle: l10n.settingsWebFormDetailActivitySub,
              ),
              if (detail.analytics != null)
                _AnalyticsRow(
                  analytics: detail.analytics!,
                  noun: isTicket
                      ? l10n.settingsWebFormDetailStatTickets
                      : l10n.settingsWebFormDetailStatLeads,
                ),
              _Submissions(
                submissions: detail.submissions,
                total: detail.submissionCount,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// [ticketPriorities] are API codes; only what the dropdown shows is translated.
String _priorityLabel(AppLocalizations l10n, String code) => switch (code) {
  'Low' => l10n.settingsWebFormDetailPriorityLow,
  'Normal' => l10n.settingsWebFormDetailPriorityNormal,
  'High' => l10n.settingsWebFormDetailPriorityHigh,
  'Urgent' => l10n.settingsWebFormDetailPriorityUrgent,
  _ => code,
};

String _ticketTypeLabel(AppLocalizations l10n, String code) => switch (code) {
  'Question' => l10n.settingsWebFormDetailTypeQuestion,
  'Incident' => l10n.settingsWebFormDetailTypeIncident,
  'Problem' => l10n.settingsWebFormDetailTypeProblem,
  _ => code,
};

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.form,
    required this.isAdmin,
    required this.blocker,
    required this.onToggle,
  });

  final WebForm form;
  final bool isAdmin;
  final String? blocker;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(
                label: form.isPublished
                    ? context.l10n.settingsWebFormPublished
                    : context.l10n.settingsWebFormDraft,
                color: form.isPublished
                    ? AppColors.success600
                    : AppColors.gray500,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${form.isTicket ? context.l10n.settingsWebFormDetailCreatesTickets : context.l10n.settingsWebFormDetailCreatesLeads} '
                  '${form.isPublished ? context.l10n.settingsWebFormDetailAccepting : context.l10n.settingsWebFormDetailCollectingNothing}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (isAdmin) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                // Disabled with the reason printed below rather than hidden:
                // "why can I not publish this" is the question the screen
                // exists to answer.
                onPressed: form.isPublished || blocker == null
                    ? onToggle
                    : null,
                style: form.isPublished
                    ? OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger600,
                      )
                    : null,
                child: Text(
                  form.isPublished
                      ? context.l10n.settingsWebFormDetailUnpublish
                      : context.l10n.settingsWebFormDetailPublish,
                ),
              ),
            ),
            if (!form.isPublished && blocker != null) ...[
              const SizedBox(height: 8),
              Text(
                blocker!,
                style: AppTypography.caption.copyWith(
                  color: AppColors.warning600,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _FieldList extends StatelessWidget {
  const _FieldList({
    required this.fields,
    required this.isAdmin,
    required this.onReorder,
    required this.onEdit,
    required this.onRemove,
  });

  final List<WebFormField> fields;
  final bool isAdmin;
  final void Function(int, int) onReorder;
  final void Function(WebFormField) onEdit;
  final void Function(WebFormField) onRemove;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.settingsWebFormDetailFieldsEmpty,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      // The enclosing ListView already scrolls. Two scrollables sharing one
      // gesture is the other way a drag here stops working.
      physics: const NeverScrollableScrollPhysics(),
      // No default handles: the whole row would become the drag target, and
      // the row's own tap-to-edit would then win the gesture arena and kill
      // the drag. The explicit listener below is the handle instead.
      buildDefaultDragHandles: false,
      itemCount: fields.length,
      // `onReorderItem`, not `onReorder`. It hands over the index the row ends
      // up at rather than an insertion point, so the buttons and the drag can
      // pass the same numbers to the same function.
      onReorderItem: onReorder,
      itemBuilder: (context, index) {
        final field = fields[index];
        return _FieldRow(
          key: ValueKey('${field.id ?? ''}-${field.label}-$index'),
          field: field,
          index: index,
          total: fields.length,
          isAdmin: isAdmin,
          onEdit: () => onEdit(field),
          onRemove: () => onRemove(field),
          onMoveUp: index == 0 ? null : () => onReorder(index, index - 1),
          onMoveDown: index == fields.length - 1
              ? null
              : () => onReorder(index, index + 1),
        );
      },
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.field,
    required this.index,
    required this.total,
    required this.isAdmin,
    required this.onEdit,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final WebFormField field;
  final int index;
  final int total;
  final bool isAdmin;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final target = field.isCustom
        ? l10n.settingsWebFormCustomField
        : field.builtinLabel;

    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          if (isAdmin)
            // An explicit handle, not a long-press on the row. A child's own
            // recognizer wins the gesture arena against an enclosing drag, so
            // the row's tap-to-edit would silently kill a row-level drag.
            ReorderableDragStartListener(
              index: index,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: Icon(
                  LucideIcons.gripVertical,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          Expanded(
            child: InkWell(
              onTap: isAdmin ? onEdit : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      field.displayLabel,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      field.isRequired
                          ? l10n.settingsWebFormDetailFieldRequired(target)
                          : target,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    if (!field.isComplete) ...[
                      const SizedBox(height: 2),
                      Text(
                        l10n.settingsWebFormDetailFieldIncomplete,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warning600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isAdmin) ...[
            // The same move the drag makes, without needing a drag to land.
            // Both call `onReorder`, so there is one implementation.
            _IconAction(
              icon: LucideIcons.chevronUp,
              tooltip: l10n.settingsWebFormDetailMoveUp(field.displayLabel),
              onPressed: onMoveUp,
            ),
            _IconAction(
              icon: LucideIcons.chevronDown,
              tooltip: l10n.settingsWebFormDetailMoveDown(field.displayLabel),
              onPressed: onMoveDown,
            ),
            _IconAction(
              icon: LucideIcons.trash2,
              tooltip: l10n.settingsWebFormDetailRemoveField(
                field.displayLabel,
              ),
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

/// 44 logical pixels square, because the pointer here is a fingertip and an
/// icon-only button has nothing to pad around.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 18),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        color: AppColors.textSecondary,
        disabledColor: AppColors.gray300,
        onPressed: onPressed,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTypography.overline.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text({
    required this.controller,
    required this.label,
    this.helper,
    this.hint,
    this.enabled = true,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final String? hint;
  final bool enabled;
  final int? minLines;
  final int maxLines;
  final int? maxLength;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      minLines: minLines,
      maxLines: obscure ? 1 : maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 4,
        hintText: hint,
        border: const OutlineInputBorder(),
        counterText: '',
      ),
    );
  }
}

/// A multi-select rendered as chips.
///
/// A Material multi-select dropdown does not exist, and a dialog for two or
/// three names is more taps than the choice is worth.
class _MultiPick extends StatelessWidget {
  const _MultiPick({
    required this.label,
    required this.empty,
    required this.options,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String empty;
  final List<({String id, String name})> options;
  final List<String> selected;
  final bool enabled;
  final void Function(List<String>) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        if (options.isEmpty)
          Text(
            empty,
            style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                FilterChip(
                  label: Text(option.name),
                  selected: selected.contains(option.id),
                  onSelected: enabled
                      ? (isSelected) {
                          final next = [...selected];
                          if (isSelected) {
                            next.add(option.id);
                          } else {
                            next.remove(option.id);
                          }
                          onChanged(next);
                        }
                      : null,
                ),
            ],
          ),
      ],
    );
  }
}

class _Snippet extends StatelessWidget {
  const _Snippet({
    required this.title,
    required this.note,
    required this.code,
    required this.onCopy,
    this.warning,
  });

  final String title;
  final String note;
  final String code;
  final String? warning;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      note,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(LucideIcons.copy, size: 15),
                  label: Text(context.l10n.settingsWebFormDetailCopy),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Scrolls inside its own box. Without this a long absolute URL
          // widens the whole screen and every section inherits a sideways
          // swipe.
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.gray100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gray200),
            ),
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                code,
                style: AppTypography.caption.copyWith(
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          if (warning != null) ...[
            const SizedBox(height: 8),
            Text(
              warning!,
              style: AppTypography.caption.copyWith(
                color: AppColors.warning600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnalyticsRow extends StatelessWidget {
  const _AnalyticsRow({required this.analytics, required this.noun});

  final WebFormAnalytics analytics;

  /// "leads" or "tickets": what an accepted submission created.
  final String noun;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      margin: const EdgeInsets.only(bottom: 1),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          _Stat(
            value: '${analytics.views}',
            label: context.l10n.settingsWebFormDetailStatViews,
          ),
          _Stat(value: '${analytics.submissions}', label: noun),
          _Stat(
            // Guarded rather than computed blind: a brand new form has zero
            // views, and this is the first thing its screen renders.
            value: analytics.views == 0
                ? '-'
                : '${(analytics.conversionRate * 100).round()}%',
            label: context.l10n.settingsWebFormDetailStatConversion,
          ),
          _Stat(
            value: '${analytics.spam}',
            label: context.l10n.settingsWebFormStatSpam,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: AppTypography.h2.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _Submissions extends StatelessWidget {
  const _Submissions({required this.submissions, required this.total});

  final List<WebFormSubmission> submissions;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (submissions.isEmpty) {
      return Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: Text(
          context.l10n.settingsWebFormDetailSubmissionsEmpty,
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    return Column(
      children: [
        for (final submission in submissions)
          InkWell(
            // A ticket form's accepted row opens the ticket it created. The
            // detail screen applies the ticket's own read rule, so a member
            // who may not see it is told so there rather than here.
            onTap: submission.caseId == null
                ? null
                : () => context.push('/tickets/${submission.caseId}'),
            child: Container(
              color: AppColors.surface,
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          submission.caseName ??
                              submission.leadName ??
                              submission.statusLabel,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          submission.referer.isEmpty
                              ? submission.statusLabel
                              : '${submission.statusLabel} · '
                                    '${submission.referer}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(
                    label: !submission.isAccepted
                        ? context.l10n.settingsWebFormDetailBadgeRefused
                        : submission.caseId != null
                        ? context.l10n.settingsWebFormDetailBadgeTicket
                        : context.l10n.settingsWebFormDetailBadgeLead,
                    color: submission.isAccepted
                        ? AppColors.success600
                        : AppColors.gray500,
                  ),
                ],
              ),
            ),
          ),
        if (total > submissions.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.settingsWebFormShowingRecent(
                  submissions.length,
                  total,
                ),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
