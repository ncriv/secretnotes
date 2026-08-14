// Cross-language crypto parity: proves the web client reproduces the Dart
// client byte-for-byte, by asserting against the SAME authoritative fixture the
// Dart suite uses (test/fixtures/protocol_vectors.json, generated from the real
// CryptoService). If this is green, a note encrypted on mobile decrypts on the
// web and vice-versa. Run: `npm test` (from web/).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { fromB64, fromUtf8, bytesEqual } from '../src/lib/bytes.js';
import {
  deriveMasterKey,
  wrapKey,
  authKey,
  authHash,
  unwrapDek,
  gcmDecrypt,
} from '../src/lib/crypto.js';
import { paddedSize, decryptPayload, decodeNote } from '../src/lib/codec.js';

const fixturePath = fileURLToPath(
  new URL('../../test/fixtures/protocol_vectors.json', import.meta.url),
);
const V = JSON.parse(readFileSync(fixturePath, 'utf8'));

const eqBytes = (actual, b64) =>
  assert.ok(bytesEqual(actual, fromB64(b64)), 'byte mismatch vs fixture');

// Derive once; several tests reuse it.
const d = V.derivation;
const masterKeyP = deriveMasterKey(d.password, fromB64(d.kdfSaltB64), d.kdfParams);

test('Argon2id master key matches the fixture', async () => {
  eqBytes(await masterKeyP, d.masterKeyB64);
});

test('HKDF wrap key matches the fixture', async () => {
  eqBytes(await wrapKey(await masterKeyP), d.wrapKeyB64);
});

test('HKDF auth key matches the fixture', async () => {
  eqBytes(await authKey(await masterKeyP), d.authKeyB64);
});

test('server auth-hash matches the fixture', async () => {
  const a = V.authHash;
  const hash = await authHash(fromB64(a.serverAuthSaltB64), await authKey(await masterKeyP));
  assert.equal(hash, a.authHashB64);
});

test('padding buckets match the fixture', () => {
  for (const c of V.padding) {
    assert.equal(paddedSize(c.plaintextLen), c.paddedSize, `paddedSize(${c.plaintextLen})`);
  }
});

test('wrapped DEK decrypts to the expected DEK', async () => {
  const w = V.wrappedDek;
  const dek = await unwrapDek(fromB64(d.wrapKeyB64), fromB64(w.wrappedDekB64));
  eqBytes(dek, w.dekB64);
});

test('raw GCM blob decrypts to the expected plaintext', async () => {
  const g = V.gcm;
  const pt = await gcmDecrypt(fromB64(g.keyB64), fromB64(g.blobB64));
  assert.equal(fromUtf8(pt), g.plaintextUtf8);
});

test('note blob decrypts and decodes to the expected map', async () => {
  const n = V.note;
  const dek = fromB64(n.dekB64);

  // Padded payload decrypts back to the exact codec bytes...
  const codecBytes = await decryptPayload(dek, fromB64(n.blobB64));
  eqBytes(codecBytes, n.codecBytesB64);

  // ...which decode to the note the fixture describes.
  const note = decodeNote(codecBytes);
  assert.equal(note.id, n.map.id);
  assert.equal(note.title, n.map.title);
  assert.equal(note.contentJson, n.map.content);
  assert.equal(note.colorIndex, n.map.color);
  assert.equal(note.createdAt, n.map.created);
  assert.equal(note.updatedAt, n.map.updated);
});
