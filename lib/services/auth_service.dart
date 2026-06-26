import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'crypto_service.dart';

class AuthService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const _keySalt = 'salt';
  static const _keyHash = 'key_hash';
  static const _keyBioEnabled = 'biometric_enabled';
  static const _keyBioKey = 'bio_key';

  /// Check if this is the first launch (no password set yet).
  Future<bool> isFirstLaunch() async {
    final salt = await _secureStorage.read(key: _keySalt);
    return salt == null;
  }

  /// Set up the master password on first launch.
  /// Returns the derived encryption key.
  Future<Uint8List> setupPassword(String password) async {
    final salt = CryptoService.generateSalt();
    final key = CryptoService.deriveKey(password, salt);
    final hash = CryptoService.hashKey(key);

    await _secureStorage.write(key: _keySalt, value: base64Encode(salt));
    await _secureStorage.write(key: _keyHash, value: hash);

    return key;
  }

  /// Verify the master password and return the derived key, or null on failure.
  Future<Uint8List?> login(String password) async {
    final saltB64 = await _secureStorage.read(key: _keySalt);
    final storedHash = await _secureStorage.read(key: _keyHash);
    if (saltB64 == null || storedHash == null) return null;

    final salt = base64Decode(saltB64);
    final key = CryptoService.deriveKey(password, Uint8List.fromList(salt));
    final hash = CryptoService.hashKey(key);

    if (hash == storedHash) return key;
    return null;
  }

  /// Check if the device supports biometric authentication.
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Check if the user has enabled biometric unlock.
  Future<bool> isBiometricEnabled() async {
    final val = await _secureStorage.read(key: _keyBioEnabled);
    return val == 'true';
  }

  /// Enable biometric unlock by storing the encryption key.
  Future<void> enableBiometric(Uint8List key) async {
    await _secureStorage.write(key: _keyBioKey, value: base64Encode(key));
    await _secureStorage.write(key: _keyBioEnabled, value: 'true');
  }

  /// Disable biometric unlock.
  Future<void> disableBiometric() async {
    await _secureStorage.delete(key: _keyBioKey);
    await _secureStorage.write(key: _keyBioEnabled, value: 'false');
  }

  /// Authenticate with biometrics and return the stored key, or null on failure.
  Future<Uint8List?> biometricLogin() async {
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Unlock SecretNotes',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!authenticated) return null;

      final keyB64 = await _secureStorage.read(key: _keyBioKey);
      if (keyB64 == null) return null;

      return Uint8List.fromList(base64Decode(keyB64));
    } catch (_) {
      return null;
    }
  }
}
