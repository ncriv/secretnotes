<script>
  import { notes, username, saveNote, deleteNote, newNote, logout } from '../lib/store.js';
  import { plainText } from '../lib/text.js';
  import LockMark from './LockMark.svelte';
  import SyncPill from './SyncPill.svelte';
  import NoteCard from './NoteCard.svelte';
  import Editor from './Editor.svelte';

  let query = '';
  let open = null; // note being edited, or null

  $: q = query.trim().toLowerCase();
  $: filtered = q
    ? $notes.filter(
        (n) =>
          (n.title || '').toLowerCase().includes(q) ||
          plainText(n.contentJson).toLowerCase().includes(q),
      )
    : $notes;

  function create() {
    open = newNote();
  }
  function onSave(e) {
    saveNote(e.detail);
  }
  function onDelete(e) {
    deleteNote(e.detail);
    open = null;
  }
</script>

<header class="bar">
  <div class="brand">
    <span class="mark"><LockMark size={26} stroke={3} /></span>
    <span class="word">SecretNotes</span>
  </div>

  <div class="search">
    <svg viewBox="0 0 24 24" width="17" height="17" aria-hidden="true">
      <circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="2" />
      <path d="M20 20l-3.2-3.2" stroke="currentColor" stroke-width="2" stroke-linecap="round" />
    </svg>
    <input
      type="search"
      placeholder="Search your notes"
      aria-label="Search your notes"
      bind:value={query}
    />
  </div>

  <div class="actions">
    <SyncPill />
    <button class="btn btn-primary new" on:click={create}>
      <span class="plus">+</span> New note
    </button>
    <button class="btn btn-ghost" on:click={logout} title={`Signed in as ${$username}`}>
      Lock
    </button>
  </div>
</header>

<main class="board">
  {#if $notes.length === 0}
    <div class="empty">
      <span class="empty-mark"><LockMark size={40} stroke={2.4} /></span>
      <h2>Your desk is clear</h2>
      <p>Write your first note. It’s encrypted here before it’s ever synced.</p>
      <button class="btn btn-primary" on:click={create}><span class="plus">+</span> New note</button>
    </div>
  {:else if filtered.length === 0}
    <div class="empty">
      <h2>Nothing matches “{query}”</h2>
      <p>Search looks inside your notes — try another word.</p>
    </div>
  {:else}
    <section class="grid" aria-label="Notes">
      {#each filtered as note, i (note.id)}
        <div class="cell">
          <NoteCard {note} index={i} on:click={() => (open = note)} />
        </div>
      {/each}
    </section>
  {/if}
</main>

{#if open}
  <Editor note={open} on:save={onSave} on:delete={onDelete} on:close={() => (open = null)} />
{/if}

<style>
  .bar {
    position: sticky;
    top: 0;
    z-index: 20;
    display: flex;
    align-items: center;
    gap: 1rem;
    padding: 0.85rem clamp(1rem, 4vw, 2.4rem);
    background: color-mix(in srgb, var(--paper) 82%, transparent);
    backdrop-filter: blur(10px);
    border-bottom: 1px solid var(--line);
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 0.55rem;
  }
  .mark {
    color: var(--accent);
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    background: var(--sheet);
    border: 1px solid var(--line);
    border-radius: 11px;
  }
  .word {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 1.08rem;
    letter-spacing: -0.02em;
  }

  .search {
    flex: 1;
    max-width: 460px;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: var(--sheet-2);
    border: 1px solid var(--line-strong);
    border-radius: 999px;
    padding: 0 0.95rem;
    color: var(--ink-faint);
    transition: border-color 0.15s ease, background 0.15s ease;
  }
  .search:focus-within {
    border-color: var(--accent);
    background: var(--sheet);
  }
  .search input {
    flex: 1;
    border: none;
    outline: none;
    background: transparent;
    padding: 0.55rem 0;
    color: var(--ink);
  }
  .search input::placeholder {
    color: var(--ink-faint);
  }

  .actions {
    display: flex;
    align-items: center;
    gap: 0.6rem;
  }
  .new {
    padding: 0.55rem 1rem;
  }
  .plus {
    font-size: 1.15em;
    line-height: 0;
    font-weight: 400;
  }

  .board {
    max-width: var(--maxw);
    margin: 0 auto;
    padding: clamp(1.2rem, 3vw, 2.2rem) clamp(1rem, 4vw, 2.4rem) 4rem;
  }
  .grid {
    columns: 260px;
    column-gap: 1.1rem;
  }
  .cell {
    break-inside: avoid;
    margin-bottom: 1.1rem;
  }

  .empty {
    text-align: center;
    max-width: 30rem;
    margin: clamp(3rem, 12vh, 7rem) auto 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.7rem;
  }
  .empty-mark {
    color: var(--accent);
    display: grid;
    place-items: center;
    width: 76px;
    height: 76px;
    background: var(--sheet);
    border: 1px solid var(--line);
    border-radius: 20px;
    box-shadow: var(--shadow-sm);
    margin-bottom: 0.5rem;
  }
  .empty h2 {
    font-size: 1.5rem;
  }
  .empty p {
    color: var(--ink-soft);
    margin: 0 0 0.6rem;
  }

  @media (max-width: 720px) {
    .bar {
      flex-wrap: wrap;
    }
    .search {
      order: 3;
      max-width: none;
      width: 100%;
    }
    .word {
      display: none;
    }
  }
</style>
