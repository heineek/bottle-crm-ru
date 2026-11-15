import { describe, expect, it } from 'vitest';
import {
  intlLocale,
  localeFromHeader,
  resolveLocale,
  supportedLocale,
  textDirection
} from './locale.js';

const LOCALES = ['en', 'ru'];

describe('supportedLocale', () => {
  it('falls back from a regional tag to its base language', () => {
    expect(supportedLocale('ru-RU', LOCALES)).toBe('ru');
    expect(supportedLocale('RU_ru', LOCALES)).toBe('ru');
  });

  it('refuses what is not supported', () => {
    expect(supportedLocale('de', LOCALES)).toBeUndefined();
    expect(supportedLocale('', LOCALES)).toBeUndefined();
    expect(supportedLocale(null, LOCALES)).toBeUndefined();
    expect(supportedLocale(42, LOCALES)).toBeUndefined();
  });
});

describe('localeFromHeader', () => {
  it('takes the best supported language by quality', () => {
    expect(localeFromHeader('de-DE,ru;q=0.8,en;q=0.5', LOCALES)).toBe('ru');
    expect(localeFromHeader('en;q=0.2, ru;q=0.9', LOCALES)).toBe('ru');
  });

  it('keeps header order between equal qualities', () => {
    expect(localeFromHeader('en, ru', LOCALES)).toBe('en');
  });

  it('ignores wildcards, zero quality and unsupported languages', () => {
    expect(localeFromHeader('*', LOCALES)).toBeUndefined();
    expect(localeFromHeader('ru;q=0', LOCALES)).toBeUndefined();
    expect(localeFromHeader('de, fr', LOCALES)).toBeUndefined();
    expect(localeFromHeader(undefined, LOCALES)).toBeUndefined();
  });
});

describe('resolveLocale', () => {
  it('prefers the user, then the header, then the org, then the base', () => {
    expect(
      resolveLocale({ userLanguage: 'ru', acceptLanguage: 'en', orgLanguage: 'en' }, LOCALES, 'en')
    ).toBe('ru');
    expect(
      resolveLocale({ userLanguage: '', acceptLanguage: 'ru', orgLanguage: 'en' }, LOCALES, 'en')
    ).toBe('ru');
    expect(
      resolveLocale({ userLanguage: '', acceptLanguage: 'de', orgLanguage: 'ru' }, LOCALES, 'en')
    ).toBe('ru');
    expect(
      resolveLocale({ userLanguage: '', acceptLanguage: 'en', orgLanguage: 'ru' }, LOCALES, 'en')
    ).toBe('en');
    expect(resolveLocale({}, LOCALES, 'en')).toBe('en');
  });

  it('falls through a stored language that is no longer supported', () => {
    expect(resolveLocale({ userLanguage: 'xx', orgLanguage: 'xx' }, LOCALES, 'en')).toBe('en');
  });
});

describe('intlLocale', () => {
  it('keeps the English tags format.js always used', () => {
    expect(intlLocale('en', 'number')).toBe('en-US');
    expect(intlLocale('en', 'date')).toBe('en-GB');
    expect(intlLocale('ru', 'date')).toBe('ru-RU');
  });
});

describe('textDirection', () => {
  it('is ltr for the shipped languages', () => {
    expect(textDirection('en')).toBe('ltr');
    expect(textDirection('ru')).toBe('ltr');
  });

  it('is rtl for right-to-left scripts, with or without a region', () => {
    expect(textDirection('fa')).toBe('rtl');
    expect(textDirection('ar-EG')).toBe('rtl');
    expect(textDirection('he_IL')).toBe('rtl');
  });
});
