# Web client — design direction

**Thesis:** a calm, private writing desk. The server only ever sees ciphertext;
only you hold the key. Friendly and modern, never cold or spy-themed. Warmth
comes from paper, soft color, and type — not skeuomorphism.

**Palette — "warm paper & ink-violet"** (tokens in `src/app.css`)
- paper `#F6F4EF` (board) · sheet `#FFFFFF` (cards/editor) · ink `#201E1B`
- ink-soft `#6E675C` · line `#E7E2D8`
- accent ink-violet `#5A4FE4` (hover `#4A3FD0`), tint `#ECEAFB`
- Deliberately **not** the cream + serif + terracotta AI default, nor
  black + acid-green, nor broadsheet. Dark theme via `prefers-color-scheme`.

**Note colors:** honor the mobile `colorIndex` (10 hues, `src/lib/theme.js`) but
render as soft tints — each card derives its background with `color-mix(hue into
sheet)`, so it adapts to light/dark automatically.

**Type** (self-hosted, no third-party requests — a privacy app shouldn't phone home)
- Display / UI / brand: **Bricolage Grotesque** (characterful, friendly-modern)
- Body / notes / inputs: **Hanken Grotesk** (warm, highly legible)

**Signature:** a friendly **keyhole lock mark** (SVG, `LockMark.svelte`) — large
as the login hero, small in the top bar. One bold motif; everything else quiet.
Microcopy carries the privacy thesis warmly ("Only you hold the key"), and the
sync pill says plainly what the server can and can't see.

**Motion:** gentle only — card hover lift, editor sheet fade-up, staggered card
entrance. All gated behind `prefers-reduced-motion`.
