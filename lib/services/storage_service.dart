import 'dart:typed_data';

import 'package:hive/hive.dart';

import '../models/note.dart';

class StorageService {
  Box<Note>? _box;

  bool get isOpen => _box?.isOpen ?? false;

  Future<void> openBox(Uint8List encryptionKey) async {
    if (_box != null && _box!.isOpen) return;
    final cipher = HiveAesCipher(encryptionKey);
    _box = await Hive.openBox<Note>('notes', encryptionCipher: cipher);
  }

  Future<void> closeBox() async {
    await _box?.close();
    _box = null;
  }

  List<Note> getAllNotes() {
    if (_box == null) return [];
    final notes = _box!.values.toList();
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  Note? getNote(String id) {
    if (_box == null) return null;
    return _box!.get(id);
  }

  Future<void> addNote(Note note) async {
    await _box?.put(note.id, note);
  }

  Future<void> updateNote(Note note) async {
    note.updatedAt = DateTime.now();
    await note.save();
  }

  Future<void> deleteNote(String id) async {
    await _box?.delete(id);
  }

  int get noteCount => _box?.length ?? 0;
}
