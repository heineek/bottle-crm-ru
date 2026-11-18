import { describe, expect, it } from 'vitest';
import { messageParts, slot } from './message-parts.js';

describe('messageParts', () => {
  it('marks each slot in the order the message puts it', () => {
    expect(messageParts(`Показано ${slot('shown')} из ${slot('total')}`)).toEqual([
      { text: 'Показано ' },
      { text: '', key: 'shown' },
      { text: ' из ' },
      { text: '', key: 'total' },
      { text: '' }
    ]);
  });

  it('returns a message without slots as one text part', () => {
    expect(messageParts('Nothing unread')).toEqual([{ text: 'Nothing unread' }]);
  });
});
