import { afterEach, describe, expect, it } from 'vitest';
import { getLocale, overwriteGetLocale } from '#lib/paraglide/runtime.js';
import { parentKinds, taskKindLabel, taskPriorityLabel, taskStatusLabel } from './labels.js';

const base = getLocale;

describe('task labels', () => {
  afterEach(() => overwriteGetLocale(base));

  it('keeps the English codes as labels', () => {
    expect(taskStatusLabel('In Progress')).toBe('In Progress');
    expect(taskPriorityLabel('Medium')).toBe('Medium');
    expect(taskKindLabel('deal')).toBe('deal');
    expect(parentKinds().map((k) => k.label)).toEqual([
      'Nothing',
      'An account',
      'A deal',
      'A ticket',
      'A lead'
    ]);
  });

  it('translates in Russian, with a feminine status for a task', () => {
    overwriteGetLocale(() => 'ru');
    expect(taskStatusLabel('Completed')).toBe('Выполнена');
    expect(taskPriorityLabel('High')).toBe('Высокий');
    expect(taskKindLabel('ticket')).toBe('обращение');
  });

  it('shows an unknown code as it came', () => {
    overwriteGetLocale(() => 'ru');
    expect(taskStatusLabel('Archived')).toBe('Archived');
    expect(taskKindLabel('constructor')).toBe('constructor');
  });
});
