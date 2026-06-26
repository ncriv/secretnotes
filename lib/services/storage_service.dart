import 'dart:typed_data';

import 'package:hive/hive.dart';

import '../models/note.dart';
import '../models/note_codec.dart';
import '../models/note_record.dart';
import 'crypto_service.dart';

/// Thrown when the legacy migration cannot verify that every note copied
/// across intact. The original `notes` box is never deleted, so the user's
/// data is safe to retry.
class MigrationException implements Exception {
  final String message;
  MigrationException(this.message);
  @override
  String toString() => 'MigrationException: $message';
}

/// Local vault. Notes are stored as [NoteRecord]s whose `blob` is the
/// per-note AES-256-GCM ciphertext. The Hive box itself is additionally
/// encrypted with the DEK for defense-in-depth at rest, so even the sync
/// metadata is protected on disk.
class StorageService {
  static const String _vaultBox = 'vault';
  static const String _legacyBox = 'notes';

  /// Single shared vault so the notes and sync providers see the same box.
  StorageService._();
  static final StorageService instance = StorageService._();

  Box<NoteRecord>? _box;
  Uint8List? _dek;

  bool get isOpen => _box?.isOpen ?? false;

  Future<void> open(Uint8List dek) async {
    if (_box != null && _box!.isOpen) return;
    _dek = dek;
    _box = await Hive.openBox<NoteRecord>(
      _vaultBox,
      encryptionCipher: HiveAesCipher(dek),
    );
  }

  Future<void> close() async {
    await _box?.close();
    _box = null;
    _dek = null;
  }

  Box<NoteRecord> get _vault {
    final box = _box;
    if (box == null) throw StateError('vault not open');
    return box;
  }

  // --- Plaintext note access ------------------------------------------------

  List<Note> getAllNotes() {
    if (_box == null) return [];
    final notes = <Note>[];
    for (final record in _vault.values) {
      if (record.deleted) continue;
      final note = _decode(record);
      if (note != null) notes.add(note);
    }
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  Note? getNote(String id) {
    final record = _box?.get(id);
    if (record == null || record.deleted) return null;
    return _decode(record);
  }

  Note? _decode(NoteRecord record) {
    if (record.blob.isEmpty) return null;
    try {
      return NoteCodec.decode(CryptoService.decryptPayload(_dek!, record.blob));
    } catch (_) {
      // Corrupt or undecryptable record — skip rather than crash the list.
      return null;
    }
  }

  /// Decrypt a record to its plaintext note (null if a tombstone/corrupt).
  Note? decryptRecord(NoteRecord record) => _decode(record);

  /// Encrypt and store a note, flagging it dirty for the next sync.
  Future<void> upsertNote(Note note) async {
    final existing = _vault.get(note.id);
    final blob = CryptoService.encryptPayload(_dek!, NoteCodec.encode(note));
    await _vault.put(
      note.id,
      NoteRecord(
        id: note.id,
        blob: blob,
        rev: existing?.rev ?? 0,
        dirty: true,
        deleted: false,
        updatedAt: note.updatedAt,
      ),
    );
  }

  /// Delete a note. If it was never synced we drop it outright; otherwise we
  /// leave a dirty tombstone so the delete propagates to other devices.
  Future<void> deleteNote(String id) async {
    final existing = _vault.get(id);
    if (existing == null) return;
    if (existing.rev == 0) {
      await _vault.delete(id);
      return;
    }
    await _vault.put(
      id,
      NoteRecord(
        id: id,
        blob: Uint8List(0),
        rev: existing.rev,
        dirty: true,
        deleted: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  int get noteCount {
    if (_box == null) return 0;
    return _vault.values.where((r) => !r.deleted).length;
  }

  // --- Raw record access for the sync engine --------------------------------

  Iterable<NoteRecord> allRecords() => _box?.values ?? const [];

  List<NoteRecord> dirtyRecords() =>
      _vault.values.where((r) => r.dirty).toList();

  NoteRecord? rawRecord(String id) => _box?.get(id);

  Future<void> putRecord(NoteRecord record) => _vault.put(record.id, record);

  Future<void> hardDelete(String id) => _vault.delete(id);

  /// Store a server version verbatim as a clean (synced) record.
  Future<void> applyRemote({
    required String id,
    required Uint8List blob,
    required int rev,
    required bool deleted,
    required int updatedAtMs,
  }) {
    return _vault.put(
      id,
      NoteRecord(
        id: id,
        blob: blob,
        rev: rev,
        dirty: false,
        deleted: deleted,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      ),
    );
  }

  /// Mark a pushed record as synced at [rev], clearing its dirty flag.
  Future<void> markSynced(String id, int rev) async {
    final r = _vault.get(id);
    if (r == null) return;
    r.rev = rev;
    r.dirty = false;
    await _vault.put(id, r);
  }

  /// Preserve a losing local edit as a brand-new dirty note (so neither side of
  /// a conflict is lost). Must be called before the original id is overwritten.
  Future<void> saveConflictCopy(String sourceId, String newId) async {
    final r = _vault.get(sourceId);
    if (r == null) return;
    final note = _decode(r);
    if (note == null) return;
    final now = DateTime.now();
    await upsertNote(
      Note(
        id: newId,
        title: note.title.isEmpty
            ? 'Conflicted copy'
            : '${note.title} (conflict)',
        contentJson: note.contentJson,
        colorIndex: note.colorIndex,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  // --- Legacy migration -----------------------------------------------------

  /// One-time migration of the pre-sync, box-level-encrypted `notes` box into
  /// per-note records. Returns the number of notes imported (0 if there was
  /// nothing to migrate). Imported records are marked dirty so they upload on
  /// the first sync.
  ///
  /// Safety contract — this never destroys the only copy of your notes:
  ///   1. every note is copied into the vault, then
  ///   2. every note is read back and decrypted to confirm it round-trips
  ///      identically, and only if that fully succeeds does the migration
  ///      report success. On any mismatch it throws [MigrationException].
  /// The original `notes` box is **kept on disk as a backup** either way (the
  /// caller records completion via a flag; see [deleteLegacyBackup] to remove
  /// the backup once you're confident).
  Future<int> migrateLegacyVault(Uint8List oldKey, Uint8List dek) async {
    if (!await Hive.boxExists(_legacyBox)) return 0;

    final legacy = await Hive.openBox<Note>(
      _legacyBox,
      encryptionCipher: HiveAesCipher(oldKey),
    );
    try {
      final originals = legacy.values.toList();

      // 1. Copy (idempotent by id, so a re-run after an interruption is safe).
      for (final note in originals) {
        final blob = CryptoService.encryptPayload(dek, NoteCodec.encode(note));
        await _vault.put(
          note.id,
          NoteRecord(
            id: note.id,
            blob: blob,
            rev: 0,
            dirty: true,
            deleted: false,
            updatedAt: note.updatedAt,
          ),
        );
      }

      // 2. Verify every original survived the round-trip before we trust it.
      for (final note in originals) {
        final record = _vault.get(note.id);
        if (record == null) {
          throw MigrationException(
            'note "${note.id}" missing from the vault after copy',
          );
        }
        final restored = _decode(record);
        if (restored == null || !_sameNote(note, restored)) {
          throw MigrationException(
            'note "${note.id}" did not round-trip; original left untouched',
          );
        }
      }

      return originals.length;
    } finally {
      // Keep the box file on disk as a backup; just release the handle.
      await legacy.close();
    }
  }

  static bool _sameNote(Note a, Note b) =>
      a.id == b.id &&
      a.title == b.title &&
      a.contentJson == b.contentJson &&
      a.colorIndex == b.colorIndex &&
      a.createdAt.millisecondsSinceEpoch == b.createdAt.millisecondsSinceEpoch &&
      a.updatedAt.millisecondsSinceEpoch == b.updatedAt.millisecondsSinceEpoch;

  static Future<bool> hasLegacyVault() => Hive.boxExists(_legacyBox);

  /// Permanently delete the pre-sync backup box. Call only after the user
  /// confirms their notes migrated correctly.
  static Future<void> deleteLegacyBackup() async {
    if (await Hive.boxExists(_legacyBox)) {
      await Hive.deleteBoxFromDisk(_legacyBox);
    }
  }
}
