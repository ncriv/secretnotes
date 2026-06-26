import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:secretnotes/models/note.dart';
import 'package:secretnotes/services/backup_service.dart';
import 'package:secretnotes/services/crypto_service.dart';

Note _note(String id, String title, String body) => Note(
      id: id,
      title: title,
      contentJson: '[{"insert":"$body\\n"}]',
      colorIndex: 2,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000900000),
    );

void _expectSame(List<Note> a, List<Note> b) {
  expect(b.length, a.length);
  for (final original in a) {
    final m = b.firstWhere((n) => n.id == original.id);
    expect(m.title, original.title);
    expect(m.contentJson, original.contentJson);
    expect(m.colorIndex, original.colorIndex);
    expect(m.createdAt, original.createdAt);
    expect(m.updatedAt, original.updatedAt);
  }
}

void main() {
  final notes = [
    _note('a', 'First', 'hello'),
    _note('b', '', 'no title'),
  ];

  test('plaintext export round-trips', () {
    final doc = BackupService.exportPlaintext(notes);
    expect(BackupService.isEncrypted(doc), isFalse);
    _expectSame(notes, BackupService.restore(doc));
  });

  group('encrypted backup', () {
    const password = 'correct horse battery staple';
    late String doc;

    setUp(() {
      final salt = CryptoService.generateSalt();
      final params = {
        'm': CryptoService.kdfMemoryKib,
        't': CryptoService.kdfIterations,
        'p': CryptoService.kdfLanes,
      };
      final masterKey = CryptoService.deriveMasterKey(password, salt);
      final dek = CryptoService.generateDek();
      final wrapped =
          CryptoService.wrapDek(CryptoService.wrapKey(masterKey), dek);
      doc = BackupService.exportEncrypted(
        kdfSaltB64: base64Encode(salt),
        kdfParamsJson: jsonEncode(params),
        wrappedDekB64: base64Encode(wrapped),
        dek: dek,
        notes: notes,
      );
    });

    test('is marked encrypted and reveals no plaintext', () {
      expect(BackupService.isEncrypted(doc), isTrue);
      expect(doc.contains('hello'), isFalse);
      expect(doc.contains('First'), isFalse);
    });

    test('restores with the correct password', () {
      _expectSame(notes, BackupService.restore(doc, password: password));
    });

    test('rejects the wrong password', () {
      expect(
        () => BackupService.restore(doc, password: 'nope'),
        throwsA(isA<BackupException>()),
      );
    });

    test('requires a password', () {
      expect(
        () => BackupService.restore(doc),
        throwsA(isA<BackupNeedsPassword>()),
      );
    });
  });

  test('rejects a non-backup file', () {
    expect(
      () => BackupService.restore('{"hello":"world"}'),
      throwsA(isA<BackupException>()),
    );
  });
}
