<script>
  import { noteHue } from '../lib/theme.js';
  import { plainText, relativeTime } from '../lib/text.js';

  export let note;
  export let index = 0;

  $: hue = noteHue(note.colorIndex);
  $: preview = plainText(note.contentJson);
  $: title = note.title?.trim() || (preview ? '' : 'Untitled');
</script>

<button
  class="card"
  style="--hue:{hue}; --i:{index}"
  on:click
  aria-label={`Open note: ${note.title?.trim() || 'untitled'}`}
>
  <span class="spine" aria-hidden="true"></span>
  <div class="body">
    {#if title}
      <h3 class="title">{title}</h3>
    {/if}
    {#if preview}
      <p class="preview">{preview}</p>
    {:else if !title}
      <p class="preview empty">Empty note</p>
    {/if}
  </div>
  <time class="meta">{relativeTime(note.updatedAt)}</time>
</button>

<style>
  .card {
    position: relative;
    display: flex;
    flex-direction: column;
    text-align: left;
    width: 100%;
    border: 1px solid color-mix(in srgb, var(--hue) 24%, var(--line));
    background: color-mix(in srgb, var(--hue) 12%, var(--sheet));
    border-radius: var(--radius);
    padding: 1rem 1.1rem 0.85rem 1.25rem;
    box-shadow: var(--shadow-sm);
    transition: transform 0.12s ease, box-shadow 0.15s ease, border-color 0.15s ease;
    overflow: hidden;
    /* staggered entrance */
    animation: rise 0.4s cubic-bezier(0.2, 0.7, 0.3, 1) both;
    animation-delay: calc(var(--i) * 28ms);
  }
  .card:hover {
    transform: translateY(-3px);
    box-shadow: var(--shadow-md);
    border-color: color-mix(in srgb, var(--hue) 45%, var(--line));
  }
  .spine {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 5px;
    background: var(--hue);
    opacity: 0.85;
  }
  .body {
    flex: 1;
    min-height: 3.2rem;
  }
  .title {
    font-size: 1.02rem;
    font-weight: 650;
    color: var(--ink);
    margin-bottom: 0.35rem;
    /* clamp to 2 lines */
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .preview {
    margin: 0;
    color: var(--ink-soft);
    font-size: 0.9rem;
    line-height: 1.5;
    white-space: pre-wrap;
    display: -webkit-box;
    -webkit-line-clamp: 6;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .preview.empty {
    font-style: italic;
    color: var(--ink-faint);
  }
  .meta {
    margin-top: 0.75rem;
    font-family: var(--font-display);
    font-size: 0.72rem;
    font-weight: 600;
    letter-spacing: 0.02em;
    color: color-mix(in srgb, var(--hue) 55%, var(--ink-faint));
  }
  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(8px);
    }
  }
</style>
