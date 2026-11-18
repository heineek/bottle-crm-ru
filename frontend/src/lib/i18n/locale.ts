/**
 * Which locale a page renders in. The same order as the API's
 * `backend/common/locale.py`, so a page and the errors it shows agree:
 *
 *   1. the user's own choice (`language` claim in the JWT),
 *   2. the browser's Accept-Language,
 *   3. the org's default (`org_settings.default_language` claim),
 *   4. the base locale.
 *
 * Pure on purpose: hooks.server.ts feeds it the claims and the header, and
 * vitest can run it without SvelteKit.
 */

/**
 * `code` as one of `supported`, or undefined. A regional tag falls back to its
 * base language, so `ru-RU` matches `ru`.
 */
export function supportedLocale(code: unknown, supported: readonly string[]): string | undefined {
  if (typeof code !== 'string' || !code.trim()) return undefined;
  const normalized = code.trim().toLowerCase().replace(/_/g, '-');
  if (supported.includes(normalized)) return normalized;
  const base = normalized.split('-')[0];
  return supported.includes(base) ? base : undefined;
}

/** The best supported locale in an Accept-Language value, by quality. */
export function localeFromHeader(
  header: string | null | undefined,
  supported: readonly string[]
): string | undefined {
  if (!header) return undefined;
  const ranked = header
    .split(',')
    .map((part, index) => {
      const [tag, ...params] = part.trim().split(';');
      const q = params.map((p) => p.trim()).find((p) => p.startsWith('q='));
      const quality = q ? Number(q.slice(2)) : 1;
      return { tag: tag.trim(), quality: Number.isFinite(quality) ? quality : 0, index };
    })
    .filter((entry) => entry.tag && entry.tag !== '*' && entry.quality > 0)
    .sort((a, b) => b.quality - a.quality || a.index - b.index);
  for (const { tag } of ranked) {
    const found = supportedLocale(tag, supported);
    if (found) return found;
  }
  return undefined;
}

export function resolveLocale(
  {
    userLanguage,
    acceptLanguage,
    orgLanguage
  }: { userLanguage?: unknown; acceptLanguage?: string | null; orgLanguage?: unknown },
  supported: readonly string[],
  base: string
): string {
  return (
    supportedLocale(userLanguage, supported) ??
    localeFromHeader(acceptLanguage, supported) ??
    supportedLocale(orgLanguage, supported) ??
    base
  );
}

// Scripts written right to left. A locale whose language is listed here gets
// `dir="rtl"` on <html>; layout then follows from logical CSS (`ms-*`, `pe-*`,
// `margin-inline-start`), see docs/localization/right-to-left.md.
const RTL_LANGUAGES = new Set(['ar', 'ckb', 'dv', 'fa', 'he', 'ps', 'sd', 'ug', 'ur', 'yi']);

/** The text direction of a UI locale, for the `dir` attribute on <html>. */
export function textDirection(locale: string): 'ltr' | 'rtl' {
  const language = locale.toLowerCase().split(/[-_]/)[0];
  return RTL_LANGUAGES.has(language) ? 'rtl' : 'ltr';
}

/**
 * The `Intl` locale for a UI locale. English keeps the tags `format.js` always
 * used (`en-US` numbers, `en-GB` day-first dates), so English output is unchanged.
 */
export function intlLocale(locale: string, kind: 'number' | 'date'): string {
  if (locale === 'en') return kind === 'date' ? 'en-GB' : 'en-US';
  if (locale === 'ru') return 'ru-RU';
  return locale;
}
