// Reactive glue between the framework-agnostic logic layer (session.js / Vault)
// and the Svelte UI: holds the open vault, the decrypted notes, sync status,
// and the server-URL config; runs background pulls.

import { writable, get } from 'svelte/store';
import { SyncClient } from './api.js';
import { login as sessionLogin } from './session.js';

const LS_URL = 'secretnotes.serverUrl';
const readUrl = () => {
  try {
    return localStorage.getItem(LS_URL) || location.origin;
  } catch {
    return location.origin;
  }
};

export const serverUrl = writable(readUrl());
serverUrl.subscribe((v) => {
  try {
    localStorage.setItem(LS_URL, v);
  } catch {
    /* ignore (private mode) */
  }
});

export const vault = writable(null);
export const notes = writable([]);
export const username = writable('');
/** state: 'idle' | 'unlocking' | 'syncing' | 'synced' | 'error' */
export const status = writable({ state: 'idle', at: null, error: null });

let pollTimer = null;

const refresh = () => {
  const v = get(vault);
  if (v) notes.set(v.notes());
};

export async function doLogin(name, password) {
  status.set({ state: 'unlocking', at: null, error: null });
  try {
    const client = new SyncClient(get(serverUrl));
    const v = await sessionLogin(client, name.trim(), password);
    vault.set(v);
    username.set(name.trim());
    await pull();
    startPolling();
  } catch (e) {
    status.set({ state: 'idle', at: null, error: null });
    throw e; // surfaced by the login form
  }
}

export async function pull() {
  const v = get(vault);
  if (!v) return;
  status.update((s) => ({ ...s, state: 'syncing' }));
  try {
    await v.pull();
    refresh();
    status.set({ state: 'synced', at: Date.now(), error: null });
  } catch (e) {
    status.set({ state: 'error', at: get(status).at, error: e.message });
  }
}

export async function saveNote(note) {
  const v = get(vault);
  if (!v) return;
  note.updatedAt = Date.now();
  status.update((s) => ({ ...s, state: 'syncing' }));
  try {
    await v.save(note);
    refresh();
    status.set({ state: 'synced', at: Date.now(), error: null });
  } catch (e) {
    status.set({ state: 'error', at: get(status).at, error: e.message });
    refresh(); // keep the optimistic local copy visible
  }
}

export async function deleteNote(id) {
  const v = get(vault);
  if (!v) return;
  status.update((s) => ({ ...s, state: 'syncing' }));
  try {
    await v.remove(id);
    refresh();
    status.set({ state: 'synced', at: Date.now(), error: null });
  } catch (e) {
    status.set({ state: 'error', at: get(status).at, error: e.message });
  }
}

export function newNote() {
  const now = Date.now();
  return {
    id: crypto.randomUUID(),
    title: '',
    contentJson: '[{"insert":"\\n"}]',
    colorIndex: get(notes).length % 10,
    createdAt: now,
    updatedAt: now,
  };
}

export function logout() {
  stopPolling();
  vault.set(null);
  notes.set([]);
  username.set('');
  status.set({ state: 'idle', at: null, error: null });
}

function startPolling() {
  stopPolling();
  pollTimer = setInterval(pull, 15000);
  window.addEventListener('focus', pull);
}
function stopPolling() {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = null;
  window.removeEventListener('focus', pull);
}
