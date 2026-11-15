/// Builds `lib/l10n/app_<locale>.arb` from the per-module fragments in
/// `lib/l10n/parts/<module>/<locale>.json`.
///
/// `flutter gen-l10n` reads exactly one ARB per locale, so a file every module
/// edits would be a merge conflict on every change. Each module owns its
/// fragment instead; this concatenates them in module order. Run it after
/// editing a fragment, then `flutter gen-l10n`:
///
///     dart run tool/l10n_merge.dart && flutter gen-l10n
///
/// `test/unit/l10n_merge_test.dart` fails when the ARBs are stale.
library;

import 'dart:convert';
import 'dart:io';

const String partsDir = 'lib/l10n/parts';
const String arbDir = 'lib/l10n';

/// The merged ARB for every locale found in the fragments, as file name to
/// content. Throws on a key two modules define, which gen-l10n would
/// otherwise resolve silently in favour of whichever came last.
Map<String, String> mergeArbs({String parts = partsDir}) {
  final modules = Directory(parts).listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final locales = <String>{
    for (final module in modules)
      for (final file in module.listSync().whereType<File>())
        if (file.path.endsWith('.json'))
          file.uri.pathSegments.last.replaceAll('.json', ''),
  };

  final out = <String, String>{};
  for (final locale in locales.toList()..sort()) {
    final merged = <String, Object?>{'@@locale': locale};
    final owner = <String, String>{};
    for (final module in modules) {
      final name = module.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final file = File('${module.path}/$locale.json');
      if (!file.existsSync()) continue;
      final entries =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final entry in entries.entries) {
        if (entry.key.startsWith('@@')) continue;
        final clash = owner[entry.key];
        if (clash != null) {
          throw StateError(
            '"${entry.key}" is defined by both $clash and $name',
          );
        }
        owner[entry.key] = name;
        merged[entry.key] = entry.value;
      }
    }
    out['app_$locale.arb'] =
        '${const JsonEncoder.withIndent('  ').convert(merged)}\n';
  }
  return out;
}

void main() {
  for (final entry in mergeArbs().entries) {
    File('$arbDir/${entry.key}').writeAsStringSync(entry.value);
  }
}
