import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { strategy } from '#lib/paraglide/runtime.js';

/**
 * Paraglide is compiled twice: by the vite plugin (dev, build) and by
 * `pnpm i18n` (check, test). Each takes its own strategy, and a runtime
 * compiled with the CLI default renders every page in English whatever
 * hooks.server.ts decided. The tests run on the CLI's output, so pin it here.
 */
const EXPECTED = ['custom-crm', 'cookie', 'baseLocale'];

describe('paraglide strategy', () => {
  it('is what hooks.server.ts relies on', () => {
    expect([...strategy]).toEqual(EXPECTED);
  });

  it('is the same in vite.config.js', () => {
    const config = readFileSync(new URL('../../../vite.config.js', import.meta.url), 'utf8');
    expect(config).toContain(
      `strategy: ${JSON.stringify(EXPECTED).replace(/"/g, "'").replace(/,/g, ', ')}`
    );
  });
});
