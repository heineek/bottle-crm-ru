import { describe, it, expect } from 'vitest';
import { COUNTRIES, getCountryName, sortedCountries } from '#lib/constants/countries.js';

describe('countries in English', () => {
  it('keep the backend names', () => {
    expect(getCountryName('AX')).toBe('Aland Islands');
    expect(COUNTRIES[0]).toEqual({ code: 'GB', name: 'United Kingdom' });
  });

  it('sort by name and return plain objects', () => {
    const list = sortedCountries();
    const names = list.map((c) => c.name);
    expect(names[0]).toBe('Afghanistan');
    expect(names).toHaveLength(COUNTRIES.length);
    expect(Object.getOwnPropertyDescriptor(list[0], 'name')?.get).toBeUndefined();
  });
});
