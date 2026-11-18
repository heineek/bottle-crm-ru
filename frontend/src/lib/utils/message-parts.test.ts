import { describe, expect, it } from 'vitest';
import { messageParts, slot } from './message-parts.js';

describe('messageParts', () => {
  it('marks each slot in the order the message puts it', () => {
    expect(messageParts(`Showing ${slot('shown')} of ${slot('total')}`)).toEqual([
      { text: 'Showing ' },
      { text: '', key: 'shown' },
      { text: ' of ' },
      { text: '', key: 'total' },
      { text: '' }
    ]);
  });

  it('returns a message without slots as one text part', () => {
    expect(messageParts('Nothing unread')).toEqual([{ text: 'Nothing unread' }]);
  });
});
