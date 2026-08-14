// Note payload codec — JS counterpart of Dart's NoteCodec + the length-hiding
// padding in CryptoService. See /PROTOCOL.md §4.

import { utf8, fromUtf8 } from './bytes.js';
import { gcmEncrypt, gcmDecrypt } from './crypto.js';

const PAD_HEADER = 4; // uint32-be plaintext length
const MIN_BUCKET = 256;

/** Smallest power-of-two bucket ≥ 256 that fits (4 + plaintextLen). */
export function paddedSize(plaintextLen) {
  const needed = PAD_HEADER + plaintextLen;
  let bucket = MIN_BUCKET;
  while (bucket < needed) bucket <<= 1;
  return bucket;
}

/** Pad to a size bucket, then AES-256-GCM under the DEK. */
export async function encryptPayload(dek, plaintext) {
  const padded = new Uint8Array(paddedSize(plaintext.length));
  new DataView(padded.buffer).setUint32(0, plaintext.length, false); // big-endian
  padded.set(plaintext, PAD_HEADER);
  // Remaining bytes are already zero (Uint8Array initializer).
  return gcmEncrypt(dek, padded);
}

/** Reverse of {@link encryptPayload}: decrypt, read the length header, unpad. */
export async function decryptPayload(dek, blob) {
  const padded = await gcmDecrypt(dek, blob);
  if (padded.length < PAD_HEADER) throw new Error('payload too short');
  const len = new DataView(padded.buffer, padded.byteOffset, PAD_HEADER).getUint32(0, false);
  if (PAD_HEADER + len > padded.length) throw new Error('corrupt padding');
  return padded.subarray(PAD_HEADER, PAD_HEADER + len);
}

// --- Note <-> map <-> bytes ------------------------------------------------
//
// A note is { id, title, contentJson, colorIndex, createdAt, updatedAt } where
// timestamps are epoch-ms numbers. On the wire the map keys are the short forms
// below (matching Dart). Key ORDER is irrelevant to interop: every client
// parses by key, so we never depend on byte-identical JSON across languages.

export function noteToMap(note) {
  return {
    id: note.id,
    title: note.title,
    content: note.contentJson,
    color: note.colorIndex,
    created: note.createdAt,
    updated: note.updatedAt,
  };
}

export function mapToNote(map) {
  return {
    id: map.id,
    title: map.title ?? '',
    contentJson: map.content ?? '[{"insert":"\\n"}]',
    colorIndex: map.color ?? 0,
    createdAt: map.created,
    updatedAt: map.updated,
  };
}

export const encodeNote = (note) => utf8(JSON.stringify(noteToMap(note)));
export const decodeNote = (bytes) => mapToNote(JSON.parse(fromUtf8(bytes)));

/** Encrypt a note to a sync blob. */
export const encryptNote = (dek, note) => encryptPayload(dek, encodeNote(note));

/** Decrypt a sync blob back to a note. */
export async function decryptNote(dek, blob) {
  return decodeNote(await decryptPayload(dek, blob));
}
