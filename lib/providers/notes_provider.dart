import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import '../services/storage_service.dart';
import '../utils/color_utils.dart';

class NotesProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final Uuid _uuid = const Uuid();

  List<Note> _notes = [];
  bool _isInitialized = false;

  List<Note> get notes => _notes;
  bool get isInitialized => _isInitialized;

  Future<void> init(Uint8List encryptionKey) async {
    await _storageService.openBox(encryptionKey);
    _loadNotes();
    _isInitialized = true;
    notifyListeners();
  }

  void _loadNotes() {
    _notes = _storageService.getAllNotes();
  }

  Future<Note> addNote({String title = '', String contentJson = '[{"insert":"\\n"}]'}) async {
    final note = Note(
      id: _uuid.v4(),
      title: title,
      contentJson: contentJson,
      colorIndex: _storageService.noteCount % noteColors.length,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _storageService.addNote(note);
    _loadNotes();
    notifyListeners();
    return note;
  }

  Future<void> updateNote(String id, {String? title, String? contentJson}) async {
    final note = _storageService.getNote(id);
    if (note == null) return;

    if (title != null) note.title = title;
    if (contentJson != null) note.contentJson = contentJson;
    await _storageService.updateNote(note);
    _loadNotes();
    notifyListeners();
  }

  Future<void> deleteNote(String id) async {
    await _storageService.deleteNote(id);
    _loadNotes();
    notifyListeners();
  }

  Note? getNote(String id) => _storageService.getNote(id);

  Future<void> close() async {
    await _storageService.closeBox();
    _notes = [];
    _isInitialized = false;
  }
}
