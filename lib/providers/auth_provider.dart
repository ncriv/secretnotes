import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  bool _isUnlocked = false;
  bool _isFirstLaunch = true;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _isLoading = false;
  String? _error;
  Uint8List? _encryptionKey;

  bool get isUnlocked => _isUnlocked;
  bool get isFirstLaunch => _isFirstLaunch;
  bool get biometricAvailable => _biometricAvailable;
  bool get biometricEnabled => _biometricEnabled;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Uint8List? get encryptionKey => _encryptionKey;

  Future<void> init() async {
    _isFirstLaunch = await _authService.isFirstLaunch();
    _biometricAvailable = await _authService.isBiometricAvailable();
    if (!_isFirstLaunch) {
      _biometricEnabled = await _authService.isBiometricEnabled();
    }
    notifyListeners();
  }

  Future<bool> setupPassword(String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _encryptionKey = await _authService.setupPassword(password);
      _isUnlocked = true;
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
      final key = await _authService.login(password);
      if (key != null) {
        _encryptionKey = key;
        _isUnlocked = true;
        _error = null;
      } else {
        _error = 'Wrong password';
      }
      _isLoading = false;
      notifyListeners();
      return key != null;
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
      final key = await _authService.biometricLogin();
      if (key != null) {
        _encryptionKey = key;
        _isUnlocked = true;
      } else {
        _error = 'Biometric authentication failed';
      }
      _isLoading = false;
      notifyListeners();
      return key != null;
    } catch (e) {
      _error = 'Biometric authentication failed';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> enableBiometric() async {
    if (_encryptionKey == null) return;
    await _authService.enableBiometric(_encryptionKey!);
    _biometricEnabled = true;
    notifyListeners();
  }

  Future<void> disableBiometric() async {
    await _authService.disableBiometric();
    _biometricEnabled = false;
    notifyListeners();
  }

  void lock() {
    _encryptionKey = null;
    _isUnlocked = false;
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
