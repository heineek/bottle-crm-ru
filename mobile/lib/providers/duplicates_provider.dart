import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';
import '../l10n/l10n.dart';
import '../services/api_service.dart';
import 'accounts_provider.dart';
import 'contacts_provider.dart';
import 'leads_provider.dart';

/// Possible duplicates and merging, for leads, contacts and accounts (G19).
///
/// The API decides everything that matters. It searches only the records the
/// caller may open, so nothing here can show or count a hidden one, and it
/// refuses a merge the caller may not make. `canDelete` on a hit is a hint that
/// spares somebody a refusal, not a gate.
enum DuplicateModule {
  leads('leads', 'lead', 'lead_obj'),
  contacts('contacts', 'contact', 'contact_obj'),
  accounts('accounts', 'account', 'account_obj');

  const DuplicateModule(this.path, this.singular, this.recordKey);

  /// The API and router segment: `/leads/...`.
  final String path;
  final String singular;

  /// Where the detail endpoint nests the record.
  final String recordKey;

  static DuplicateModule? parse(String? value) {
    for (final module in values) {
      if (module.path == value) return module;
    }
    return null;
  }

  /// What each create form may ask about. Mirrors `DuplicateQuerySerializer`.
  List<String> get queryFields => switch (this) {
    leads => const [
      'email',
      'phone',
      'first_name',
      'last_name',
      'company_name',
    ],
    contacts => const ['email', 'phone', 'first_name', 'last_name'],
    accounts => const ['name', 'email', 'phone', 'website'],
  };

  /// The record kind in the current language, lowercase: "lead".
  String get singularLabel => appL10n.appDupSingular(name);

  /// The rows the compare screen shows side by side, the same as the web's.
  List<(String, String Function(Map<String, dynamic>))> get compareFields {
    final l10n = appL10n;
    return switch (this) {
      leads => [
        (l10n.commonName, _personName),
        (l10n.appDupFieldCompany, (o) => _text(o['company_name'])),
        (l10n.commonEmail, (o) => _text(o['email'])),
        (l10n.commonPhone, (o) => _text(o['phone'])),
        (l10n.appWebFormFieldWebsite, (o) => _text(o['website'])),
        (l10n.commonStatus, (o) => _text(o['status'])),
        (l10n.appDupFieldCreated, _created),
      ],
      contacts => [
        (l10n.commonName, _personName),
        (l10n.appWebFormFieldJobTitle, (o) => _text(o['title'])),
        (l10n.appDupFieldCompany, (o) => _text(o['organization'])),
        (l10n.commonEmail, (o) => _text(o['email'])),
        (l10n.commonPhone, (o) => _text(o['phone'])),
        (l10n.appWebFormFieldCity, (o) => _text(o['city'])),
        (l10n.appDupFieldCreated, _created),
      ],
      accounts => [
        (l10n.commonName, (o) => _text(o['name'])),
        (l10n.appWebFormFieldWebsite, (o) => _text(o['website'])),
        (l10n.commonEmail, (o) => _text(o['email'])),
        (l10n.commonPhone, (o) => _text(o['phone'])),
        (l10n.appWebFormFieldIndustry, (o) => _text(o['industry'])),
        (l10n.appWebFormFieldCity, (o) => _text(o['city'])),
        (l10n.appDupFieldCreated, _created),
      ],
    };
  }

  String nameOf(Map<String, dynamic> record) {
    final name = this == accounts ? _text(record['name']) : _personName(record);
    if (name.isNotEmpty) return name;
    final email = _text(record['email']);
    return email.isNotEmpty ? email : singularLabel;
  }
}

String _text(dynamic value) => value == null ? '' : value.toString().trim();

String _personName(Map<String, dynamic> o) => [
  _text(o['first_name']),
  _text(o['last_name']),
].where((s) => s.isNotEmpty).join(' ');

String _created(Map<String, dynamic> o) {
  final raw = _text(o['created_at']);
  return raw.length >= 10 ? raw.substring(0, 10) : raw;
}

/// "email and phone": the API names each rule in plain words already.
String matchedLabel(List<String> reasons) {
  if (reasons.length <= 1) return reasons.join();
  return appL10n.appJoinAnd(
    reasons.sublist(0, reasons.length - 1).join(', '),
    reasons.last,
  );
}

/// One possible duplicate. List-level fields only, which is all the API sends.
class DuplicateHit {
  const DuplicateHit({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    this.matchedOn = const [],
    this.canDelete = false,
  });

  final String id;
  final String name;
  final String email;
  final String phone;
  final List<String> matchedOn;

  /// Whether the caller could merge this record away.
  final bool canDelete;

  String get matchedLabelText => matchedLabel(matchedOn);

  factory DuplicateHit.fromJson(Map<String, dynamic> json) => DuplicateHit(
    id: json['id']?.toString() ?? '',
    name: _text(json['name']),
    email: _text(json['email']),
    phone: _text(json['phone']),
    matchedOn: [
      for (final r in (json['matched_on'] as List<dynamic>? ?? const []))
        r.toString(),
    ],
    canDelete: json['can_delete'] == true,
  );
}

class RecordDuplicates {
  const RecordDuplicates({this.canDelete = false, this.hits = const []});

  /// Whether the caller could merge the record itself away.
  final bool canDelete;
  final List<DuplicateHit> hits;
}

/// One side of the compare screen.
class MergeSide {
  const MergeSide({
    required this.id,
    required this.name,
    required this.canDelete,
    required this.fields,
  });

  final String id;
  final String name;
  final bool canDelete;
  final List<(String, String)> fields;
}

/// A merge side that could not be loaded. `notFound` covers a missing record
/// and one the caller may not open, which the API answers identically.
class MergeSideError implements Exception {
  const MergeSideError({required this.notFound});
  final bool notFound;
}

class DuplicatesApi {
  DuplicatesApi([ApiService? api]) : _api = api ?? ApiService();

  final ApiService _api;

  /// Possible duplicates of a record being typed. Only the module's own
  /// fields are sent, blank ones dropped, in a POST body rather than a query
  /// string: an email and a phone in a URL are written to access logs. A
  /// failure answers none: it is a hint beside a form, and the form must
  /// still save.
  Future<List<DuplicateHit>> check(
    DuplicateModule module,
    Map<String, String> criteria,
  ) async {
    final query = <String, String>{
      for (final field in module.queryFields)
        if ((criteria[field] ?? '').trim().isNotEmpty)
          field: criteria[field]!.trim(),
    };
    if (query.isEmpty) return const [];
    final response = await _api.post(
      ApiConfig.duplicatesCheck(module.path),
      query,
    );
    if (!response.success || response.data == null) return const [];
    return _hits(response.data!);
  }

  /// Possible duplicates of a saved record. None when the check fails.
  Future<RecordDuplicates> forRecord(DuplicateModule module, String id) async {
    final response = await _api.get(
      ApiConfig.recordDuplicates(module.path, id),
    );
    if (!response.success || response.data == null) {
      return const RecordDuplicates();
    }
    return RecordDuplicates(
      canDelete: response.data!['can_delete'] == true,
      hits: _hits(response.data!),
    );
  }

  /// One record for the compare screen: its detail, plus whether the caller
  /// may delete it (from its duplicates endpoint).
  Future<MergeSide> side(DuplicateModule module, String id) async {
    final results = await Future.wait([
      _api.get(ApiConfig.recordDetail(module.path, id)),
      _api.get(ApiConfig.recordDuplicates(module.path, id)),
    ]);
    final detail = results[0];
    final record = detail.data?[module.recordKey];
    if (!detail.success || record is! Map<String, dynamic>) {
      throw MergeSideError(notFound: detail.statusCode == 404);
    }
    return MergeSide(
      id: record['id']?.toString() ?? id,
      name: module.nameOf(record),
      canDelete: results[1].data?['can_delete'] == true,
      fields: [
        for (final (label, read) in module.compareFields) (label, read(record)),
      ],
    );
  }

  /// Merge [loserId] into [keeperId]. Null on success, else the reason.
  Future<String?> merge(
    DuplicateModule module,
    String keeperId,
    String loserId,
  ) async {
    final response = await _api.post(
      ApiConfig.mergeRecord(module.path, keeperId),
      {'merge_id': loserId},
    );
    if (response.success) return null;
    if (response.statusCode == 404) {
      return appL10n.appDupMergeGone(module.name);
    }
    return response.message ?? appL10n.appDupMergeFailed(module.name);
  }

  List<DuplicateHit> _hits(Map<String, dynamic> data) => [
    for (final raw in (data['duplicates'] as List<dynamic>? ?? const []))
      if (raw is Map<String, dynamic>) DuplicateHit.fromJson(raw),
  ];
}

final duplicatesApiProvider = Provider<DuplicatesApi>((ref) => DuplicatesApi());

final recordDuplicatesProvider = FutureProvider.autoDispose
    .family<RecordDuplicates, (DuplicateModule, String)>(
      (ref, key) => ref.read(duplicatesApiProvider).forRecord(key.$1, key.$2),
    );

/// After a merge: the loser is gone from its list and the keeper changed, so
/// the module's list and every duplicates panel are read again.
void refreshAfterMerge(WidgetRef ref, DuplicateModule module) {
  switch (module) {
    case DuplicateModule.leads:
      ref.invalidate(leadsProvider);
    case DuplicateModule.contacts:
      ref.invalidate(contactsProvider);
    case DuplicateModule.accounts:
      ref.invalidate(accountsProvider);
  }
  ref.invalidate(recordDuplicatesProvider);
}
