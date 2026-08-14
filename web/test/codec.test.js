// Exercises the JS *encrypt* path (the parity suite only decrypts Dart blobs):
// notes and payloads must survive an encrypt→decrypt round trip locally.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { generateDek } from '../src/lib/crypto.js';
import {
  paddedSize,
  encryptPayload,
  decryptPayload,
  encryptNote,
  decryptNote,
} from '../src/lib/codec.js';
import { utf8 } from '../src/lib/bytes.js';

test('paddedSize buckets to powers of two ≥ 256', () => {
  assert.equal(paddedSize(0), 256);
  assert.equal(paddedSize(252), 256); // 4 + 252 = 256
  assert.equal(paddedSize(253), 512); // 4 + 253 = 257 → 512
  assert.equal(paddedSize(508), 512);
  assert.equal(paddedSize(1020), 1024);
  assert.equal(paddedSize(4096), 8192);
});

test('payload survives encrypt → decrypt for many sizes', async () => {
  const dek = generateDek();
  for (const len of [0, 1, 200, 252, 253, 1000, 5000]) {
    const plain = utf8('x'.repeat(len));
    const blob = await encryptPayload(dek, plain);
    // Ciphertext length leaks only the coarse bucket (+ nonce + tag).
    assert.equal(blob.length, 12 + paddedSize(len) + 16);
    const back = await decryptPayload(dek, blob);
    assert.deepEqual(back, plain);
  }
});

test('note survives encrypt → decrypt round trip', async () => {
  const dek = generateDek();
  const note = {
    id: 'abc-123',
    title: 'Grocery list',
    contentJson: '[{"insert":"milk\\neggs\\n"}]',
    colorIndex: 3,
    createdAt: 1700000000000,
    updatedAt: 1700000123000,
  };
  const restored = await decryptNote(dek, await encryptNote(dek, note));
  assert.deepEqual(restored, note);
});

test('wrong key fails authentication (tamper detection)', async () => {
  const dek = generateDek();
  const blob = await encryptPayload(dek, utf8('secret'));
  await assert.rejects(() => decryptPayload(generateDek(), blob));
});
