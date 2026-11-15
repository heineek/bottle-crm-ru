/**
 * Styling part of a translated sentence (a count in bold, a path in `<code>`)
 * without splitting the sentence into fragments: pass `slot('name')` as the
 * placeholder's value, then render the result of `messageParts`, where each
 * `key` part marks where that styled value goes. The word order stays the
 * locale's.
 */

const MARK = '';

/** @param {string} key */
export const slot = (key) => `${MARK}${key}${MARK}`;

/**
 * @param {string} text a message rendered with `slot()` values
 * @returns {{ text: string, key?: string }[]}
 */
export function messageParts(text) {
  return text
    .split(new RegExp(`${MARK}(\\w+)${MARK}`))
    .map((piece, i) => (i % 2 ? { text: '', key: piece } : { text: piece }));
}
