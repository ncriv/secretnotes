import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../services/storage_service.dart';
import '../utils/color_utils.dart';

class NotesProvider extends ChangeNotifier {
  final StorageService _storage = StorageService.instance;
  final Uuid _uuid = const Uuid();

  List<Note> _notes = [];
  bool _isInitialized = false;

  List<Note> get notes => _notes;
  bool get isInitialized => _isInitialized;

  Future<void> init(Uint8List dek) async {
    await _storage.open(dek);
    _loadNotes();
    _isInitialized = true;
    notifyListeners();
  }

  void _loadNotes() {
    _notes = _storage.getAllNotes();
  }

  /// Re-read from the vault (e.g. after a sync changed records underneath us).
  void reload() {
    _loadNotes();
    notifyListeners();
  }

  Future<Note> addNote({
    String title = '',
    String contentJson = '[{"insert":"\\n"}]',
  }) async {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: title,
      contentJson: contentJson,
      colorIndex: _storage.noteCount % noteColors.length,
      createdAt: now,
      updatedAt: now,
    );
    await _storage.upsertNote(note);
    _loadNotes();
    notifyListeners();
    return note;
  }

  Future<void> updateNote(String id, {String? title, String? contentJson}) async {
    final note = _storage.getNote(id);
    if (note == null) return;

    if (title != null) note.title = title;
    if (contentJson != null) note.contentJson = contentJson;
    note.updatedAt = DateTime.now();
    await _storage.upsertNote(note);
    _loadNotes();
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    await _storage.deleteNote(id);
    _loadNotes();
    notifyListeners();
  }

  Note? getNote(String id) => _storage.getNote(id);

  Future<void> close() async {
    await _storage.close();
    _notes = [];
    _isInitialized = false;
  }
}
