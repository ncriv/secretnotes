// Sync/merge logic: the pure conflict decision (port of Dart's sync_merge_test)
// and the Vault flow driven against an in-memory fake server that mirrors the
// Python server's seq/base_rev semantics — real encryption, no network.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { generateDek } from '../src/lib/crypto.js';
import { decryptNote } from '../src/lib/codec.js';
import { decideRemote, Vault } from '../src/lib/session.js';

// --- decideRemote truth table ---------------------------------------------

const local = (rev, dirty) => ({ rev, dirty, deleted: false, note: {} });
const remote = (rev, deleted = false) => ({ rev, deleted, blob: new Uint8Array(0) });

test('decideRemote: insert when no local record', () => {
  assert.equal(decideRemote(null, remote(5)), 'insert');
});
test('decideRemote: clean local + newer remote → overwrite', () => {
  assert.equal(decideRemote(local(3, false), remote(5)), 'overwrite');
});
test('decideRemote: clean local, remote not newer → ignore', () => {
  assert.equal(decideRemote(local(5, false), remote(5)), 'ignore');
});
test('decideRemote: dirty local, remote not ahead → ignore', () => {
  assert.equal(decideRemote(local(5, true), remote(5)), 'ignore');
});
test('decideRemote: dirty local + newer remote → keepBoth', () => {
  assert.equal(decideRemote(local(3, true), remote(5)), 'keepBoth');
});

// --- Fake server (in-memory port of the Python server contract) ------------

class FakeServer {
  constructor() {
    this.seq = 0;
    this.notes = new Map(); // id -> {blob, rev, deleted, updatedAt}
  }
  // Matches SyncClient.changes(token, since)
  async changes(_token, since = 0) {
    const changes = [...this.notes.entries()]
      .filter(([, n]) => n.rev > since)
      .sort((a, b) => a[1].rev - b[1].rev)
      .map(([id, n]) => ({ id, blob: n.blob, rev: n.rev, deleted: n.deleted, updatedAt: n.updatedAt }));
    return { cursor: this.seq, changes };
  }
  // Matches SyncClient.push(token, changes)
  async push(_token, changes) {
    const results = [];
    for (const c of changes) {
      const cur = this.notes.get(c.id);
      if (cur && cur.rev !== (c.baseRev ?? 0)) {
        results.push({ id: c.id, status: 'conflict', rev: cur.rev, server: { id: c.id, ...cur } });
        continue;
      }
      this.seq += 1;
      this.notes.set(c.id, {
        blob: c.blob ?? new Uint8Array(0),
        rev: this.seq,
        deleted: !!c.deleted,
        updatedAt: c.updatedAt ?? 0,
      });
      results.push({ id: c.id, status: 'ok', rev: this.seq });
    }
    return { cursor: this.seq, results };
  }
}

const mkNote = (id, title, updatedAt) => ({
  id,
  title,
  contentJson: `[{"insert":"${title}\\n"}]`,
  colorIndex: 0,
  createdAt: 1700000000000,
  updatedAt,
});

test('Vault: save then pull is idempotent', async () => {
  const server = new FakeServer();
  const dek = generateDek();
  const vault = new Vault({ client: server, token: 't', dek, username: 'a' });

  assert.equal(await vault.save(mkNote('n1', 'Hello', 1000)), 'ok');
  assert.equal(vault.records.get('n1').rev, 1);
  await vault.pull(); // our own change comes back; must not duplicate
  assert.equal(vault.notes().length, 1);
});

test('Vault: adopts a newer remote for a clean note', async () => {
  const server = new FakeServer();
  const dek = generateDek();
  const a = new Vault({ client: server, token: 't', dek, username: 'a' });
  await a.save(mkNote('n1', 'v1', 1000));

  // A second device (shares the DEK) updates n1.
  const b = new Vault({ client: server, token: 't', dek, username: 'a' });
  await b.pull();
  await b.save({ ...mkNote('n1', 'v2', 2000) });

  const notes = await a.pull();
  assert.equal(notes.length, 1);
  assert.equal(notes[0].title, 'v2');
  assert.equal(a.records.get('n1').rev, 2);
});

test('Vault: keeps both when a dirty local meets a newer remote', async () => {
  const server = new FakeServer();
  const dek = generateDek();
  const a = new Vault({ client: server, token: 't', dek, username: 'a' });
  await a.save(mkNote('n1', 'base', 1000));

  // Simulate an un-pushed local edit (offline): mutate the record to dirty.
  a.records.set('n1', {
    note: mkNote('n1', 'my local edit', 1500),
    rev: 1,
    dirty: true,
    deleted: false,
  });

  // Another device advances n1 on the server.
  const b = new Vault({ client: server, token: 't', dek, username: 'a' });
  await b.pull();
  await b.save({ ...mkNote('n1', 'their edit', 2000) });

  await a.pull();
  const titles = a.notes().map((n) => n.title).sort();
  // Remote adopted for n1; local edit preserved as a conflicted copy.
  assert.deepEqual(titles, ['my local edit (conflicted copy)', 'their edit']);
});

test('Vault: a note pushed by web decrypts back through the same DEK', async () => {
  const server = new FakeServer();
  const dek = generateDek();
  const vault = new Vault({ client: server, token: 't', dek, username: 'a' });
  await vault.save(mkNote('n1', 'roundtrip', 1000));

  // Read the raw stored blob and decrypt it independently.
  const stored = server.notes.get('n1').blob;
  const note = await decryptNote(dek, stored);
  assert.equal(note.title, 'roundtrip');
});
