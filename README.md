# SecretNotes

An offline-first, end-to-end-encrypted note-taking app (Flutter) with optional
sync to your own server. Notes are encrypted on the device; the server only ever
stores ciphertext.

## Security model

```
password ──Argon2id(salt)──▶ masterKey
                                 │
              HKDF "wrap" ───────┼─────── HKDF "auth"
                  │                            │
               wrapKey                      authKey ──▶ server login secret
                  │                                     (never reveals the password)
            unwraps the DEK
                  │
      DEK (random) ── AES-256-GCM ──▶ each note (padded to a size bucket)
```

- **Argon2id** stretches the master password; the derived key never leaves the
  device.
- A random **Data Encryption Key (DEK)** encrypts notes and is shared across
  devices *wrapped* — only the password-derived `wrapKey` can unwrap it.
- The server receives only the `authKey` (a separate HKDF branch), so it can
  authenticate you without ever holding anything that decrypts data.
- Each note is encrypted independently with **AES-256-GCM** and **padded to a
  size bucket** so blob lengths leak only a coarse bucket, not the real size.
- Local storage is a Hive box of per-note ciphertext records, itself encrypted
  with the DEK for defense-in-depth at rest.

What the server can see: usernames, a login verifier, KDF salt/params, the
*wrapped* DEK, ciphertext blobs, revisions, and sync timing. What it cannot see:
the password, any key that decrypts notes, or note plaintext/titles.

## Sync

- **Optimistic concurrency:** every note carries a server-assigned revision. A
  push includes the last-seen `base_rev`; a stale push is rejected as a conflict.
- **Conflicts keep both sides:** the losing local edit is preserved as a new
  "conflicted copy" note rather than dropped.
- **Deletes** propagate as tombstones; a change cursor makes pulls incremental.
- **Multi-device:** a new device enters the master password, fetches the wrapped
  DEK, and unwraps it locally — no key material is ever transmitted.

The first launch can either create a local vault (set a master password) or
**link to an existing account** on a server. Pre-sync local vaults are migrated
from the old PBKDF2 box-encryption to the envelope model automatically on first
unlock after upgrading.

See [`server/`](server/) for the self-contained reference sync server (Python
standard library + SQLite) and its API.

## Develop

```sh
flutter pub get
flutter test          # crypto round-trips, padding, conflict resolution
flutter run
```
