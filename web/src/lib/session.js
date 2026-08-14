// High-level client orchestration: the username+password login flow and an
// in-memory, remote-only note vault with pull/save/delete + conflict handling.
// See /PROTOCOL.md §6. The mobile app persists a local encrypted vault; the web
// client deliberately keeps the DEK and notes in memory only.

import { deriveMasterKey, authKey, wrapKey, unwrapDek } from './crypto.js';
import { encryptNote, decryptNote } from './codec.js';
import { fromB64 } from './bytes.js';

/**
 * What to do with a local note when the server reports a change for it.
 * Pure port of Dart's `decideRemote` — kept side-effect-free for testing.
 * @returns {'insert'|'overwrite'|'keepBoth'|'ignore'}
 */
export function decideRemote(local, remote) {
  if (!local) return 'insert';
  if (!local.dirty) {
    return remote.rev <= local.rev ? 'ignore' : 'overwrite';
  }
  // Local has un-pushed edits.
  if (remote.rev <= local.rev) return 'ignore';
  return 'keepBoth';
}

/** Derive the login/envelope keys from a password + the account's KDF material. */
export async function deriveKeys(password, kdfSaltB64, kdfParams) {
  const masterKey = await deriveMasterKey(password, fromB64(kdfSaltB64), kdfParams);
  return {
    masterKey,
    authKey: await authKey(masterKey),
    wrapKey: await wrapKey(masterKey),
  };
}

/**
 * Log in and open a vault. Runs the full §6 flow:
 * prelogin → Argon2id → authKey → login → unwrap DEK.
 */
export async function login(client, username, password) {
  const { kdfSaltB64, kdfParamsJson } = await client.prelogin(username);
  const kdfParams = JSON.parse(kdfParamsJson);
  const keys = await deriveKeys(password, kdfSaltB64, kdfParams);
  const { token, wrappedDekB64 } = await client.login(username, keys.authKey);
  const dek = await unwrapDek(keys.wrapKey, fromB64(wrappedDekB64));
  return new Vault({ client, token, dek, username });
}

/** In-memory note store synced to the server. */
export class Vault {
  constructor({ client, token, dek, username }) {
    this.client = client;
    this.token = token;
    this.dek = dek;
    this.username = username;
    /** @type {Map<string, {note:object, rev:number, dirty:boolean, deleted:boolean}>} */
    this.records = new Map();
    this.cursor = 0;
  }

  /** All live (non-deleted) notes, newest-updated first. */
  notes() {
    return [...this.records.values()]
      .filter((r) => !r.deleted)
      .map((r) => r.note)
      .sort((a, b) => b.updatedAt - a.updatedAt);
  }

  /** Pull remote changes since the last cursor and merge them in. */
  async pull() {
    const { cursor, changes } = await this.client.changes(this.token, this.cursor);
    for (const remote of changes) {
      const local = this.records.get(remote.id);
      const action = decideRemote(local, remote);
      if (action === 'ignore') continue;
      if (action === 'keepBoth' && local && !local.deleted) {
        // Preserve the un-pushed local edit as a fresh, conflicted note.
        const copy = { ...local.note, id: crypto.randomUUID(), updatedAt: local.note.updatedAt };
        copy.title = conflictTitle(copy.title);
        this.records.set(copy.id, { note: copy, rev: 0, dirty: true, deleted: false });
      }
      if (remote.deleted) {
        this.records.set(remote.id, { note: null, rev: remote.rev, dirty: false, deleted: true });
      } else {
        const note = await decryptNote(this.dek, remote.blob);
        this.records.set(remote.id, { note, rev: remote.rev, dirty: false, deleted: false });
      }
    }
    this.cursor = cursor;
    return this.notes();
  }

  /** Create or update a note, encrypt it, and push. Handles a conflict by re-pulling. */
  async save(note) {
    const existing = this.records.get(note.id);
    const baseRev = existing?.rev ?? 0;
    this.records.set(note.id, { note, rev: baseRev, dirty: true, deleted: false });

    const blob = await encryptNote(this.dek, note);
    const { results } = await this.client.push(this.token, [
      { id: note.id, blob, baseRev, deleted: false, updatedAt: note.updatedAt },
    ]);
    return this._applyPushResult(results[0], note);
  }

  /** Tombstone a note (empty blob) and push the deletion. */
  async remove(id) {
    const existing = this.records.get(id);
    const baseRev = existing?.rev ?? 0;
    const updatedAt = Date.now();
    const { results } = await this.client.push(this.token, [
      { id, blob: null, baseRev, deleted: true, updatedAt },
    ]);
    const res = results[0];
    if (res.status === 'ok') {
      this.records.set(id, { note: null, rev: res.rev, dirty: false, deleted: true });
    } else {
      await this.pull();
    }
    return res.status;
  }

  async _applyPushResult(res, note) {
    if (res.status === 'ok') {
      this.records.set(note.id, { note, rev: res.rev, dirty: false, deleted: false });
      if (res.rev > this.cursor) this.cursor = res.rev;
      return 'ok';
    }
    // Conflict: the local edit stays dirty; pulling reconciles per §6 (keepBoth).
    await this.pull();
    return 'conflict';
  }
}

function conflictTitle(title) {
  return title ? `${title} (conflicted copy)` : '(conflicted copy)';
}
