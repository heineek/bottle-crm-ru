import 'countries.dart';
import 'org_settings.dart';

/// `GET /api/org/locales/`: countries named in the caller's language, sorted
/// by that name. The web reads the same list, so a country is called the same
/// thing on both clients.
class OrgLocales {
  final List<PickerOption> countries;

  const OrgLocales({required this.countries});

  factory OrgLocales.fromJson(Map<String, dynamic> json) {
    final raw = json['countries'];
    return OrgLocales(
      countries: [
        if (raw is List)
          for (final c in raw)
            if (c is Map && c['code'] is String && c['name'] is String)
              (value: c['code'] as String, label: c['name'] as String),
      ],
    );
  }

  /// The bundled English list, for an API that does not serve this yet or a
  /// request that failed: a country picker must never come up empty.
  static final OrgLocales fallback = OrgLocales(
    countries: [for (final c in kCountries) (value: c.code, label: c.label)],
  );

  /// The name for [code], or [code] itself when the list does not know it.
  String? countryName(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final c in countries) {
      if (c.value == code) return c.label;
    }
    return code;
  }
}
