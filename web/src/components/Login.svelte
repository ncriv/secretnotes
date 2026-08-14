<script>
  import { doLogin, serverUrl } from '../lib/store.js';
  import { SyncError } from '../lib/api.js';
  import LockMark from './LockMark.svelte';

  let username = '';
  let password = '';
  let busy = false;
  let error = '';
  let showServer = false;

  function messageFor(e) {
    if (e instanceof SyncError) {
      if (e.status === 401) return "That username and password don't match.";
      if (e.status === 404) return 'No account with that username.';
      if (e.status === 0 || e.status === undefined) return 'Can’t reach the server. Check the address and try again.';
      return e.message || 'Something went wrong. Try again.';
    }
    return 'Can’t reach the server. Check the address and try again.';
  }

  async function submit() {
    if (busy || !username.trim() || !password) return;
    busy = true;
    error = '';
    try {
      await doLogin(username, password);
    } catch (e) {
      error = messageFor(e);
      password = '';
    } finally {
      busy = false;
    }
  }
</script>

<main class="wrap">
  <div class="card">
    <section class="brand">
      <div class="mark"><LockMark size={44} stroke={2.6} /></div>
      <h1>SecretNotes</h1>
      <p class="tag">Only you hold the key.</p>
      <p class="blurb">
        Your notes are encrypted on this device before they ever leave it. The
        server keeps the ciphertext in sync across your devices — and can read
        none of it.
      </p>
    </section>

    <section class="panel">
      <form on:submit|preventDefault={submit} novalidate>
        <h2>Sign in</h2>

        <label class="field">
          <span>Username</span>
          <input
            class="input"
            type="text"
            autocomplete="username"
            autocapitalize="none"
            spellcheck="false"
            bind:value={username}
            disabled={busy}
          />
        </label>

        <label class="field">
          <span>Password</span>
          <input
            class="input"
            type="password"
            autocomplete="current-password"
            bind:value={password}
            disabled={busy}
          />
        </label>

        {#if error}
          <p class="error" role="alert">{error}</p>
        {/if}

        <button class="btn btn-primary unlock" type="submit" disabled={busy}>
          {#if busy}Unlocking…{:else}Unlock{/if}
        </button>

        <details bind:open={showServer} class="server">
          <summary>Server</summary>
          <label class="field">
            <span>Sync server address</span>
            <input
              class="input"
              type="url"
              inputmode="url"
              autocapitalize="none"
              spellcheck="false"
              bind:value={$serverUrl}
              disabled={busy}
            />
          </label>
        </details>

        <p class="foot">New accounts are created by your server’s admin.</p>
      </form>
    </section>
  </div>
</main>

<style>
  .wrap {
    min-height: 100vh;
    display: grid;
    place-items: center;
    padding: 1.5rem;
    /* a soft, warm board with a faint violet glow — quiet, not busy */
    background:
      radial-gradient(120% 90% at 15% 0%, color-mix(in srgb, var(--accent) 7%, var(--paper)), transparent 55%),
      radial-gradient(90% 80% at 100% 100%, color-mix(in srgb, var(--accent) 5%, var(--paper)), transparent 50%),
      var(--paper);
  }

  .card {
    width: min(940px, 100%);
    display: grid;
    grid-template-columns: 1.05fr 1fr;
    background: var(--sheet);
    border: 1px solid var(--line);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-lg);
    overflow: hidden;
  }

  .brand {
    padding: 3rem 2.6rem;
    background:
      linear-gradient(160deg, color-mix(in srgb, var(--accent) 10%, var(--sheet-2)), var(--sheet-2));
    border-right: 1px solid var(--line);
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .mark {
    color: var(--accent);
    width: 76px;
    height: 76px;
    display: grid;
    place-items: center;
    background: var(--sheet);
    border: 1px solid var(--line);
    border-radius: 20px;
    box-shadow: var(--shadow-sm);
    margin-bottom: 1.5rem;
  }
  .brand h1 {
    font-size: 2.1rem;
    letter-spacing: -0.03em;
  }
  .tag {
    font-family: var(--font-display);
    font-weight: 600;
    color: var(--accent-ink);
    margin: 0.5rem 0 1.1rem;
    font-size: 1.05rem;
  }
  .blurb {
    color: var(--ink-soft);
    font-size: 0.95rem;
    line-height: 1.6;
    margin: 0;
    max-width: 34ch;
  }

  .panel {
    padding: 3rem 2.6rem;
    display: flex;
    align-items: center;
  }
  form {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 1.05rem;
  }
  form h2 {
    font-size: 1.35rem;
    margin-bottom: 0.2rem;
  }
  .error {
    margin: -0.2rem 0 0;
    color: var(--danger);
    font-size: 0.9rem;
    font-weight: 500;
  }
  .unlock {
    margin-top: 0.2rem;
    width: 100%;
    padding: 0.8rem;
    font-size: 1.02rem;
  }
  .server {
    margin-top: 0.1rem;
    border-top: 1px solid var(--line);
    padding-top: 0.9rem;
  }
  .server summary {
    font-family: var(--font-display);
    font-size: 0.82rem;
    font-weight: 600;
    color: var(--ink-soft);
    cursor: pointer;
    list-style: none;
  }
  .server summary::-webkit-details-marker {
    display: none;
  }
  .server summary::before {
    content: '▸';
    display: inline-block;
    margin-right: 0.4rem;
    transition: transform 0.15s ease;
  }
  .server[open] summary::before {
    transform: rotate(90deg);
  }
  .server .field {
    margin-top: 0.8rem;
  }
  .foot {
    margin: 0;
    font-size: 0.82rem;
    color: var(--ink-faint);
  }

  @media (max-width: 720px) {
    .card {
      grid-template-columns: 1fr;
    }
    .brand {
      border-right: none;
      border-bottom: 1px solid var(--line);
      padding: 2.2rem 1.8rem;
    }
    .mark {
      width: 60px;
      height: 60px;
      margin-bottom: 1.1rem;
    }
    .panel {
      padding: 2rem 1.8rem 2.4rem;
    }
  }
</style>
