// End-to-end check against the REAL Python sync server: spins it up, registers
// an account with web-derived keys, logs in through the actual HTTP client,
// pushes a note, and pulls it back on a second session. Proves api.js +
// session.js + crypto interoperate with server/secretnotes_server.py over HTTP.
//
//   node e2e/live-server.mjs
//
// Not part of `npm test` (needs Python + a spawned server); run it on demand.

import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import assert from 'node:assert/strict';

import { KDF, generateSalt, generateDek, deriveMasterKey, wrapKey, authKey, wrapDek } from '../src/lib/crypto.js';
import { toB64, bytesEqual } from '../src/lib/bytes.js';
import { SyncClient } from '../src/lib/api.js';
import { login } from '../src/lib/session.js';

const PORT = 8799;
const BASE = `http://127.0.0.1:${PORT}`;
const ADMIN = 'test-admin-token';
const USER = 'alice';
const PASS = 'correct horse battery staple';

const dir = mkdtempSync(join(tmpdir(), 'sn-e2e-'));
const db = join(dir, 'notes.db');

const server = spawn(
  'python3',
  ['../server/secretnotes_server.py', '--db', db, '--port', String(PORT), '--admin-token', ADMIN],
  { stdio: 'inherit' },
);

async function waitForServer() {
  for (let i = 0; i < 50; i++) {
    try {
      const r = await fetch(`${BASE}/healthz`);
      if (r.ok) return;
    } catch {
      /* not up yet */
    }
    await new Promise((res) => setTimeout(res, 100));
  }
  throw new Error('server did not start');
}

function cleanup() {
  server.kill('SIGINT');
  try {
    rmSync(dir, { recursive: true, force: true });
  } catch {
    /* ignore */
  }
}

try {
  await waitForServer();
  const client = new SyncClient(BASE);

  // --- provision an account with web-derived envelope (what an admin tool does)
  const salt = generateSalt();
  const master = await deriveMasterKey(PASS, salt);
  const dek = generateDek();
  const wrapped = await wrapDek(await wrapKey(master), dek);
  await client.register({
    adminToken: ADMIN,
    username: USER,
    authKey: await authKey(master),
    kdfSaltB64: toB64(salt),
    kdfParamsJson: JSON.stringify({ m: KDF.memoryKiB, t: KDF.iterations, p: KDF.lanes }),
    wrappedDekB64: toB64(wrapped),
  });
  console.log('✓ registered account');

  // --- log in over HTTP; the unwrapped DEK must match what we generated
  const vault = await login(client, USER, PASS);
  assert.ok(bytesEqual(vault.dek, dek), 'unwrapped DEK matches the generated DEK');
  console.log('✓ login recovered the DEK');

  // --- push a note
  const now = 1700000000000;
  const note = {
    id: crypto.randomUUID(),
    title: 'Buy milk',
    contentJson: '[{"insert":"2% and oat\\n"}]',
    colorIndex: 4,
    createdAt: now,
    updatedAt: now,
  };
  assert.equal(await vault.save(note), 'ok');
  console.log('✓ pushed a note');

  // --- a fresh session pulls and decrypts it
  const vault2 = await login(client, USER, PASS);
  const pulled = await vault2.pull();
  assert.equal(pulled.length, 1);
  assert.equal(pulled[0].title, 'Buy milk');
  assert.equal(pulled[0].contentJson, note.contentJson);
  console.log('✓ second session pulled and decrypted the note');

  // --- wrong password is rejected by the server verifier
  await assert.rejects(() => login(client, USER, 'wrong password'), /401|invalid/i);
  console.log('✓ wrong password rejected');

  console.log('\nALL E2E CHECKS PASSED');
  cleanup();
  process.exit(0);
} catch (e) {
  console.error('\nE2E FAILED:', e);
  cleanup();
  process.exit(1);
}
