#!/usr/bin/env python3
"""SecretNotes sync server — a dumb end-to-end-encrypted blob store.

The server never sees plaintext, the master password, or anything that can
decrypt notes. It stores, per account:

  * an opaque login verifier (sha256(salt || authKey)), where authKey is itself
    Argon2id-derived on the client — the password never reaches the server;
  * the KDF salt/params and the *wrapped* DEK, so a new device can bootstrap;
  * per-note ciphertext blobs plus a monotonic revision used for sync ordering
    and optimistic-concurrency conflict detection.

Standard library only (http.server + sqlite3). Run:

    python3 secretnotes_server.py --db notes.db --admin-token "$(openssl rand -hex 16)"

Put it behind TLS (a reverse proxy such as Caddy/nginx) in production: the
payloads are E2E-encrypted, but TLS still protects tokens and metadata.
"""

import argparse
import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

SCHEMA = """
CREATE TABLE IF NOT EXISTS accounts (
    username    TEXT PRIMARY KEY,
    auth_salt   BLOB NOT NULL,
    auth_hash   BLOB NOT NULL,
    kdf_salt    TEXT NOT NULL,
    kdf_params  TEXT NOT NULL,
    wrapped_dek TEXT NOT NULL,
    seq         INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
    token      TEXT PRIMARY KEY,
    username   TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS notes (
    username   TEXT NOT NULL,
    id         TEXT NOT NULL,
    blob       BLOB NOT NULL,
    rev        INTEGER NOT NULL,
    deleted    INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL,
    seq        INTEGER NOT NULL,
    PRIMARY KEY (username, id)
);
CREATE INDEX IF NOT EXISTS notes_seq ON notes (username, seq);
"""


class Store:
    """Thin SQLite wrapper. One connection guarded by a lock keeps the
    server correct under ThreadingHTTPServer without per-request setup."""

    def __init__(self, path):
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        with self._lock:
            self._db.executescript(SCHEMA)
            self._db.commit()

    # --- accounts ---------------------------------------------------------
    def create_account(self, username, auth_key, kdf_salt, kdf_params, wrapped_dek):
        auth_salt = secrets.token_bytes(16)
        auth_hash = hashlib.sha256(auth_salt + auth_key).digest()
        now = _epoch_ms_from_db(self)
        with self._lock:
            try:
                self._db.execute(
                    "INSERT INTO accounts "
                    "(username, auth_salt, auth_hash, kdf_salt, kdf_params, wrapped_dek, seq, created_at) "
                    "VALUES (?,?,?,?,?,?,0,?)",
                    (username, auth_salt, auth_hash, kdf_salt, kdf_params, wrapped_dek, now),
                )
                self._db.commit()
            except sqlite3.IntegrityError:
                return False
        return True

    def account(self, username):
        with self._lock:
            return self._db.execute(
                "SELECT * FROM accounts WHERE username=?", (username,)
            ).fetchone()

    def verify(self, username, auth_key):
        row = self.account(username)
        if row is None:
            return None
        expected = hashlib.sha256(bytes(row["auth_salt"]) + auth_key).digest()
        if not hmac.compare_digest(expected, bytes(row["auth_hash"])):
            return None
        return row

    def new_token(self, username):
        token = secrets.token_urlsafe(32)
        with self._lock:
            self._db.execute(
                "INSERT INTO tokens (token, username, created_at) VALUES (?,?,?)",
                (token, username, 0),
            )
            self._db.commit()
        return token

    def user_for_token(self, token):
        if not token:
            return None
        with self._lock:
            row = self._db.execute(
                "SELECT username FROM tokens WHERE token=?", (token,)
            ).fetchone()
        return row["username"] if row else None

    # --- notes ------------------------------------------------------------
    def changes_since(self, username, since):
        with self._lock:
            rows = self._db.execute(
                "SELECT id, blob, rev, deleted, updated_at FROM notes "
                "WHERE username=? AND seq>? ORDER BY seq ASC",
                (username, since),
            ).fetchall()
            cursor = self._db.execute(
                "SELECT seq FROM accounts WHERE username=?", (username,)
            ).fetchone()["seq"]
        changes = [
            {
                "id": r["id"],
                "blob": base64.b64encode(bytes(r["blob"])).decode(),
                "rev": r["rev"],
                "deleted": bool(r["deleted"]),
                "updated_at": r["updated_at"],
            }
            for r in rows
        ]
        return cursor, changes

    def push(self, username, changes):
        """Apply a batch of client changes under one transaction, allocating a
        fresh monotonic seq per accepted write. Returns (cursor, results)."""
        results = []
        with self._lock:
            try:
                seq = self._db.execute(
                    "SELECT seq FROM accounts WHERE username=?", (username,)
                ).fetchone()["seq"]
                for c in changes:
                    note_id = c["id"]
                    base_rev = int(c.get("base_rev", 0))
                    deleted = 1 if c.get("deleted") else 0
                    updated_at = int(c.get("updated_at", 0))
                    blob = base64.b64decode(c["blob"]) if c.get("blob") else b""

                    row = self._db.execute(
                        "SELECT blob, rev, deleted, updated_at FROM notes "
                        "WHERE username=? AND id=?",
                        (username, note_id),
                    ).fetchone()

                    if row is not None and row["rev"] != base_rev:
                        # Stale base revision — report the server's version so
                        # the client can keep a conflicted copy.
                        results.append({
                            "id": note_id,
                            "status": "conflict",
                            "rev": row["rev"],
                            "server": {
                                "id": note_id,
                                "blob": base64.b64encode(bytes(row["blob"])).decode(),
                                "rev": row["rev"],
                                "deleted": bool(row["deleted"]),
                                "updated_at": row["updated_at"],
                            },
                        })
                        continue

                    seq += 1
                    self._db.execute(
                        "INSERT INTO notes (username, id, blob, rev, deleted, updated_at, seq) "
                        "VALUES (?,?,?,?,?,?,?) "
                        "ON CONFLICT(username, id) DO UPDATE SET "
                        "blob=excluded.blob, rev=excluded.rev, deleted=excluded.deleted, "
                        "updated_at=excluded.updated_at, seq=excluded.seq",
                        (username, note_id, blob, seq, deleted, updated_at, seq),
                    )
                    results.append({"id": note_id, "status": "ok", "rev": seq})

                self._db.execute(
                    "UPDATE accounts SET seq=? WHERE username=?", (seq, username)
                )
                self._db.commit()
            except Exception:
                self._db.rollback()
                raise
        return seq, results


def _epoch_ms_from_db(store):
    # SQLite's strftime gives us a clock without importing time/Date.
    row = store._db.execute(
        "SELECT CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER) AS ms"
    ).fetchone()
    return row["ms"]


class Handler(BaseHTTPRequestHandler):
    server_version = "SecretNotesSync/1.0"

    # Wired up in main().
    store = None
    admin_token = None

    def log_message(self, fmt, *args):
        # Quiet by default; uncomment for debugging.
        pass

    # --- helpers ----------------------------------------------------------
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length))

    def _auth_user(self):
        header = self.headers.get("Authorization", "")
        token = header[7:] if header.startswith("Bearer ") else ""
        return self.store.user_for_token(token)

    @staticmethod
    def _b64(value):
        return base64.b64decode(value)

    # --- routing ----------------------------------------------------------
    def do_GET(self):
        url = urlparse(self.path)
        try:
            if url.path == "/v1/prelogin":
                return self._prelogin(parse_qs(url.query))
            if url.path == "/v1/keys":
                return self._keys()
            if url.path == "/v1/changes":
                return self._changes(parse_qs(url.query))
            if url.path == "/healthz":
                return self._send(200, {"ok": True})
        except Exception as exc:  # noqa: BLE001 - surface as 500 JSON
            return self._send(500, {"error": str(exc)})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        url = urlparse(self.path)
        try:
            if url.path == "/v1/register":
                return self._register()
            if url.path == "/v1/login":
                return self._login()
            if url.path == "/v1/push":
                return self._push()
        except Exception as exc:  # noqa: BLE001
            return self._send(500, {"error": str(exc)})
        self._send(404, {"error": "not found"})

    # --- endpoints --------------------------------------------------------
    def _register(self):
        b = self._body()
        if not hmac.compare_digest(str(b.get("admin_token", "")), self.admin_token):
            return self._send(403, {"error": "invalid admin token"})
        for field in ("username", "auth_key", "kdf_salt", "kdf_params", "wrapped_dek"):
            if not b.get(field):
                return self._send(400, {"error": f"missing {field}"})
        ok = self.store.create_account(
            b["username"],
            self._b64(b["auth_key"]),
            b["kdf_salt"],
            b["kdf_params"],
            b["wrapped_dek"],
        )
        if not ok:
            return self._send(409, {"error": "username already exists"})
        token = self.store.new_token(b["username"])
        self._send(200, {"token": token})

    def _prelogin(self, q):
        username = (q.get("username") or [""])[0]
        row = self.store.account(username)
        if row is None:
            return self._send(404, {"error": "unknown account"})
        self._send(200, {"kdf_salt": row["kdf_salt"], "kdf_params": row["kdf_params"]})

    def _login(self):
        b = self._body()
        row = self.store.verify(b.get("username", ""), self._b64(b.get("auth_key", "")))
        if row is None:
            return self._send(401, {"error": "invalid credentials"})
        token = self.store.new_token(row["username"])
        self._send(200, {"token": token, "wrapped_dek": row["wrapped_dek"]})

    def _keys(self):
        user = self._auth_user()
        if user is None:
            return self._send(401, {"error": "unauthorized"})
        row = self.store.account(user)
        self._send(200, {
            "kdf_salt": row["kdf_salt"],
            "kdf_params": row["kdf_params"],
            "wrapped_dek": row["wrapped_dek"],
        })

    def _changes(self, q):
        user = self._auth_user()
        if user is None:
            return self._send(401, {"error": "unauthorized"})
        since = int((q.get("since") or ["0"])[0])
        cursor, changes = self.store.changes_since(user, since)
        self._send(200, {"cursor": cursor, "changes": changes})

    def _push(self):
        user = self._auth_user()
        if user is None:
            return self._send(401, {"error": "unauthorized"})
        b = self._body()
        cursor, results = self.store.push(user, b.get("changes", []))
        self._send(200, {"cursor": cursor, "results": results})


def main():
    parser = argparse.ArgumentParser(description="SecretNotes sync server")
    parser.add_argument("--db", default="secretnotes.db")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument(
        "--admin-token",
        default=os.environ.get("SECRETNOTES_ADMIN_TOKEN"),
        help="required to register new accounts (or set SECRETNOTES_ADMIN_TOKEN)",
    )
    args = parser.parse_args()
    if not args.admin_token:
        parser.error("--admin-token (or SECRETNOTES_ADMIN_TOKEN) is required")

    Handler.store = Store(args.db)
    Handler.admin_token = args.admin_token

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"SecretNotes sync server listening on http://{args.host}:{args.port}")
    print("Endpoints: /v1/{register,prelogin,login,keys,changes,push}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")
        httpd.shutdown()


if __name__ == "__main__":
    main()
