import { afterEach, describe, expect, it, vi } from 'vitest';

const apiRequest = vi.fn();
vi.mock('#lib/api-helpers.js', () => ({ apiRequest: (...a) => apiRequest(...a) }));

const { logTicketTime, stopTimer } = await import('./timesheet.js');
const { getLocale, overwriteGetLocale } = await import('#lib/paraglide/runtime.js');
const baseGetLocale = getLocale;

const event = /** @type {any} */ ({ cookies: { get: () => undefined } });

describe('timesheet input errors', () => {
  afterEach(() => overwriteGetLocale(baseGetLocale));

  it('rejects out-of-range minutes in English', async () => {
    await expect(logTicketTime(event, 't1', { minutes: 0, description: 'x' })).rejects.toThrow(
      'Minutes must be a whole number between 1 and 1440.'
    );
  });

  it('rejects out-of-range minutes in Russian', async () => {
    overwriteGetLocale(() => 'ru');
    await expect(logTicketTime(event, 't1', { minutes: 2000, description: 'x' })).rejects.toThrow(
      'Минуты должны быть целым числом от 1 до 1440.'
    );
  });

  it('asks which entry to stop in Russian', async () => {
    overwriteGetLocale(() => 'ru');
    await expect(stopTimer(event, '')).rejects.toThrow(
      'Какая запись времени? Идентификатор записи не передан.'
    );
    expect(apiRequest).not.toHaveBeenCalled();
  });
});
