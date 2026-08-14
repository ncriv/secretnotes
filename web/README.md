# SecretNotes Web Client

A remote-only, end-to-end-encrypted browser client for SecretNotes. It speaks
the same sync protocol and crypto as the Flutter app — see [`/PROTOCOL.md`](../PROTOCOL.md)
for the contract. Notes are encrypted/decrypted **in the browser**; the server
only ever sees ciphertext.

Unlike the mobile app this client is **remote-only** (no local vault, no
migration) and logs in with **username + password** (no biometrics).

## Stack

Svelte + Vite, plain CSS with design tokens. Self-hosted fonts (no third-party
requests — a privacy app shouldn't phone home). The editor is **Quill.js**,
whose native Delta format is exactly what notes store. See `DESIGN-NOTES.md` for
the visual direction.

| Layer | File | Tested by |
|-------|------|-----------|
| Bytes / base64 / utf8 | `src/lib/bytes.js` | (used throughout) |
| Crypto (Argon2id, HKDF, AES-GCM) | `src/lib/crypto.js` | `test/parity.test.js` |
| Note codec + padding | `src/lib/codec.js` | `test/parity.test.js`, `test/codec.test.js` |
| HTTP sync client | `src/lib/api.js` | `test/session.test.js`, `e2e/live-server.mjs` |
| Login flow + in-memory vault | `src/lib/session.js` | `test/session.test.js`, `e2e/live-server.mjs` |
| Reactive store (Svelte) | `src/lib/store.js` | — |
| UI | `src/App.svelte`, `src/components/*` | screenshots (manual) |

## The parity guarantee

`test/parity.test.js` asserts this client against
[`../test/fixtures/protocol_vectors.json`](../test/fixtures/protocol_vectors.json)
— the **same** fixture the Dart suite uses, generated from the real mobile
`CryptoService`. If parity is green, a note encrypted on the phone decrypts in
the browser and vice-versa. Regenerate the fixture from the Dart side with
`dart run tool/generate_test_vectors.dart` (from the repo root); never edit it by
hand.

The one non-native dependency is [`hash-wasm`](https://github.com/Daninet/hash-wasm)
for Argon2id; AES-GCM, HKDF, and SHA-256 are WebCrypto.

## Develop & test

```sh
cd web
npm install
npm test        # node --test — crypto parity + codec + sync/merge logic
npm run e2e     # spins up the real Python server, does register→login→push→pull
npm run dev     # Vite dev server on :5173, proxies /v1 to the sync server
```

Tests run in Node (v20+), which exposes the same `crypto.subtle` the browser
uses, so parity is verified headlessly with no browser needed. `npm run dev`
proxies the API to `http://127.0.0.1:8787` by default (override with the
`SECRETNOTES_API` env var); start the sync server separately:

```sh
python3 ../server/secretnotes_server.py --db notes.db --admin-token "$(openssl rand -hex 16)"
```

Accounts are admin-gated (see `/PROTOCOL.md` §5) — the web app is a **login**
client. Create an account with the admin token, then sign in.

## Build & deploy

```sh
npm run build   # → dist/ (static, self-contained)
```

The sync server can serve the built app directly, so the app and API share an
origin (no CORS, no proxy):

```sh
python3 ../server/secretnotes_server.py \
  --db notes.db --admin-token "$TOKEN" --web-dir web/dist
```

It serves `index.html` at `/`, hashed assets under `/assets/` with an immutable
cache, keeps `/v1/*` and `/healthz` as JSON, and falls back to `index.html` for
unknown paths. Put TLS in front (a reverse proxy) in production. Any static host
works too, as long as `/v1` reaches the sync server.
