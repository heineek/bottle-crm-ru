import { describe, expect, it } from 'vitest';
import { parentKinds, taskKindLabel, taskPriorityLabel, taskStatusLabel } from './labels.js';

describe('task labels', () => {
  it('keeps the English codes as labels', () => {
    expect(taskStatusLabel('In Progress')).toBe('In Progress');
    expect(taskPriorityLabel('Medium')).toBe('Medium');
    expect(taskKindLabel('deal')).toBe('deal');
    expect(parentKinds().map((k) => k.label)).toEqual([
      'Nothing',
      'An account',
      'A deal',
      'A ticket',
      'A lead',
      'A project'
    ]);
  });

  it('shows an unknown code as it came', () => {
    expect(taskStatusLabel('Archived')).toBe('Archived');
    expect(taskKindLabel('constructor')).toBe('constructor');
  });
});
