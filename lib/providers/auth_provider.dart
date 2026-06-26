import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isUnlocked = false;
  bool _isFirstLaunch = true;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _isLoading = false;
  String? _error;

  Uint8List? _dek;
  Uint8List? _authKey;
  Uint8List? _pendingLegacyKey;

  bool get isUnlocked => _isUnlocked;
  bool get isFirstLaunch => _isFirstLaunch;
  bool get biometricAvailable => _biometricAvailable;
  bool get biometricEnabled => _biometricEnabled;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Data Encryption Key — decrypts notes.
  Uint8List? get dek => _dek;

  /// Server login secret for the active session.
  Uint8List? get authKey => _authKey;

  Future<void> init() async {
    _isFirstLaunch = await _authService.isFirstLaunch();
    _biometricAvailable = await _authService.isBiometricAvailable();
    if (!_isFirstLaunch) {
      _biometricEnabled = await _authService.isBiometricEnabled();
    }
    notifyListeners();
  }

  void _applyUnlock(UnlockResult result) {
    _dek = result.dek;
    _authKey = result.authKey;
    _pendingLegacyKey = result.legacyKey;
    _isUnlocked = true;
  }

  Future<bool> setupPassword(String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _applyUnlock(await _authService.setupPassword(password));
      _isFirstLaunch = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to set up password';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _authService.login(password);
      if (result != null) {
        _applyUnlock(result);
      } else {
        _error = 'Wrong password';
      }
      _isLoading = false;
      notifyListeners();
      return result != null;
    } catch (e) {
      _error = 'Authentication failed';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> biometricLogin() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _authService.biometricLogin();
      if (result != null) {
        _applyUnlock(result);
      } else {
        _error = 'Biometric authentication failed';
      }
      _isLoading = false;
      notifyListeners();
      return result != null;
    } catch (e) {
      _error = 'Biometric authentication failed';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Adopt a session recovered by linking this device to an existing account.
  void adoptSession(Uint8List dek, Uint8List authKey) {
    _dek = dek;
    _authKey = authKey;
    _pendingLegacyKey = null;
    _isUnlocked = true;
    _isFirstLaunch = false;
    notifyListeners();
  }

  /// Consume the legacy key (if any) that the caller should use to migrate an
  /// old vault, then finalize. Returns null when there's nothing to migrate.
  Uint8List? consumeLegacyKey() {
    final key = _pendingLegacyKey;
    _pendingLegacyKey = null;
    return key;
  }

  Future<void> finalizeMigration() => _authService.finalizeMigration();

  /// Whether a pre-sync backup box is still present on disk.
  Future<bool> hasLegacyBackup() => StorageService.hasLegacyVault();

  /// Permanently remove the pre-sync backup and its verifier.
  Future<void> removeLegacyBackup() async {
    await StorageService.deleteLegacyBackup();
    await _authService.clearLegacyVerifier();
    notifyListeners();
  }

  Future<void> enableBiometric() async {
    if (_dek == null || _authKey == null) return;
    await _authService.enableBiometric(_dek!, _authKey!);
    _biometricEnabled = true;
    notifyListeners();
  }

  Future<void> disableBiometric() async {
    await _authService.disableBiometric();
    _biometricEnabled = false;
    notifyListeners();
  }

  void lock() {
    _dek = null;
    _authKey = null;
    _pendingLegacyKey = null;
    _isUnlocked = false;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
