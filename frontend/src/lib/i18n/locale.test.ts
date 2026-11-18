import { describe, expect, it } from 'vitest';
import {
  intlLocale,
  localeFromHeader,
  resolveLocale,
  supportedLocale,
  textDirection
} from './locale.js';

// A second locale so order and fallback are observable; it need not ship.
const LOCALES = ['en', 'fr'];

describe('supportedLocale', () => {
  it('falls back from a regional tag to its base language', () => {
    expect(supportedLocale('fr-CA', LOCALES)).toBe('fr');
    expect(supportedLocale('FR_fr', LOCALES)).toBe('fr');
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
    expect(localeFromHeader('de-DE,fr;q=0.8,en;q=0.5', LOCALES)).toBe('fr');
    expect(localeFromHeader('en;q=0.2, fr;q=0.9', LOCALES)).toBe('fr');
  });

  it('keeps header order between equal qualities', () => {
    expect(localeFromHeader('en, fr', LOCALES)).toBe('en');
  });

  it('ignores wildcards, zero quality and unsupported languages', () => {
    expect(localeFromHeader('*', LOCALES)).toBeUndefined();
    expect(localeFromHeader('fr;q=0', LOCALES)).toBeUndefined();
    expect(localeFromHeader('de, it', LOCALES)).toBeUndefined();
    expect(localeFromHeader(undefined, LOCALES)).toBeUndefined();
  });
});

describe('resolveLocale', () => {
  it('prefers the user, then the header, then the org, then the base', () => {
    expect(
      resolveLocale({ userLanguage: 'fr', acceptLanguage: 'en', orgLanguage: 'en' }, LOCALES, 'en')
    ).toBe('fr');
    expect(
      resolveLocale({ userLanguage: '', acceptLanguage: 'fr', orgLanguage: 'en' }, LOCALES, 'en')
    ).toBe('fr');
    expect(
      resolveLocale({ userLanguage: '', acceptLanguage: 'de', orgLanguage: 'fr' }, LOCALES, 'en')
    ).toBe('fr');
    expect(
      resolveLocale({ userLanguage: '', acceptLanguage: 'en', orgLanguage: 'fr' }, LOCALES, 'en')
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
    expect(intlLocale('fr', 'date')).toBe('fr');
  });
});

describe('textDirection', () => {
  it('is ltr for the shipped languages', () => {
    expect(textDirection('en')).toBe('ltr');
    expect(textDirection('fr')).toBe('ltr');
  });

  it('is rtl for right-to-left scripts, with or without a region', () => {
    expect(textDirection('fa')).toBe('rtl');
    expect(textDirection('ar-EG')).toBe('rtl');
    expect(textDirection('he_IL')).toBe('rtl');
  });
});
