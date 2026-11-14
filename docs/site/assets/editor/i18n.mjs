// Exact message keys and numbered placeholders keep user-entered data untouched.
export function translator(messages = {}) {
  return (key, ...values) => {
    const tagged = Array.isArray(key);
    const source = tagged ? key.reduce((s, part, i) => s + (i ? `{${i-1}}` : '') + part, '') : key;
    const text = Object.hasOwn(messages, source) ? messages[source] : source;
    return tagged ? text.replace(/\{(\d+)\}/g, (_, index) => String(values[Number(index)])) : text;
  };
}
export const locale = globalThis.document?.documentElement.lang || 'en';
let messages = {};
if (locale !== 'en' && globalThis.document) {
  const response = await fetch(new URL('./messages.json?v=roads-1', import.meta.url));
  if (!response.ok) throw new Error('Unable to load language messages. Please reload.');
  messages = (await response.json())[locale] || {};
}
export const t = translator(messages);
