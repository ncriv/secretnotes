# SecretNotes sync server

A self-contained, end-to-end-encrypted blob store for the SecretNotes app.
Python standard library only — no dependencies.

The server is deliberately dumb: it never sees your password, the keys derived
from it, or the plaintext of any note. It stores ciphertext blobs, a per-note
revision number for sync ordering and conflict detection, and a login verifier
that cannot be reversed into your password.

## Run

```sh
python3 secretnotes_server.py \
  --db /var/lib/secretnotes/notes.db \
  --host 127.0.0.1 --port 8787 \
  --admin-token "$(openssl rand -hex 16)"
```

`--admin-token` (or the `SECRETNOTES_ADMIN_TOKEN` env var) is required and gates
account registration, so the server isn't an open sign-up endpoint. Hand this
token to the app once, when connecting the first device.

### Serving the web client

Pass `--web-dir` (or `SECRETNOTES_WEB_DIR`) to serve the built browser app from
the same origin as the API — no CORS, no separate host:

```sh
python3 secretnotes_server.py --db notes.db --admin-token "$TOKEN" --web-dir ../web/dist
```

Build it first with `npm run build` in `../web`. The server returns `index.html`
at `/`, serves hashed assets under `/assets/` with a long immutable cache, keeps
`/v1/*` and `/healthz` as JSON, and falls back to `index.html` for any other
path. Path traversal outside `--web-dir` is refused.

### TLS

Payloads are E2E-encrypted, but **put the server behind TLS anyway** — it still
protects bearer tokens, usernames, and metadata in transit. Easiest is a
reverse proxy:

```
# Caddy
notes.example.com {
    reverse_proxy 127.0.0.1:8787
}
```

## What the server can and cannot see

| Sees | Cannot see |
| --- | --- |
| username, login verifier | password, master key, wrap key |
| KDF salt/params, **wrapped** DEK | the DEK itself, note plaintext/titles |
| ciphertext blob sizes (padded to buckets) | exact note sizes |
| note count, revisions, sync timing | which note is which |

Padding rounds note sizes to coarse buckets, but access patterns (counts,
timing) are still observable to whoever runs the server — that's you.

## HTTP API

All bodies are JSON; binary fields are base64. Authenticated routes take
`Authorization: Bearer <token>`.

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| POST | `/v1/register` | admin token | create account, returns device token |
| GET  | `/v1/prelogin?username=` | none | KDF salt/params for a username |
| POST | `/v1/login` | none | exchange authKey for a token + wrapped DEK |
| GET  | `/v1/keys` | bearer | KDF salt/params + wrapped DEK (new device) |
| GET  | `/v1/changes?since=N` | bearer | changed notes with `seq > N` |
| POST | `/v1/push` | bearer | upload changes; per-note ok/conflict |
| GET  | `/healthz` | none | liveness check |

`register`/`login` return a long-lived device token; revoke a lost device by
deleting its row from the `tokens` table.

### Conflict model

Each note carries a server-assigned `rev`. A push includes the `base_rev` the
client last saw. If it still matches, the write is accepted and `rev` advances;
otherwise the server returns `status: "conflict"` with its current version, and
the client keeps a local "conflicted copy" rather than losing either edit.
