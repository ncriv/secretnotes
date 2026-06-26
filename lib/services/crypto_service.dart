import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Low-level cryptographic primitives for SecretNotes.
///
/// Key hierarchy (Bitwarden-style envelope):
///
///   password ──Argon2id(kdfSalt)──▶ masterKey (32 bytes)
///                                      │
///                  ┌───────────────────┼────────────────────┐
///        HKDF(info:"wrap")   HKDF(info:"auth")               │
///                  │                   │                      │
///               wrapKey             authKey            (never stored
///                  │                   │                 on the server)
///        unwraps the DEK      sent to the server
///                  │                 as the login secret
///                  ▼
///      DEK (random 32 bytes) ── AES-256-GCM ──▶ every note blob
///
/// The DEK is what actually encrypts notes; it is generated once and shared
/// across all of a user's devices (delivered wrapped, decryptable only with
/// the password-derived wrapKey). The server never sees the password, the
/// masterKey, the wrapKey, or the DEK — only ciphertext and the authKey.
class CryptoService {
  // --- Argon2id parameters (defaults; persisted per-account for forward-compat).
  static const int kdfMemoryKib = 1 << 15; // 32 MiB
  static const int kdfIterations = 3;
  static const int kdfLanes = 4;
  static const int keyLength = 32; // 256-bit keys throughout

  static const int _saltLength = 16;
  static const int _gcmNonceLength = 12;
  static const int _gcmTagBits = 128;
  static const int _padHeader = 4; // big-endian uint32 plaintext length
  static const int _minBucket = 256;

  static final Random _rng = Random.secure();

  /// Cryptographically-secure random bytes.
  static Uint8List randomBytes(int n) {
    return Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));
  }

  static Uint8List generateSalt() => randomBytes(_saltLength);

  /// A fresh random Data Encryption Key.
  static Uint8List generateDek() => randomBytes(keyLength);

  /// Derive the master key from the password with Argon2id.
  static Uint8List deriveMasterKey(
    String password,
    Uint8List salt, {
    int memoryKib = kdfMemoryKib,
    int iterations = kdfIterations,
    int lanes = kdfLanes,
  }) {
    final params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      version: Argon2Parameters.ARGON2_VERSION_13,
      iterations: iterations,
      memory: memoryKib,
      lanes: lanes,
      desiredKeyLength: keyLength,
    );
    final gen = Argon2BytesGenerator()..init(params);
    return gen.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// HKDF-SHA256 expansion of [ikm] into [length] bytes bound to [info].
  static Uint8List hkdf(Uint8List ikm, String info, int length) {
    final params = HkdfParameters(
      ikm,
      length,
      null,
      Uint8List.fromList(utf8.encode(info)),
    );
    final kdf = HKDFKeyDerivator(SHA256Digest())..init(params);
    final out = Uint8List(length);
    kdf.deriveKey(null, 0, out, 0);
    return out;
  }

  /// Key that wraps/unwraps the DEK (stays on device).
  static Uint8List wrapKey(Uint8List masterKey) =>
      hkdf(masterKey, 'secretnotes:wrap:v1', keyLength);

  /// Login secret presented to the server (derived from, but not reversible
  /// to, the password — and distinct from the wrapKey, so it never reveals
  /// anything that decrypts data).
  static Uint8List authKey(Uint8List masterKey) =>
      hkdf(masterKey, 'secretnotes:auth:v1', keyLength);

  // --- AES-256-GCM ----------------------------------------------------------

  /// Encrypt [plaintext] with AES-256-GCM. Output is `nonce(12) || ct || tag`.
  static Uint8List gcmEncrypt(Uint8List key, Uint8List plaintext) {
    final nonce = randomBytes(_gcmNonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), _gcmTagBits, nonce, Uint8List(0)));
    final ct = cipher.process(plaintext);
    return Uint8List.fromList([...nonce, ...ct]);
  }

  /// Decrypt a `nonce || ct || tag` blob. Throws on a bad key or tampering
  /// (GCM authentication failure) — which doubles as wrong-password detection.
  static Uint8List gcmDecrypt(Uint8List key, Uint8List blob) {
    if (blob.length < _gcmNonceLength + 16) {
      throw ArgumentError('ciphertext too short');
    }
    final nonce = blob.sublist(0, _gcmNonceLength);
    final ct = blob.sublist(_gcmNonceLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), _gcmTagBits, nonce, Uint8List(0)));
    return cipher.process(ct);
  }

  // --- DEK wrapping ---------------------------------------------------------

  static Uint8List wrapDek(Uint8List wrapKey, Uint8List dek) =>
      gcmEncrypt(wrapKey, dek);

  static Uint8List unwrapDek(Uint8List wrapKey, Uint8List wrappedDek) =>
      gcmDecrypt(wrapKey, wrappedDek);

  // --- Note blob encryption with length-hiding padding ----------------------

  /// Round a plaintext length up to a size bucket so the ciphertext length
  /// leaks only a coarse bucket, not the exact note size.
  static int paddedSize(int plaintextLen) {
    final needed = _padHeader + plaintextLen;
    var bucket = _minBucket;
    while (bucket < needed) {
      bucket <<= 1;
    }
    return bucket;
  }

  /// Encrypt a note payload: pad to a size bucket, then AES-256-GCM.
  static Uint8List encryptPayload(Uint8List dek, Uint8List plaintext) {
    final padded = Uint8List(paddedSize(plaintext.length));
    final bd = ByteData.view(padded.buffer);
    bd.setUint32(0, plaintext.length, Endian.big);
    padded.setRange(_padHeader, _padHeader + plaintext.length, plaintext);
    // Remaining bytes are already zero-filled by Uint8List's initializer.
    return gcmEncrypt(dek, padded);
  }

  /// Decrypt and unpad a note payload produced by [encryptPayload].
  static Uint8List decryptPayload(Uint8List dek, Uint8List blob) {
    final padded = gcmDecrypt(dek, blob);
    if (padded.length < _padHeader) {
      throw ArgumentError('payload too short');
    }
    final len = ByteData.view(padded.buffer, padded.offsetInBytes, _padHeader)
        .getUint32(0, Endian.big);
    if (_padHeader + len > padded.length) {
      throw ArgumentError('corrupt padding');
    }
    return padded.sublist(_padHeader, _padHeader + len);
  }

  // --- Server auth-hash (server-side verifier) ------------------------------

  /// Hash the authKey for storage/verification: SHA-256(salt || authKey).
  /// Mirrors what the reference server computes.
  static String authHash(Uint8List salt, Uint8List authKey) {
    final digest = SHA256Digest().process(
      Uint8List.fromList([...salt, ...authKey]),
    );
    return base64Encode(digest);
  }

  // --- Legacy (pre-sync) key derivation, kept only for one-time migration ---

  static const int _legacyIterations = 100000;

  /// The original PBKDF2-HMAC-SHA256 derivation used before the envelope model.
  static Uint8List legacyDeriveKey(String password, Uint8List salt) {
    final params = Pbkdf2Parameters(salt, _legacyIterations, keyLength);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  static String legacyHashKey(Uint8List key) =>
      base64Encode(SHA256Digest().process(key));
}
