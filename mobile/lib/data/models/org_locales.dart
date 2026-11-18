import '../api/schema.g.dart' as api;
import 'countries.dart';
import 'org_settings.dart';

/// `GET /api/org/locales/`: countries named in the caller's language, sorted
/// by that name. The web reads the same list, so a country is called the same
/// thing on both clients.
class OrgLocales {
  final List<PickerOption> countries;

  const OrgLocales({required this.countries});

  /// Reads an `OrgLocalesResponse`.
  factory OrgLocales.fromJson(Map<String, dynamic> json) {
    final w = api.OrgLocalesResponse.fromJson(json);
    return OrgLocales(
      countries: [
        for (final c in w.countries ?? const <api.CountryOption>[])
          if ((c.code ?? '').isNotEmpty && c.name != null)
            (value: c.code!, label: c.name!),
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
