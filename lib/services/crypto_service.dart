import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class CryptoService {
  static const int _iterations = 100000;
  static const int _keyLength = 32; // 256 bits
  static const int _saltLength = 32;

  /// Generate a random salt.
  static Uint8List generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_saltLength, (_) => random.nextInt(256)),
    );
  }

  /// Derive a 256-bit key from password + salt using PBKDF2-HMAC-SHA256.
  static Uint8List deriveKey(String password, Uint8List salt) {
    final params = Pbkdf2Parameters(salt, _iterations, _keyLength);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(params);
    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// SHA-256 hash of the derived key, used for password verification.
  static String hashKey(Uint8List key) {
    final digest = SHA256Digest().process(key);
    return base64Encode(digest);
  }
}
