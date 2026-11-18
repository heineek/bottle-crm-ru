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

  group('in Russian', () {
    setUp(() => applyLanguage('ru'));

    test(
      'money groups with a space, uses a comma and puts the symbol after',
      () {
        expect(money(1234.5, '₽'), '1 234,50 ₽');
        expect(money(-40, '₽'), '-40,00 ₽');
        expect(money(1234.5, ''), '1 234,50');
      },
    );

    test('compactMoney says тыс. and млн', () {
      expect(compactMoney(950, '₽'), '950 ₽');
      expect(compactMoney(12500, '₽'), '12,5 тыс. ₽');
      expect(compactMoney(2500000, '₽'), '2,5 млн ₽');
      expect(compactMoney(12500, ''), '12,5 тыс.');
      expect(compactMoney(12500, 'RUB '), '12,5 тыс. RUB');
    });

    test('a language switch is picked up without a restart', () {
      expect(money(1234.5, '₽'), '1 234,50 ₽');
      applyLanguage('en');
      expect(money(1234.5, r'$'), r'$1,234.50');
    });
  });
}
