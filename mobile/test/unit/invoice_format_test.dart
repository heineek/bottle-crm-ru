import 'package:bottle_crm/screens/invoices/invoice_format.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => applyLanguage('en'));

  group('in English', () {
    setUp(() => applyLanguage('en'));

    test('money keeps the symbol first and the sign leading', () {
      expect(money(1234.5, r'$'), r'$1,234.50');
      expect(money(-40, r'$'), r'-$40.00');
      expect(money(0, '€'), '€0.00');
    });

    test('compactMoney shortens thousands and millions', () {
      expect(compactMoney(950, r'$'), r'$950');
      expect(compactMoney(12500, r'$'), r'$12.5k');
      expect(compactMoney(2500000, r'$'), r'$2.5M');
      expect(compactMoney(12500, ''), '12.5k');
    });
  });
}
