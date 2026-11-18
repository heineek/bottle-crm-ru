import 'package:bottle_crm/data/models/models.dart';
import 'package:bottle_crm/data/models/sales_goal.dart';
import 'package:bottle_crm/services/app_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => applyLanguage(baseLanguage));

  group('model labels follow the current language', () {
    test('English is unchanged', () {
      expect(LeadStatus.closed.label, 'Closed');
      expect(TicketStatus.closed.label, 'Closed');
      expect(TaskStatus.completed.label, 'Completed');
      expect(InvoiceStatus.partiallyPaid.label, 'Partially paid');
      expect(goalStatusLabel('on_track'), 'On track');
    });

    test('the API values do not change with the language', () {
      expect(Priority.high.value, 'High');
      expect(boardPriorityValue(Priority.high), 'high');
      expect(TicketStatus.closed.value, 'Closed');
    });
  });
}
