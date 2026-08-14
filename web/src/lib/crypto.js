// SecretNotes cryptography for the web client.
//
// This is the JS counterpart of the Dart `CryptoService`, implementing the
// contract in /PROTOCOL.md. It MUST stay byte-for-byte compatible with the
// mobile app — the parity suite (test/parity.test.js) proves it against the
// shared fixture test/fixtures/protocol_vectors.json.
//
// Everything is WebCrypto-native except Argon2id, which comes from hash-wasm.

import { argon2id } from 'hash-wasm';
import { utf8, concat, toB64 } from './bytes.js';

// --- Constants (must match Dart CryptoService) -----------------------------
export const KDF = Object.freeze({
  memoryKiB: 32768, // 32 MiB
  iterations: 3,
  lanes: 4, // parallelism
  keyLength: 32,
});

const WRAP_INFO = 'secretnotes:wrap:v1';
const AUTH_INFO = 'secretnotes:auth:v1';
const GCM_NONCE_LEN = 12;
const GCM_TAG_BITS = 128;

const subtle = globalThis.crypto.subtle;

export function randomBytes(n) {
  return globalThis.crypto.getRandomValues(new Uint8Array(n));
}

export const generateSalt = () => randomBytes(16);
export const generateDek = () => randomBytes(KDF.keyLength);

// --- Argon2id --------------------------------------------------------------

/**
 * Derive the 32-byte master key from the password. `params` mirrors the
 * account's stored kdf_params ({m,t,p}); defaults match {@link KDF}.
 */
export async function deriveMasterKey(password, salt, params = {}) {
  const memorySize = params.m ?? KDF.memoryKiB;
  const iterations = params.t ?? KDF.iterations;
  const parallelism = params.p ?? KDF.lanes;
  return argon2id({
    password: utf8(password),
    salt,
    parallelism,
    iterations,
    memorySize, // KiB — matches Dart's `memory` and hash-wasm's unit
    hashLength: KDF.keyLength,
    outputType: 'binary',
    // hash-wasm defaults to Argon2 version 0x13 (19), matching Dart.
  });
}

// --- HKDF-SHA256 -----------------------------------------------------------

/**
 * HKDF-SHA256 expansion. IMPORTANT: salt is EMPTY here (not the KDF salt) —
 * Dart passes a null salt which RFC 5869 defines as HashLen zero bytes; a
 * zero-length WebCrypto salt reduces to the same all-zero HMAC key.
 */
export async function hkdf(ikm, info, length = KDF.keyLength) {
  const key = await subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
  const bits = await subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: utf8(info) },
    key,
    length * 8,
  );
  return new Uint8Array(bits);
}

export const wrapKey = (masterKey) => hkdf(masterKey, WRAP_INFO);
export const authKey = (masterKey) => hkdf(masterKey, AUTH_INFO);

// --- AES-256-GCM (blob layout: nonce ‖ ciphertext ‖ tag) -------------------

async function importGcmKey(key) {
  return subtle.importKey('raw', key, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

export async function gcmEncrypt(key, plaintext) {
  const nonce = randomBytes(GCM_NONCE_LEN);
  const k = await importGcmKey(key);
  const ct = new Uint8Array(
    await subtle.encrypt({ name: 'AES-GCM', iv: nonce, tagLength: GCM_TAG_BITS }, k, plaintext),
  );
  return concat(nonce, ct); // WebCrypto appends the tag to `ct`
}

export async function gcmDecrypt(key, blob) {
  if (blob.length < GCM_NONCE_LEN + 16) throw new Error('ciphertext too short');
  const nonce = blob.subarray(0, GCM_NONCE_LEN);
  const ct = blob.subarray(GCM_NONCE_LEN); // includes the 16-byte tag
  const k = await importGcmKey(key);
  const pt = await subtle.decrypt({ name: 'AES-GCM', iv: nonce, tagLength: GCM_TAG_BITS }, k, ct);
  return new Uint8Array(pt);
}

// --- DEK wrapping ----------------------------------------------------------

export const wrapDek = (wrapKeyBytes, dek) => gcmEncrypt(wrapKeyBytes, dek);
export const unwrapDek = (wrapKeyBytes, wrappedDek) => gcmDecrypt(wrapKeyBytes, wrappedDek);

// --- Server auth-hash (parity/debug only; the client never sends this) -----

export async function authHash(salt, authKeyBytes) {
  const digest = new Uint8Array(await subtle.digest('SHA-256', concat(salt, authKeyBytes)));
  return toB64(digest);
}
