<script>
  import { onMount, onDestroy, createEventDispatcher, tick } from 'svelte';
  import Quill from 'quill';
  import 'quill/dist/quill.snow.css';
  import { NOTE_HUES, noteHue } from '../lib/theme.js';

  export let note;

  const dispatch = createEventDispatcher();
  const draft = { ...note };

  let editorEl;
  let titleEl;
  let quill;
  let ready = false;
  let dirty = false;
  let confirmingDelete = false;
  let saveTimer = null;

  const toolbar = [
    [{ header: [1, 2, false] }],
    ['bold', 'italic', 'underline', 'strike'],
    [{ list: 'ordered' }, { list: 'bullet' }],
    ['blockquote', 'code-block', 'link'],
    ['clean'],
  ];

  function collect() {
    const ops = quill ? quill.getContents().ops : JSON.parse(draft.contentJson);
    return { ...draft, contentJson: JSON.stringify(ops) };
  }

  function markDirty() {
    dirty = true;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(flush, 1200); // gentle autosave
  }

  function flush() {
    clearTimeout(saveTimer);
    if (!dirty) return;
    dirty = false;
    dispatch('save', collect());
  }

  function close() {
    flush();
    dispatch('close');
  }

  function chooseColor(i) {
    if (draft.colorIndex === i) return;
    draft.colorIndex = i;
    markDirty();
  }

  function requestDelete() {
    if (!confirmingDelete) {
      confirmingDelete = true;
      return;
    }
    clearTimeout(saveTimer);
    dispatch('delete', draft.id);
  }

  function onKey(e) {
    if (e.key === 'Escape') {
      e.preventDefault();
      close();
    } else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's') {
      e.preventDefault();
      flush();
    }
  }

  onMount(async () => {
    quill = new Quill(editorEl, {
      theme: 'snow',
      placeholder: 'Start writing…',
      modules: { toolbar },
    });
    const Delta = Quill.import('delta');
    let ops;
    try {
      ops = JSON.parse(draft.contentJson);
    } catch {
      ops = [{ insert: '\n' }];
    }
    quill.setContents(new Delta(ops), 'silent');
    quill.on('text-change', (_d, _o, source) => {
      if (ready && source === 'user') markDirty();
    });
    await tick();
    ready = true;
    // Focus the title on a fresh/untitled note, else the body.
    if (!draft.title) titleEl?.focus();
    else quill.focus();
    document.body.style.overflow = 'hidden';
  });

  onDestroy(() => {
    clearTimeout(saveTimer);
    document.body.style.overflow = '';
  });
</script>

<svelte:window on:keydown={onKey} />

<!-- svelte-ignore a11y-no-static-element-interactions -->
<div class="backdrop" role="presentation" on:mousedown={close}>
  <div
    class="sheet"
    role="dialog"
    aria-label="Note editor"
    style="--hue:{noteHue(draft.colorIndex)}"
    on:mousedown|stopPropagation
  >
    <div class="topline">
      <span class="tint" aria-hidden="true"></span>
      <div class="spacer"></div>
      <button class="btn btn-quiet" on:click={close}>Done</button>
    </div>

    <input
      class="title-input"
      placeholder="Title"
      bind:this={titleEl}
      bind:value={draft.title}
      on:input={markDirty}
    />

    <div class="quill-host">
      <div bind:this={editorEl}></div>
    </div>

    <div class="tools">
      <div class="swatches" role="group" aria-label="Note color">
        {#each NOTE_HUES as c, i}
          <button
            class="swatch"
            class:active={draft.colorIndex === i}
            style="--s:{c.hue}"
            title={c.name}
            aria-label={c.name}
            aria-pressed={draft.colorIndex === i}
            on:click={() => chooseColor(i)}
          ></button>
        {/each}
      </div>

      <button
        class="btn del"
        class:confirm={confirmingDelete}
        on:click={requestDelete}
        on:blur={() => (confirmingDelete = false)}
      >
        {confirmingDelete ? 'Delete note?' : 'Delete'}
      </button>
    </div>
  </div>
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: color-mix(in srgb, var(--ink) 42%, transparent);
    backdrop-filter: blur(3px);
    display: grid;
    place-items: center;
    padding: 1.5rem;
    z-index: 40;
    animation: fade 0.16s ease both;
  }
  .sheet {
    width: min(720px, 100%);
    max-height: 90vh;
    display: flex;
    flex-direction: column;
    background: var(--sheet);
    border: 1px solid var(--line);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg);
    animation: pop 0.22s cubic-bezier(0.2, 0.7, 0.3, 1) both;
    overflow: hidden;
  }
  .topline {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    padding: 0.75rem 0.9rem 0.75rem 1.4rem;
    border-bottom: 1px solid var(--line);
  }
  .tint {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: var(--hue);
  }
  .spacer {
    flex: 1;
  }
  .title-input {
    border: none;
    outline: none;
    background: transparent;
    font-family: var(--font-display);
    font-size: 1.55rem;
    font-weight: 650;
    letter-spacing: -0.02em;
    color: var(--ink);
    padding: 1.2rem 1.6rem 0.4rem;
  }
  .title-input::placeholder {
    color: var(--ink-faint);
  }
  .quill-host {
    flex: 1;
    overflow: auto;
    padding: 0 0.6rem;
  }
  .tools {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
    padding: 0.8rem 1.4rem;
    border-top: 1px solid var(--line);
    background: var(--sheet-2);
    flex-wrap: wrap;
  }
  .swatches {
    display: flex;
    gap: 0.4rem;
    flex-wrap: wrap;
  }
  .swatch {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    border: 2px solid transparent;
    background: var(--s);
    padding: 0;
    transition: transform 0.1s ease, box-shadow 0.1s ease;
  }
  .swatch:hover {
    transform: scale(1.12);
  }
  .swatch.active {
    box-shadow: 0 0 0 2px var(--sheet), 0 0 0 4px var(--s);
  }
  .del {
    color: var(--ink-soft);
    background: transparent;
    border: 1px solid var(--line-strong);
    border-radius: 999px;
    padding: 0.5rem 1rem;
    font-weight: 600;
  }
  .del:hover {
    color: var(--danger);
    border-color: color-mix(in srgb, var(--danger) 50%, var(--line));
  }
  .del.confirm {
    color: #fff;
    background: var(--danger);
    border-color: var(--danger);
  }

  @keyframes fade {
    from {
      opacity: 0;
    }
  }
  @keyframes pop {
    from {
      opacity: 0;
      transform: translateY(12px) scale(0.98);
    }
  }

  /* --- Quill, restyled to match the sheet ------------------------------- */
  .quill-host :global(.ql-toolbar.ql-snow) {
    position: sticky;
    top: 0;
    z-index: 1;
    border: none;
    border-bottom: 1px solid var(--line);
    background: var(--sheet);
    padding: 0.5rem 0.9rem;
    font-family: var(--font-body);
  }
  .quill-host :global(.ql-container.ql-snow) {
    border: none;
    font-family: var(--font-body);
    font-size: 1.02rem;
  }
  .quill-host :global(.ql-editor) {
    padding: 1.1rem 1rem 2rem;
    color: var(--ink);
    line-height: 1.65;
    min-height: 40vh;
  }
  .quill-host :global(.ql-editor.ql-blank::before) {
    color: var(--ink-faint);
    font-style: normal;
    left: 1rem;
  }
  .quill-host :global(.ql-editor blockquote) {
    border-left: 3px solid var(--hue);
    color: var(--ink-soft);
    padding-left: 1rem;
    margin-left: 0;
  }
  .quill-host :global(.ql-editor a) {
    color: var(--accent-ink);
  }
  /* icon + active states in the accent, not Quill's default blue */
  .quill-host :global(.ql-snow .ql-stroke) {
    stroke: var(--ink-soft);
  }
  .quill-host :global(.ql-snow .ql-fill) {
    fill: var(--ink-soft);
  }
  .quill-host :global(.ql-snow.ql-toolbar button:hover .ql-stroke),
  .quill-host :global(.ql-snow .ql-toolbar button:hover .ql-stroke),
  .quill-host :global(.ql-snow.ql-toolbar button.ql-active .ql-stroke) {
    stroke: var(--accent);
  }
  .quill-host :global(.ql-snow.ql-toolbar button:hover .ql-fill),
  .quill-host :global(.ql-snow.ql-toolbar button.ql-active .ql-fill) {
    fill: var(--accent);
  }
  .quill-host :global(.ql-snow.ql-toolbar button.ql-active),
  .quill-host :global(.ql-snow .ql-picker-label:hover) {
    color: var(--accent);
  }
  .quill-host :global(.ql-picker) {
    color: var(--ink-soft);
  }

  @media (max-width: 640px) {
    .backdrop {
      padding: 0;
    }
    .sheet {
      width: 100%;
      max-height: 100vh;
      height: 100vh;
      border-radius: 0;
      border: none;
    }
  }
</style>
