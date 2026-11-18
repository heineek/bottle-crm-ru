import { describe, it, expect } from 'vitest';
import {
  LEAD_STATUS_LABEL,
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

  it('keep the two priority sets apart', () => {
    expect('Medium' in CASE_PRIORITY_LABEL).toBe(false);
  });
});
