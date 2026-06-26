import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'crypto_service.dart';

/// The secrets recovered by a successful unlock.
///
/// [dek] decrypts notes. [authKey] authenticates to the sync server.
/// [legacyKey] is non-null only while a pre-sync vault still needs migrating;
/// the caller uses it to import the old notes, then calls
/// [AuthService.finalizeMigration].
class UnlockResult {
  final Uint8List dek;
  final Uint8List authKey;
  final Uint8List? legacyKey;

  UnlockResult({required this.dek, required this.authKey, this.legacyKey});
}

class AuthService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  // New envelope-model keys.
  static const _kKdfSalt = 'kdf_salt';
  static const _kKdfParams = 'kdf_params';
  static const _kWrappedDek = 'wrapped_dek';

  // Biometric unlock material.
  static const _kBioEnabled = 'biometric_enabled';
  static const _kBioDek = 'bio_dek';
  static const _kBioAuth = 'bio_auth';

  // Legacy (pre-sync) verifier. Kept (along with the backup box) even after
  // migration, so the backup stays decryptable until the user removes it.
  static const _kLegacySalt = 'salt';
  static const _kLegacyHash = 'key_hash';

  // Set once the legacy vault has been migrated and verified. Gates re-running
  // migration without relying on the backup box being deleted.
  static const _kMigrationDone = 'migration_done';

  Future<bool> hasAccount() async =>
      (await _secureStorage.read(key: _kKdfSalt)) != null;

  Future<bool> hasLegacyAccount() async =>
      (await _secureStorage.read(key: _kLegacySalt)) != null;

  Future<bool> isFirstLaunch() async =>
      !(await hasAccount()) && !(await hasLegacyAccount());

  Map<String, int> get _defaultKdfParams => {
        'm': CryptoService.kdfMemoryKib,
        't': CryptoService.kdfIterations,
        'p': CryptoService.kdfLanes,
      };

  /// First-launch setup: generate a fresh DEK and password-wrapped envelope.
  Future<UnlockResult> setupPassword(String password) async {
    final salt = CryptoService.generateSalt();
    final params = _defaultKdfParams;
    final masterKey = CryptoService.deriveMasterKey(
      password,
      salt,
      memoryKib: params['m']!,
      iterations: params['t']!,
      lanes: params['p']!,
    );
    final dek = CryptoService.generateDek();
    final wrapped = CryptoService.wrapDek(CryptoService.wrapKey(masterKey), dek);

    await _persistEnvelope(salt, params, wrapped);

    return UnlockResult(dek: dek, authKey: CryptoService.authKey(masterKey));
  }

  /// Verify the password and recover the secrets, transparently upgrading a
  /// legacy vault to the envelope model on the way through. Returns null on a
  /// wrong password.
  Future<UnlockResult?> login(String password) async {
    final hasNew = await hasAccount();

    Uint8List dek;
    Uint8List authKey;

    if (hasNew) {
      final unlocked = await _unlockNew(password);
      if (unlocked == null) return null;
      dek = unlocked.dek;
      authKey = unlocked.authKey;
    } else {
      // Legacy-only account: verify the old key, then build + persist a new
      // envelope so future logins use Argon2id.
      final legacy = await _deriveLegacy(password);
      if (legacy == null) return null;
      final upgraded = await setupPassword(password);
      dek = upgraded.dek;
      authKey = upgraded.authKey;
    }

    // Hand the old key back only if a legacy vault still needs migrating.
    // Once migration is done we skip this entirely (no re-migration, and no
    // unnecessary legacy key derivation).
    final legacyKey =
        await isMigrationDone() ? null : await _deriveLegacy(password);
    return UnlockResult(dek: dek, authKey: authKey, legacyKey: legacyKey);
  }

  Future<UnlockResult?> _unlockNew(String password) async {
    final saltB64 = await _secureStorage.read(key: _kKdfSalt);
    final paramsJson = await _secureStorage.read(key: _kKdfParams);
    final wrappedB64 = await _secureStorage.read(key: _kWrappedDek);
    if (saltB64 == null || paramsJson == null || wrappedB64 == null) {
      return null;
    }
    final params = (jsonDecode(paramsJson) as Map).cast<String, dynamic>();
    final masterKey = CryptoService.deriveMasterKey(
      password,
      base64Decode(saltB64),
      memoryKib: params['m'] as int,
      iterations: params['t'] as int,
      lanes: params['p'] as int,
    );
    try {
      final dek = CryptoService.unwrapDek(
        CryptoService.wrapKey(masterKey),
        base64Decode(wrappedB64),
      );
      return UnlockResult(dek: dek, authKey: CryptoService.authKey(masterKey));
    } catch (_) {
      // GCM authentication failure == wrong password.
      return null;
    }
  }

  /// Returns the legacy PBKDF2 key if a legacy verifier exists and the password
  /// matches it; otherwise null.
  Future<Uint8List?> _deriveLegacy(String password) async {
    final saltB64 = await _secureStorage.read(key: _kLegacySalt);
    final storedHash = await _secureStorage.read(key: _kLegacyHash);
    if (saltB64 == null || storedHash == null) return null;
    final key = CryptoService.legacyDeriveKey(password, base64Decode(saltB64));
    if (CryptoService.legacyHashKey(key) != storedHash) return null;
    return key;
  }

  Future<void> _persistEnvelope(
    Uint8List salt,
    Map<String, int> params,
    Uint8List wrappedDek,
  ) async {
    await _secureStorage.write(key: _kKdfSalt, value: base64Encode(salt));
    await _secureStorage.write(key: _kKdfParams, value: jsonEncode(params));
    await _secureStorage.write(
      key: _kWrappedDek,
      value: base64Encode(wrappedDek),
    );
  }

  /// Install an envelope received from the server when linking a new device to
  /// an existing account, so the device can also unlock offline.
  Future<void> installEnvelope({
    required String saltB64,
    required String paramsJson,
    required String wrappedDekB64,
  }) async {
    await _secureStorage.write(key: _kKdfSalt, value: saltB64);
    await _secureStorage.write(key: _kKdfParams, value: paramsJson);
    await _secureStorage.write(key: _kWrappedDek, value: wrappedDekB64);
  }

  Future<bool> isMigrationDone() async =>
      (await _secureStorage.read(key: _kMigrationDone)) == 'true';

  /// Record that the legacy vault migrated and verified successfully. The
  /// backup box and its verifier are kept until the user removes them.
  Future<void> finalizeMigration() async {
    await _secureStorage.write(key: _kMigrationDone, value: 'true');
  }

  /// Remove the legacy verifier — call when deleting the pre-sync backup, since
  /// the old box is no longer needed.
  Future<void> clearLegacyVerifier() async {
    await _secureStorage.delete(key: _kLegacySalt);
    await _secureStorage.delete(key: _kLegacyHash);
  }

  /// Material needed to bootstrap a sync account on the server.
  Future<({String saltB64, String paramsJson, String wrappedDekB64})?>
      envelope() async {
    final saltB64 = await _secureStorage.read(key: _kKdfSalt);
    final paramsJson = await _secureStorage.read(key: _kKdfParams);
    final wrappedB64 = await _secureStorage.read(key: _kWrappedDek);
    if (saltB64 == null || paramsJson == null || wrappedB64 == null) {
      return null;
    }
    return (saltB64: saltB64, paramsJson: paramsJson, wrappedDekB64: wrappedB64);
  }

  // --- Biometric unlock -----------------------------------------------------

  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isBiometricEnabled() async =>
      (await _secureStorage.read(key: _kBioEnabled)) == 'true';

  Future<void> enableBiometric(Uint8List dek, Uint8List authKey) async {
    await _secureStorage.write(key: _kBioDek, value: base64Encode(dek));
    await _secureStorage.write(key: _kBioAuth, value: base64Encode(authKey));
    await _secureStorage.write(key: _kBioEnabled, value: 'true');
  }

  Future<void> disableBiometric() async {
    await _secureStorage.delete(key: _kBioDek);
    await _secureStorage.delete(key: _kBioAuth);
    await _secureStorage.write(key: _kBioEnabled, value: 'false');
  }

  Future<UnlockResult?> biometricLogin() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Unlock SecretNotes',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!authenticated) return null;

      final dekB64 = await _secureStorage.read(key: _kBioDek);
      final authB64 = await _secureStorage.read(key: _kBioAuth);
      if (dekB64 == null || authB64 == null) return null;

      return UnlockResult(
        dek: base64Decode(dekB64),
        authKey: base64Decode(authB64),
      );
    } catch (_) {
      return null;
    }
  }
}
