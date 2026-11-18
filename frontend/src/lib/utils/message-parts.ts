/**
 * Styling part of a translated sentence (a count in bold, a path in `<code>`)
 * without splitting the sentence into fragments: pass `slot('name')` as the
 * placeholder's value, then render the result of `messageParts`, where each
 * `key` part marks where that styled value goes. The word order stays the
 * locale's.
 */

const MARK = '';

export const slot = (key: string) => `${MARK}${key}${MARK}`;

/** @param text a message rendered with `slot()` values */
export function messageParts(text: string): { text: string; key?: string }[] {
  return text
    .split(new RegExp(`${MARK}(\\w+)${MARK}`))
    .map((piece, i) => (i % 2 ? { text: '', key: piece } : { text: piece }));
}
