import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/theme.dart';
import '../../data/models/contact.dart';
import '../../data/models/lookup_models.dart';
import '../../providers/contacts_provider.dart';
import '../../providers/duplicates_provider.dart';
import '../../providers/lookup_provider.dart';
import '../../widgets/duplicates/duplicate_notice.dart';
import '../../widgets/forms/unsaved_changes.dart';
import '../../l10n/l10n.dart';

/// Create or edit a contact.
class ContactFormScreen extends ConsumerStatefulWidget {
  const ContactFormScreen({super.key, this.contactId});

  final String? contactId;

  bool get isEditMode => contactId != null;

  @override
  ConsumerState<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends ConsumerState<ContactFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _title = TextEditingController();
  final _department = TextEditingController();
  final _organization = TextEditingController();
  final _linkedin = TextEditingController();
  final _addressLine = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _postcode = TextEditingController();
  final _country = TextEditingController();
  final _description = TextEditingController();

  bool _doNotCall = false;
  String? _accountId;

  Contact? _existing;
  String? _baseline;
  bool _fetching = false;
  bool _saving = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    if (widget.isEditMode) {
      _fetch();
    } else {
      _baseline = _snapshot();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _lastName,
      _email,
      _phone,
      _title,
      _department,
      _organization,
      _linkedin,
      _addressLine,
      _city,
      _state,
      _postcode,
      _country,
      _description,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _fetching = true;
      _fetchError = null;
    });
    final contact = await ref
        .read(contactsProvider.notifier)
        .getContact(widget.contactId!);
    if (!mounted) return;
    setState(() {
      _fetching = false;
      if (contact == null) {
        _fetchError = context.l10n.contactsFormLoadFailed;
      } else {
        _existing = contact;
        _populate(contact);
      }
    });
    _baseline = _snapshot();
  }

  void _populate(Contact contact) {
    _firstName.text = contact.firstName;
    _lastName.text = contact.lastName;
    _email.text = contact.email ?? '';
    _phone.text = contact.phone ?? '';
    _title.text = contact.title ?? '';
    _department.text = contact.department ?? '';
    _organization.text = contact.organization ?? '';
    _linkedin.text = contact.linkedinUrl ?? '';
    _addressLine.text = contact.addressLine ?? '';
    _city.text = contact.city ?? '';
    _state.text = contact.state ?? '';
    _postcode.text = contact.postcode ?? '';
    _country.text = contact.country ?? '';
    _description.text = contact.description ?? '';
    _doNotCall = contact.doNotCall;
    _accountId = contact.accountId;
  }

  Map<String, dynamic> _buildPayload() {
    final base =
        _existing ?? const Contact(id: '', firstName: '', lastName: '');
    return base
        .copyWith(
          firstName: _firstName.text,
          lastName: _lastName.text,
          email: _email.text,
          phone: _phone.text,
          title: _title.text,
          department: _department.text,
          organization: _organization.text,
          linkedinUrl: _linkedin.text,
          addressLine: _addressLine.text,
          city: _city.text,
          state: _state.text,
          postcode: _postcode.text,
          country: _country.text,
          description: _description.text,
          doNotCall: _doNotCall,
          accountId: _accountId,
          clearAccount: _accountId == null,
        )
        .toPayload();
  }

  String _snapshot() => _buildPayload().toString();

  bool get _hasUnsavedChanges => _baseline != null && _snapshot() != _baseline;

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final notifier = ref.read(contactsProvider.notifier);
    final payload = _buildPayload();

    final String? failure;
    if (widget.isEditMode) {
      failure = await notifier.updateContact(widget.contactId!, payload);
    } else {
      failure = (await notifier.createContact(payload)).error;
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure), backgroundColor: AppColors.danger600),
      );
      return;
    }
    _baseline = _snapshot();
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return UnsavedChangesGuard(
      hasUnsavedChanges: () => _hasUnsavedChanges,
      isSaving: _saving,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: Text(
            widget.isEditMode
                ? context.l10n.contactsFormEditTitle
                : context.l10n.contactsFormNewTitle,
          ),
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 1,
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: _saving
                ? null
                : () =>
                      leaveForm(context, hasUnsavedChanges: _hasUnsavedChanges),
          ),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_fetching) return const Center(child: CircularProgressIndicator());
    if (_fetchError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.alertCircle, size: 40, color: AppColors.danger500),
            const SizedBox(height: 12),
            Text(_fetchError!, style: AppTypography.body),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _fetch,
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      );
    }

    final accounts = ref.watch(accountOptionsProvider);
    final l10n = context.l10n;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              _firstName,
              l10n.contactsFormFirstName,
              autofocus: !widget.isEditMode,
              validator: (v) => (v?.trim().isEmpty ?? true)
                  ? l10n.contactsFormFirstNameRequired
                  : null,
            ),
            _field(
              _lastName,
              l10n.contactsFormLastName,
              validator: (v) => (v?.trim().isEmpty ?? true)
                  ? l10n.contactsFormLastNameRequired
                  : null,
            ),
            _field(
              _email,
              l10n.commonEmail,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return null;
                // The server also rejects a duplicate within the org, which
                // this cannot know. That message is surfaced from the response.
                return email.contains('@')
                    ? null
                    : l10n.contactsFormEmailInvalid;
              },
            ),
            _field(_phone, l10n.commonPhone, keyboardType: TextInputType.phone),
            if (!widget.isEditMode)
              DuplicateNotice(
                module: DuplicateModule.contacts,
                fields: {
                  'first_name': _firstName,
                  'last_name': _lastName,
                  'email': _email,
                  'phone': _phone,
                },
              ),
            _accountPicker(accounts),
            _field(_title, l10n.contactsFormJobTitle),
            _field(_department, l10n.contactsFormDepartment),
            _field(_organization, l10n.contactsFormCompany),
            _field(
              _linkedin,
              l10n.contactsFormLinkedin,
              keyboardType: TextInputType.url,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _doNotCall,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _doNotCall = value),
              title: Text(l10n.contactsFormDoNotCall),
              subtitle: Text(
                l10n.contactsFormDoNotCallHint,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.contactsFormAddress,
              style: AppTypography.label.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _field(_addressLine, l10n.contactsFormStreet),
            _field(_city, l10n.contactsFormCity),
            _field(_state, l10n.contactsFormState),
            _field(_postcode, l10n.contactsFormPostcode),
            _field(
              _country,
              l10n.contactsFormCountryCode,
              hint: l10n.contactsFormCountryHint,
              validator: (value) {
                final code = value?.trim() ?? '';
                if (code.isEmpty) return null;
                return RegExp(r'^[A-Za-z]{2}$').hasMatch(code)
                    ? null
                    : l10n.contactsFormCountryInvalid;
              },
            ),
            _field(_description, l10n.commonNotes, maxLines: 4),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        widget.isEditMode
                            ? l10n.contactsFormSaveChanges
                            : l10n.contactsFormCreate,
                      ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  /// The account link.
  ///
  /// "No account" is a real, selectable option rather than the absence of a
  /// choice, because a select whose value matches no option submits its first
  /// entry, which would attach the contact to whichever company happens to
  /// sort first.
  ///
  /// The account the contact is already linked to is always an item, even
  /// when the lookup does not carry it: one the user cannot open (the lookup
  /// holds only those they can), a closed one, or one past the lookup cap.
  /// Otherwise the picker reads "No account" while the save keeps the link.
  /// The server keeps an unchanged link whoever saves, and refuses a newly
  /// chosen account the user cannot open.
  Widget _accountPicker(List<AccountLookup> lookup) {
    final storedId = _existing?.accountId;
    final accounts = storedId == null || lookup.any((a) => a.id == storedId)
        ? lookup
        : [
            AccountLookup(
              id: storedId,
              name:
                  _existing?.accountName ??
                  context.l10n.contactsFormCurrentAccount,
            ),
            ...lookup,
          ];
    final ids = accounts.map((a) => a.id).toSet();
    final value = ids.contains(_accountId) ? _accountId : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.l10n.contactsFormAccount,
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text(context.l10n.contactsFormNoAccount),
          ),
          ...accounts.map(
            (a) => DropdownMenuItem<String?>(
              value: a.id,
              child: Text(a.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: _saving ? null : (next) => setState(() => _accountId = next),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool autofocus = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        autofocus: autofocus,
        enabled: !_saving,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
