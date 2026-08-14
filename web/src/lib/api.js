// Thin HTTP client for the SecretNotes sync protocol (/PROTOCOL.md §5).
// Knows nothing about encryption — it only moves opaque base64 blobs and tokens.
// Mirrors the Dart SyncClient.

import { fromB64, toB64 } from './bytes.js';

export class SyncError extends Error {
  constructor(message, status) {
    super(message);
    this.name = 'SyncError';
    this.status = status;
  }
}

export class SyncClient {
  /** @param {string} baseUrl e.g. "https://notes.example.com" (no trailing slash needed) */
  constructor(baseUrl, { fetch = globalThis.fetch.bind(globalThis) } = {}) {
    this.baseUrl = baseUrl.replace(/\/+$/, '');
    this._fetch = fetch;
  }

  async _json(path, { method = 'GET', token, body, query } = {}) {
    const url = new URL(this.baseUrl + path);
    if (query) for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
    const headers = {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (token) headers['Authorization'] = `Bearer ${token}`;
    const res = await this._fetch(url, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    const data = text ? JSON.parse(text) : {};
    if (!res.ok) throw new SyncError(data.error ?? 'request failed', res.status);
    return data;
  }

  // --- account bootstrap ---------------------------------------------------

  /** Admin-gated account creation. Returns a bearer token. */
  async register({ adminToken, username, authKey, kdfSaltB64, kdfParamsJson, wrappedDekB64 }) {
    const { token } = await this._json('/v1/register', {
      method: 'POST',
      body: {
        admin_token: adminToken,
        username,
        auth_key: toB64(authKey),
        kdf_salt: kdfSaltB64,
        kdf_params: kdfParamsJson,
        wrapped_dek: wrappedDekB64,
      },
    });
    return token;
  }

  /** Fetch KDF material for a username before deriving the auth key. */
  async prelogin(username) {
    const j = await this._json('/v1/prelogin', { query: { username } });
    return { kdfSaltB64: j.kdf_salt, kdfParamsJson: j.kdf_params };
  }

  /** Authenticate with the derived auth key. Returns { token, wrappedDekB64 }. */
  async login(username, authKey) {
    const j = await this._json('/v1/login', {
      method: 'POST',
      body: { username, auth_key: toB64(authKey) },
    });
    return { token: j.token, wrappedDekB64: j.wrapped_dek };
  }

  /** Re-fetch the envelope for the logged-in user. */
  async keys(token) {
    const j = await this._json('/v1/keys', { token });
    return { kdfSaltB64: j.kdf_salt, kdfParamsJson: j.kdf_params, wrappedDekB64: j.wrapped_dek };
  }

  // --- sync ----------------------------------------------------------------

  /** Pull the change feed since a cursor. Returns { cursor, changes:[RemoteChange] }. */
  async changes(token, since = 0) {
    const j = await this._json('/v1/changes', { token, query: { since: String(since) } });
    return { cursor: j.cursor, changes: j.changes.map(parseRemoteChange) };
  }

  /**
   * Push local changes. Each change: { id, blob:Uint8Array|null, baseRev,
   * deleted, updatedAt }. Returns { cursor, results:[PushResult] }.
   */
  async push(token, changes) {
    const body = {
      changes: changes.map((c) => ({
        id: c.id,
        blob: c.blob && c.blob.length ? toB64(c.blob) : null,
        base_rev: c.baseRev ?? 0,
        deleted: !!c.deleted,
        updated_at: c.updatedAt ?? 0,
      })),
    };
    const j = await this._json('/v1/push', { method: 'POST', token, body });
    return { cursor: j.cursor, results: j.results.map(parsePushResult) };
  }
}

/** @typedef {{id:string, blob:Uint8Array, rev:number, deleted:boolean, updatedAt:number}} RemoteChange */

function parseRemoteChange(j) {
  return {
    id: j.id ?? '',
    blob: j.blob ? fromB64(j.blob) : new Uint8Array(0),
    rev: j.rev,
    deleted: !!j.deleted,
    updatedAt: j.updated_at ?? 0,
  };
}

function parsePushResult(j) {
  return {
    id: j.id,
    status: j.status, // "ok" | "conflict"
    rev: j.rev ?? 0,
    server: j.server ? parseRemoteChange(j.server) : null,
    get isConflict() {
      return this.status === 'conflict';
    },
  };
}
