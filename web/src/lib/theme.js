// Note color identity. Preserves the meaning of the mobile app's `colorIndex`
// (10 hues, same order as lib/utils/color_utils.dart) but renders friendlier,
// softer tints. Each card derives its background with CSS color-mix(hue into
// sheet), so tints adapt to light/dark on their own — we only store the hue.

export const NOTE_HUES = [
  { name: 'Indigo', hue: '#6c77d6' },
  { name: 'Teal', hue: '#2fa795' },
  { name: 'Coral', hue: '#e8635a' },
  { name: 'Purple', hue: '#a667ce' },
  { name: 'Blue', hue: '#4e97e6' },
  { name: 'Amber', hue: '#e0912f' },
  { name: 'Green', hue: '#5faf64' },
  { name: 'Pink', hue: '#e56aa0' },
  { name: 'Clay', hue: '#a47c6d' },
  { name: 'Slate', hue: '#7a93a1' },
];

export const noteHue = (colorIndex) => NOTE_HUES[((colorIndex % 10) + 10) % 10].hue;
export const noteHueName = (colorIndex) => NOTE_HUES[((colorIndex % 10) + 10) % 10].name;
