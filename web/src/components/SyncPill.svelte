<script>
  import { status } from '../lib/store.js';

  const labels = {
    idle: 'Ready',
    unlocking: 'Unlocking…',
    syncing: 'Syncing…',
    synced: 'Encrypted & synced',
    error: 'Sync problem',
  };

  $: state = $status.state;
  $: label = labels[state] ?? 'Ready';
  // What the server can see is nothing — say so, warmly, on hover.
  $: title =
    state === 'error'
      ? $status.error || 'Could not reach the server'
      : 'Your notes are encrypted on this device. The server only ever stores ciphertext.';
</script>

<span class="pill" class:err={state === 'error'} class:busy={state === 'syncing' || state === 'unlocking'} {title}>
  <span class="dot"></span>
  {label}
</span>

<style>
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    font-family: var(--font-display);
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--ink-soft);
    background: var(--sheet-2);
    border: 1px solid var(--line);
    border-radius: 999px;
    padding: 0.32rem 0.7rem 0.32rem 0.6rem;
    white-space: nowrap;
  }
  .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--good);
    box-shadow: 0 0 0 3px color-mix(in srgb, var(--good) 22%, transparent);
  }
  .busy .dot {
    background: var(--accent);
    box-shadow: 0 0 0 3px color-mix(in srgb, var(--accent) 22%, transparent);
    animation: pulse 1.1s ease-in-out infinite;
  }
  .err {
    color: var(--danger);
    border-color: color-mix(in srgb, var(--danger) 40%, var(--line));
  }
  .err .dot {
    background: var(--danger);
    box-shadow: 0 0 0 3px color-mix(in srgb, var(--danger) 22%, transparent);
    animation: none;
  }
  @keyframes pulse {
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.35;
    }
  }
</style>
