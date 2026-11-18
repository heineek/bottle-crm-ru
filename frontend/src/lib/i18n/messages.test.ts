import { readdirSync, readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

/**
 * messages/<module>/en.json (and messages/en.json) is the source. Every locale
 * in project.inlang must have a file beside it with the same keys and the same
 * {placeholders}: a missing key silently falls back to English, and a renamed
 * placeholder renders literally. Keys are global in Paraglide, so two modules
 * may not define the same one. No empty messages, and no em dash in any locale.
 */
const ROOT = new URL('../../../messages/', import.meta.url);
const SETTINGS = new URL('../../../project.inlang/settings.json', import.meta.url);
const { baseLocale, locales } = JSON.parse(readFileSync(SETTINGS, 'utf8')) as {
  baseLocale: string;
  locales: string[];
};
const SOURCE = `${baseLocale}.json`;

type Variant = { declarations?: string[]; match?: Record<string, string> };

const read = (url: URL): Record<string, unknown> => {
  const { $schema, ...messages } = JSON.parse(readFileSync(url, 'utf8'));
  void $schema;
  return messages;
};
/**
 * The inputs a message takes: its {placeholders} and `input` declarations,
 * less the locals it derives itself. A locale may make a plain message a
 * plural where the source needs none, so compare inputs only.
 */
const placeholders = (value: unknown) => {
  const text = JSON.stringify(value);
  const locals = new Set([...text.matchAll(/local (\w+) =/g)].map((match) => match[1]));
  const names = [
    ...[...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1]),
    ...[...text.matchAll(/input (\w+)/g)].map((match) => match[1])
  ];
  return [...new Set(names.filter((name) => !locals.has(name)))].sort();
};

/** Every text a message can render: the string itself, or each variant's match. */
const texts = (value: unknown): unknown[] =>
  Array.isArray(value)
    ? (value as Variant[]).flatMap((variant) => Object.values(variant.match ?? {}))
    : [value];

const dirs = [
  ROOT,
  ...readdirSync(ROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => new URL(`${entry.name}/`, ROOT))
];

describe('message catalogs', () => {
  it('defines each key in one module only', () => {
    const owner: Record<string, string> = {};
    const clashes: string[] = [];
    for (const dir of dirs) {
      for (const key of Object.keys(read(new URL(SOURCE, dir)))) {
        if (owner[key]) clashes.push(`${key}: ${owner[key]} and ${dir.pathname}`);
        owner[key] = dir.pathname;
      }
    }
    expect(clashes).toEqual([]);
  });

  for (const dir of dirs) {
    const source = read(new URL(SOURCE, dir));
    const files = readdirSync(dir).filter((f) => f.endsWith('.json'));
    const name = dir.pathname.split('/messages/')[1] || '(common)';

    it(`${name} has a file for every configured locale and no other`, () => {
      expect(files.sort()).toEqual(locales.map((locale) => `${locale}.json`).sort());
    });

    for (const locale of locales) {
      const file = `${locale}.json`;
      describe(`${name}/${file}`, () => {
        const target = locale === baseLocale ? source : read(new URL(file, dir));

        if (locale !== baseLocale) {
          it('has exactly the source keys', () => {
            expect(Object.keys(target).sort()).toEqual(Object.keys(source).sort());
          });

          it('keeps every placeholder', () => {
            for (const [key, value] of Object.entries(source)) {
              expect(placeholders(target[key]), key).toEqual(placeholders(value));
            }
          });
        }

        it('gives every plural all the forms its language needs', () => {
          const needed = new Intl.PluralRules(locale)
            .resolvedOptions()
            .pluralCategories.filter((c) => c !== 'other');
          for (const [key, value] of Object.entries(target)) {
            if (!Array.isArray(value)) continue;
            for (const variant of value as Variant[]) {
              const plurals = (variant.declarations ?? [])
                .filter((d) => d.endsWith(': plural'))
                .map((d) => d.split('=')[0].replace('local', '').trim());
              for (const selector of plurals) {
                const forms = new Set(
                  Object.keys(variant.match ?? {})
                    .flatMap((k) => k.split(', '))
                    .filter((part) => part.startsWith(`${selector}=`))
                    .map((part) => part.split('=')[1])
                );
                if (forms.has('*') || (forms.size === 1 && forms.has('other'))) continue;
                expect(
                  needed.filter((c) => !forms.has(c)),
                  `${key}: ${selector}`
                ).toEqual([]);
              }
            }
          }
        });

        it('has no empty message and no em dash', () => {
          for (const [key, value] of Object.entries(target)) {
            for (const text of texts(value)) {
              expect(typeof text === 'string' && text.trim() !== '', key).toBe(true);
              expect(text, key).not.toMatch(/\u2014/);
            }
          }
        });
      });
    }
  }
});
