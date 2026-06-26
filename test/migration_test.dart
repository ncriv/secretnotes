import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:secretnotes/models/note.dart';
import 'package:secretnotes/models/note_record.dart';
import 'package:secretnotes/services/crypto_service.dart';
import 'package:secretnotes/services/storage_service.dart';

/// Exercises the pre-sync → envelope migration against a *real* encrypted Hive
/// box, which is the destructive path that unit-level crypto tests don't cover.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sn_migration');
    Hive.init(dir.path);
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(NoteAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(NoteRecordAdapter());
  });

  tearDown(() async {
    await StorageService.instance.close();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Note note(String id, String title, String body) => Note(
        id: id,
        title: title,
        contentJson: '[{"insert":"$body\\n"}]',
        colorIndex: id.hashCode % 5,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000500000),
      );

  Future<void> seedLegacyBox(Uint8List oldKey, List<Note> notes) async {
    final box = await Hive.openBox<Note>(
      'notes',
      encryptionCipher: HiveAesCipher(oldKey),
    );
    for (final n in notes) {
      await box.put(n.id, n);
    }
    await box.close();
  }

  void expectSame(Note a, Note b) {
    expect(b.id, a.id);
    expect(b.title, a.title);
    expect(b.contentJson, a.contentJson);
    expect(b.colorIndex, a.colorIndex);
    expect(b.createdAt, a.createdAt);
    expect(b.updatedAt, a.updatedAt);
  }

  test('migrates every note intact and keeps the original as a backup',
      () async {
    final oldKey = CryptoService.generateDek();
    final dek = CryptoService.generateDek();
    final originals = [
      note('a', 'Grocery list', 'milk and eggs'),
      note('b', 'Passwords', 'do not store these here'),
      note('c', '', 'untitled thoughts'),
    ];
    await seedLegacyBox(oldKey, originals);

    await StorageService.instance.open(dek);
    final count =
        await StorageService.instance.migrateLegacyVault(oldKey, dek);

    expect(count, originals.length);

    // Every note is present and decrypts identically through the new vault.
    final migrated = StorageService.instance.getAllNotes();
    expect(migrated.length, originals.length);
    for (final original in originals) {
      final match = migrated.firstWhere((n) => n.id == original.id);
      expectSame(original, match);
    }

    // The original box is kept as a backup (not deleted).
    expect(await StorageService.hasLegacyVault(), isTrue);

    // Migrated records are dirty so they upload on the first sync.
    expect(StorageService.instance.dirtyRecords().length, originals.length);
  });

  test('is idempotent — re-running produces no duplicates or loss', () async {
    final oldKey = CryptoService.generateDek();
    final dek = CryptoService.generateDek();
    final originals = [note('a', 'One', 'first'), note('b', 'Two', 'second')];
    await seedLegacyBox(oldKey, originals);

    await StorageService.instance.open(dek);
    await StorageService.instance.migrateLegacyVault(oldKey, dek);
    final second =
        await StorageService.instance.migrateLegacyVault(oldKey, dek);

    expect(second, originals.length);
    expect(StorageService.instance.getAllNotes().length, originals.length);
  });

  test('deleteLegacyBackup removes the backup box', () async {
    final oldKey = CryptoService.generateDek();
    final dek = CryptoService.generateDek();
    await seedLegacyBox(oldKey, [note('a', 'Keep', 'then drop')]);

    await StorageService.instance.open(dek);
    await StorageService.instance.migrateLegacyVault(oldKey, dek);
    expect(await StorageService.hasLegacyVault(), isTrue);

    await StorageService.deleteLegacyBackup();
    expect(await StorageService.hasLegacyVault(), isFalse);
    // Notes remain in the vault after the backup is gone.
    expect(StorageService.instance.getAllNotes().length, 1);
  });

  test('migrating an empty/absent legacy box is a no-op', () async {
    final dek = CryptoService.generateDek();
    await StorageService.instance.open(dek);
    final count = await StorageService.instance
        .migrateLegacyVault(CryptoService.generateDek(), dek);
    expect(count, 0);
    expect(StorageService.instance.getAllNotes(), isEmpty);
  });
}
