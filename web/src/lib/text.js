// Plain-text view of a note's Quill Delta (contentJson), for previews & search.

export function plainText(contentJson) {
  try {
    const ops = JSON.parse(contentJson);
    if (!Array.isArray(ops)) return '';
    return ops
      .map((op) => (typeof op.insert === 'string' ? op.insert : ' '))
      .join('')
      .replace(/\n{2,}/g, '\n')
      .trim();
  } catch {
    return '';
  }
}

export function relativeTime(ms) {
  const diff = Date.now() - ms;
  const sec = Math.round(diff / 1000);
  if (sec < 45) return 'just now';
  const min = Math.round(sec / 60);
  if (min < 60) return `${min} min ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr} hr ago`;
  const day = Math.round(hr / 24);
  if (day < 7) return `${day} day${day > 1 ? 's' : ''} ago`;
  return new Date(ms).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}
