# SecretNotes Protocol & Crypto Spec

The contract every SecretNotes client must honour to interoperate with the sync
server and with each other's encrypted data. It exists because the crypto and
wire format currently live implicitly inside the Flutter/Dart client
(`lib/services/`); a second client (the planned web app) must reproduce them
**byte-for-byte** or users get locked out of their own notes.

> **Authoritative test vectors:** [`test/fixtures/protocol_vectors.json`](test/fixtures/protocol_vectors.json),
> generated from the real Dart `CryptoService` by
> [`tool/generate_test_vectors.dart`](tool/generate_test_vectors.dart)
> (`dart run tool/generate_test_vectors.dart`). Every implementation should
> assert against this file. The Dart side is pinned by
> `test/protocol_vectors_test.dart`; the web client should mirror it.

---

## 1. Threat model

The server is a **dumb end-to-end-encrypted blob store**. It never sees:

- the master password,
- the master key, wrap key, or DEK,
- any note plaintext.

It only ever holds ciphertext, sync metadata (ids, revisions, timestamps), the
KDF salt/params, the *wrapped* DEK, and an opaque login verifier. TLS is still
required in production (a reverse proxy) to protect tokens and metadata.

---

## 2. Key hierarchy (Bitwarden-style envelope)

```
password ──Argon2id(kdf_salt)──▶ masterKey (32 bytes, never leaves the client)
                                    │
              ┌─────────────────────┼──────────────────────┐
   HKDF(info:"secretnotes:wrap:v1")  HKDF(info:"secretnotes:auth:v1")
              │                       │
           wrapKey                 authKey ──▶ sent to server as the login secret
              │                             (base64) ; server stores only
      unwraps the DEK                        sha256(authSalt || authKey)
              │
              ▼
        DEK (random 32 bytes) ── AES-256-GCM ──▶ every note blob
```

The **DEK** is generated once per account, encrypts all notes, and is shared
across devices by storing it *wrapped* (GCM under `wrapKey`) on the server. A new
device/browser derives `wrapKey` from the password and unwraps it.

---

## 3. Primitives (exact parameters)

| Primitive        | Parameters |
|------------------|------------|
| **Argon2id**     | version `0x13` (19), memory **32768 KiB** (32 MiB), iterations **3**, lanes/parallelism **4**, output **32 bytes**. Password is UTF-8; salt is the 16 raw bytes of `kdf_salt`. |
| **HKDF**         | HKDF-SHA256, **salt = empty** (see trap below), `info` = the ASCII string, output **32 bytes**. `wrapKey` uses info `secretnotes:wrap:v1`; `authKey` uses `secretnotes:auth:v1`. |
| **AES-256-GCM**  | 12-byte random nonce, 128-bit tag. On-wire blob layout is **`nonce(12) ‖ ciphertext ‖ tag(16)`**. AAD is empty. |
| **Login verifier** | Server-side only: `base64(sha256(authSalt ‖ authKey))`, `authSalt` a fresh 16 server bytes. Clients never compute this. |

### Interop traps (this is why the vectors exist)

- **HKDF salt is empty, and is NOT `kdf_salt`.** The Dart client passes a `null`
  salt, which per RFC 5869 becomes `HashLen` zero bytes. In WebCrypto pass a
  zero-length `salt: new Uint8Array(0)` — it reduces to the same all-zero HMAC
  key. Feeding `kdf_salt` here will silently produce wrong keys.
- **`kdf_params` values are KiB and raw counts**, matching hash-wasm's
  `memorySize` (KiB) / `iterations` / `parallelism` directly.
- **GCM tag placement.** WebCrypto appends the tag to the ciphertext, which
  already matches `ciphertext ‖ tag`. Encrypt → prepend your 12-byte nonce.
  Decrypt → `iv = blob[0..12]`, ciphertext-with-tag = `blob[12..]`.

---

## 4. Note payload codec

A note's plaintext is JSON (UTF-8), then length-padded, then GCM-encrypted with
the DEK to produce the `blob` that syncs.

**4.1 JSON map** (`NoteCodec`):

```json
{
  "id": "<uuid>",
  "title": "<string>",
  "content": "<Quill Delta JSON string>",
  "color": 0,
  "created": 1700000000000,
  "updated": 1700000123000
}
```

`content` is a [Quill Delta](https://quilljs.com/docs/delta) document serialized
as a JSON *string* (note the nested escaping). The mobile app uses flutter_quill;
the web app can use **Quill.js**, whose native format is exactly this Delta — no
translation needed. `created`/`updated` are epoch-milliseconds.

**4.2 Length-hiding padding.** So ciphertext length leaks only a coarse bucket:

```
padded = uint32_be(plaintextLen)  ‖  plaintext  ‖  zero-fill
```

padded to the smallest power-of-two **bucket ≥ 256** that fits
`4 + plaintextLen`. (e.g. len ≤252 → 256, 253–508 → 512, 509–1020 → 1024,
4096 → 8192.)

**4.3** `blob = AES-256-GCM(DEK, padded)` = `nonce ‖ ct ‖ tag`.

Decrypt reverses it: GCM-decrypt, read the big-endian length header, slice out
that many bytes, `JSON.parse`.

A **tombstone** (deleted note) has an **empty blob** — no ciphertext at all.

---

## 5. HTTP API

Base path `/v1`. All bodies are JSON. Binary fields (`auth_key`, `blob`,
`wrapped_dek`) are **base64**. Authenticated calls send `Authorization: Bearer
<token>`. `kdf_salt`, `kdf_params`, and `wrapped_dek` are opaque strings the
server stores and echoes verbatim.

### `POST /v1/register`  — create an account (admin-gated)

```jsonc
// request
{ "admin_token": "...", "username": "alice",
  "auth_key": "<b64>", "kdf_salt": "<b64>",
  "kdf_params": "{\"m\":32768,\"t\":3,\"p\":4}", "wrapped_dek": "<b64>" }
// response 200
{ "token": "<bearer>" }
```

Errors: `403` bad admin token, `409` username taken, `400` missing field.
Registration is intentionally admin-only; the web app is primarily a **login**
client for accounts provisioned elsewhere.

### `GET /v1/prelogin?username=alice` — fetch KDF material before login

```jsonc
// response 200
{ "kdf_salt": "<b64>", "kdf_params": "{...}" }   // 404 if unknown
```

### `POST /v1/login` — authenticate, receive the wrapped DEK

```jsonc
// request
{ "username": "alice", "auth_key": "<b64>" }
// response 200
{ "token": "<bearer>", "wrapped_dek": "<b64>" }   // 401 on bad credentials
```

### `GET /v1/keys` — (auth) re-fetch envelope for the logged-in user

```jsonc
{ "kdf_salt": "<b64>", "kdf_params": "{...}", "wrapped_dek": "<b64>" }
```

### `GET /v1/changes?since=<cursor>` — (auth) pull the change feed

```jsonc
{ "cursor": 42,
  "changes": [
    { "id": "<uuid>", "blob": "<b64>", "rev": 41,
      "deleted": false, "updated_at": 1700000000000 }
  ] }
```

Returns every note with `seq > since`, ordered ascending, plus the account's
current `cursor`. `since=0` returns everything (full initial load).

### `POST /v1/push` — (auth) upload local changes

```jsonc
// request
{ "changes": [
    { "id": "<uuid>", "blob": "<b64>|null", "base_rev": 41,
      "deleted": false, "updated_at": 1700000500000 } ] }
// response 200
{ "cursor": 43,
  "results": [
    { "id": "<uuid>", "status": "ok", "rev": 43 },
    { "id": "<uuid2>", "status": "conflict", "rev": 40,
      "server": { "id": "...", "blob": "<b64>", "rev": 40,
                  "deleted": false, "updated_at": 1699999000000 } } ] }
```

`blob` is `null` for a tombstone (`deleted: true`). See §6 for `base_rev`.

Also: `GET /healthz` → `{ "ok": true }`.

---

## 6. Revisions, cursors & conflicts

- **`rev` / `seq` / `cursor` are one monotonic counter per account.** Each
  accepted write bumps the account counter and stamps the note's new `rev` with
  it. `cursor` is the account's latest value; clients pass the last cursor they
  saw as `since`.
- **`base_rev`** on push = the `rev` the client last observed for that note. The
  server accepts the write only if the stored `rev` still equals `base_rev`
  (optimistic concurrency); otherwise it returns `status: "conflict"` with its
  current `server` copy and makes **no change**.
- **Conflict resolution is the client's job.** The reference behaviour
  (`decideRemote` in `sync_service.dart`): a clean local note adopts a newer
  remote; a locally-edited note facing a newer remote **keeps both** — save the
  local edits as a new note (fresh id) and take the remote — so no edit is lost.

### Minimal remote-only web flow

1. `prelogin(username)` → `kdf_salt`, `kdf_params`.
2. Argon2id → `masterKey`; `authKey = HKDF(masterKey,"secretnotes:auth:v1")`.
3. `login(username, authKey)` → `token`, `wrapped_dek`.
4. `wrapKey = HKDF(masterKey,"secretnotes:wrap:v1")`; `DEK = GCM_decrypt(wrapKey, wrapped_dek)`.
5. `changes?since=0` → decrypt each `blob` with the DEK → render. Remember `cursor`.
6. On save: encrypt → `push` with `base_rev = note.rev`. On `ok`, store the new
   `rev`; on `conflict`, reconcile per §6 and retry.
7. Poll `changes?since=cursor` (or on focus) to stay live.

The web client is remote-only: the DEK/token live in memory (optionally
`sessionStorage`); there is no local encrypted vault to migrate.

---

## 7. WebCrypto + hash-wasm mapping (implementation note)

| Spec element | Browser API |
|---|---|
| Argon2id | [`hash-wasm`](https://github.com/Daninet/hash-wasm) `argon2id({ password, salt, parallelism:4, iterations:3, memorySize:32768, hashLength:32, outputType:'binary' })` |
| HKDF-SHA256 | `subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits'])` → `subtle.deriveBits({ name:'HKDF', hash:'SHA-256', salt:new Uint8Array(0), info:utf8(info) }, key, 256)` |
| AES-256-GCM | `subtle.importKey('raw', key, 'AES-GCM', false, ['encrypt','decrypt'])`; `encrypt/decrypt({ name:'AES-GCM', iv:nonce, tagLength:128 }, ...)` |
| SHA-256 | `subtle.digest('SHA-256', ...)` |
| CSPRNG | `crypto.getRandomValues` |

Argon2id is the only primitive missing from WebCrypto; everything else is native.

---

## 8. Versioning

`kdf_params` is stored per-account so parameters can evolve without breaking old
accounts. The HKDF `info` strings are explicitly `:v1`-suffixed; a future key
schedule change should bump these rather than reuse them. When any of these
change, **regenerate the test vectors** and update every client together.
