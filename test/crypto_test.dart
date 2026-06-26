import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secretnotes/services/crypto_service.dart';

void main() {
  group('Argon2id key derivation', () {
    final salt = CryptoService.generateSalt();

    test('is deterministic for the same password + salt', () {
      final a = CryptoService.deriveMasterKey('correct horse', salt);
      final b = CryptoService.deriveMasterKey('correct horse', salt);
      expect(a, equals(b));
      expect(a.length, 32);
    });

    test('differs for a different password', () {
      final a = CryptoService.deriveMasterKey('correct horse', salt);
      final c = CryptoService.deriveMasterKey('battery staple', salt);
      expect(a, isNot(equals(c)));
    });

    test('differs for a different salt', () {
      final a = CryptoService.deriveMasterKey('pw', salt);
      final b = CryptoService.deriveMasterKey('pw', CryptoService.generateSalt());
      expect(a, isNot(equals(b)));
    });
  });

  group('HKDF key separation', () {
    test('wrap and auth keys differ and are deterministic', () {
      final mk = CryptoService.deriveMasterKey('pw', CryptoService.generateSalt());
      final wrap = CryptoService.wrapKey(mk);
      final auth = CryptoService.authKey(mk);
      expect(wrap, isNot(equals(auth)));
      expect(wrap, equals(CryptoService.wrapKey(mk)));
      expect(wrap.length, 32);
      expect(auth.length, 32);
    });
  });

  group('DEK wrapping', () {
    test('round-trips with the correct wrap key', () {
      final wrap = CryptoService.randomBytes(32);
      final dek = CryptoService.generateDek();
      final wrapped = CryptoService.wrapDek(wrap, dek);
      expect(CryptoService.unwrapDek(wrap, wrapped), equals(dek));
    });

    test('fails authentication with the wrong wrap key', () {
      final dek = CryptoService.generateDek();
      final wrapped = CryptoService.wrapDek(CryptoService.randomBytes(32), dek);
      expect(
        () => CryptoService.unwrapDek(CryptoService.randomBytes(32), wrapped),
        throwsA(anything),
      );
    });
  });

  group('Payload encryption with padding', () {
    final dek = CryptoService.generateDek();

    test('round-trips across sizes', () {
      for (final s in ['', 'hi', 'x' * 300, 'y' * 5000]) {
        final pt = Uint8List.fromList(utf8.encode(s));
        final blob = CryptoService.encryptPayload(dek, pt);
        expect(CryptoService.decryptPayload(dek, blob), equals(pt));
      }
    });

    test('pads to size buckets to hide exact length', () {
      expect(CryptoService.paddedSize(0), 256);
      expect(CryptoService.paddedSize(1), 256);
      expect(CryptoService.paddedSize(300), 512);
      expect(CryptoService.paddedSize(5000), 8192);

      // Two short notes of different real lengths produce equal ciphertext.
      final a = CryptoService.encryptPayload(
          dek, Uint8List.fromList(utf8.encode('a')));
      final b = CryptoService.encryptPayload(
          dek, Uint8List.fromList(utf8.encode('a far longer note, still small')));
      expect(a.length, equals(b.length));
    });

    test('a tampered blob fails to decrypt', () {
      final blob = CryptoService.encryptPayload(
          dek, Uint8List.fromList(utf8.encode('secret')));
      blob[blob.length - 1] ^= 0xff; // flip a tag bit
      expect(() => CryptoService.decryptPayload(dek, blob), throwsA(anything));
    });
  });

  group('Legacy migration helpers', () {
    test('PBKDF2 derivation + hash are deterministic', () {
      final salt = CryptoService.generateSalt();
      final k1 = CryptoService.legacyDeriveKey('pw', salt);
      final k2 = CryptoService.legacyDeriveKey('pw', salt);
      expect(k1, equals(k2));
      expect(CryptoService.legacyHashKey(k1),
          equals(CryptoService.legacyHashKey(k2)));
      expect(CryptoService.legacyHashKey(k1),
          isNot(equals(CryptoService.legacyHashKey(CryptoService.randomBytes(32)))));
    });
  });
}
