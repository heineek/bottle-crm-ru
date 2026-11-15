import { describe, it, expect, vi, beforeEach } from 'vitest';

const apiRequest = vi.fn();
vi.mock('#lib/api-helpers.js', () => ({ apiRequest: (...a) => apiRequest(...a) }));

const { getTask } = await import('#lib/server/v2/tasks.js');

const event = /** @type {any} */ ({ cookies: { get: () => 'token' } });

/**
 * `task_obj.contacts` is `ContactLinkSerializer`: `id`, `first_name`,
 * `last_name` and `email`. This read `primary_email`, which the API has never
 * sent, so every contact's email came out blank.
 */
describe('task contacts', () => {
  beforeEach(() => {
    apiRequest.mockReset();
  });

  it('reads the email the API sends', async () => {
    apiRequest.mockResolvedValue({
      task_obj: {
        id: 't1',
        title: 'Call',
        contacts: [{ id: 'c1', first_name: 'Pat', last_name: 'Doe', email: 'pat@example.com' }]
      }
    });

    const { contacts } = await getTask(event, 't1');

    expect(contacts).toEqual([{ id: 'c1', name: 'Pat Doe', email: 'pat@example.com' }]);
  });

  it('labels a nameless contact by that email', async () => {
    apiRequest.mockResolvedValue({
      task_obj: {
        id: 't1',
        title: 'Call',
        contacts: [{ id: 'c1', first_name: '', last_name: '', email: 'pat@example.com' }]
      }
    });

    const { contacts } = await getTask(event, 't1');

    expect(contacts[0].name).toBe('pat@example.com');
  });
});

describe('task activity in Russian', () => {
  beforeEach(() => apiRequest.mockReset());

  it('labels the creation event and an unnamed file in the request locale', async () => {
    const { getLocale, overwriteGetLocale } = await import('#lib/paraglide/runtime.js');
    const base = getLocale;
    overwriteGetLocale(() => 'ru');
    try {
      apiRequest.mockResolvedValue({
        task_obj: { id: 't1', title: 'Call', created_at: '2026-01-01T00:00:00Z' },
        attachments: [{ id: 'a1', file_name: '', created_at: '2026-01-02T00:00:00Z' }]
      });
      const { activity } = await getTask(event, 't1');
      expect(activity.map((/** @type {any} */ e) => e.body)).toEqual([
        'Вложение',
        'Задача создана'
      ]);
    } finally {
      overwriteGetLocale(base);
    }
  });
});
