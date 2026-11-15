import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n_merge.dart';

/// `lib/l10n/app_*.arb` is built from `lib/l10n/parts/<module>/<locale>.json`
/// by `dart run tool/l10n_merge.dart`. An edited fragment without a re-run
/// ships the old strings, so the committed ARBs must equal a fresh merge.
void main() {
  test('the ARBs are the merge of the fragments', () {
    final merged = mergeArbs();
    expect(merged.keys, containsAll(['app_en.arb', 'app_ru.arb']));
    for (final entry in merged.entries) {
      expect(
        File('$arbDir/${entry.key}').readAsStringSync(),
        entry.value,
        reason: 'run: dart run tool/l10n_merge.dart && flutter gen-l10n',
      );
    }
  });

  test('a key two modules define is refused', () {
    final dir = Directory.systemTemp.createTempSync('l10n_parts');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final module in ['a', 'b']) {
      Directory('${dir.path}/$module').createSync();
      File('${dir.path}/$module/en.json').writeAsStringSync('{"sameKey": "x"}');
    }

    expect(() => mergeArbs(parts: dir.path), throwsStateError);
  });
}
