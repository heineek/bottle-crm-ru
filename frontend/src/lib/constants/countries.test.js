import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import * as runtime from '#lib/paraglide/runtime.js';
import { COUNTRIES, getCountryName, sortedCountries } from '#lib/constants/countries.js';

describe('countries in English', () => {
  it('keep the backend names', () => {
    expect(getCountryName('AX')).toBe('Aland Islands');
    expect(COUNTRIES[0]).toEqual({ code: 'GB', name: 'United Kingdom' });
  });

  it('sort by name', () => {
    const names = sortedCountries().map((c) => c.name);
    expect(names[0]).toBe('Afghanistan');
    expect(names).toHaveLength(COUNTRIES.length);
  });
});

describe('countries in Russian', () => {
  /** @type {typeof runtime.getLocale} */
  let original;
  beforeEach(() => {
    original = runtime.getLocale;
    runtime.overwriteGetLocale(() => 'ru');
  });
  afterEach(() => runtime.overwriteGetLocale(original));

  it('read the region name from Intl', () => {
    expect(getCountryName('DE')).toBe('Германия');
    expect(COUNTRIES.find((c) => c.code === 'GB')?.name).toBe('Великобритания');
  });

  it('sort by the Russian name and return plain objects', () => {
    const list = sortedCountries();
    expect(list[0].name).toBe('Австралия');
    expect(Object.getOwnPropertyDescriptor(list[0], 'name')?.get).toBeUndefined();
  });
});
