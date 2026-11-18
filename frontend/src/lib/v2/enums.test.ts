import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as runtime from '#lib/paraglide/runtime.js';
import {
  CASE_STATUS_LABEL,
  ESTIMATE_STATUS_LABEL,
  INVOICE_STATUS_LABEL,
  LEAD_STATUS_LABEL,
  TASK_PRIORITY_LABEL,
  CASE_PRIORITY_LABEL,
  AGING_LABEL,
  invoiceStatusLabel,
  industryLabel
} from '#lib/v2/enums.js';
import { LEAD_STATUSES, CURRENCY_CODES } from '#lib/constants/filters.js';

describe('labels in English', () => {
  it('keep the source strings', () => {
    expect(LEAD_STATUS_LABEL['in process']).toBe('In process');
    expect(invoiceStatusLabel('Partially_Paid')).toBe('Partially Paid');
    expect(invoiceStatusLabel('NET_30')).toBe('NET 30');
    expect(industryLabel('FOOD & BEVERAGE')).toBe('Food & beverage');
    expect(industryLabel('NOT AN INDUSTRY')).toBe('Not an industry');
    expect(LEAD_STATUSES.find((o) => o.value === 'IN_PROCESS')?.label).toBe('In Process');
    expect(CURRENCY_CODES.find((o) => o.value === 'USD')?.label).toBe('USD - Dollar');
  });

  it('iterate like plain objects', () => {
    expect(Object.keys(AGING_LABEL)).toEqual(['green', 'yellow', 'red']);
    expect({ ...AGING_LABEL }).toEqual({
      green: 'On pace',
      yellow: 'Past expected',
      red: 'Stalled'
    });
  });
});

describe('labels in Russian', () => {
  let original: typeof runtime.getLocale;
  beforeEach(() => {
    original = runtime.getLocale;
    runtime.overwriteGetLocale(() => 'ru');
  });
  afterEach(() => runtime.overwriteGetLocale(original));

  it('agree in gender with their entity', () => {
    expect(LEAD_STATUS_LABEL.closed).toBe('Закрыт');
    expect(CASE_STATUS_LABEL.Closed).toBe('Закрыто');
    expect(INVOICE_STATUS_LABEL.Sent).toBe('Отправлен');
    expect(ESTIMATE_STATUS_LABEL.Sent).toBe('Отправлено');
    expect(AGING_LABEL.red).toBe('Застряла');
  });

  it('keep the two priority sets apart', () => {
    expect(CASE_PRIORITY_LABEL.Normal).toBe('Обычный');
    expect(TASK_PRIORITY_LABEL.Medium).toBe('Средний');
    expect('Medium' in CASE_PRIORITY_LABEL).toBe(false);
  });

  it('switch per read, not per import', () => {
    expect(invoiceStatusLabel('Cancelled')).toBe('Отменён');
    expect(industryLabel('BANKING')).toBe('Банки');
    expect(LEAD_STATUSES.find((o) => o.value === 'CLOSED')?.label).toBe('Закрыт');
    runtime.overwriteGetLocale(() => 'en');
    expect(invoiceStatusLabel('Cancelled')).toBe('Cancelled');
  });

  it('name currencies through Intl', () => {
    expect(CURRENCY_CODES.find((o) => o.value === 'EUR')?.label).toBe('EUR - евро');
  });
});
