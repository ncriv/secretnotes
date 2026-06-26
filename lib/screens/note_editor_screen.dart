import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../providers/notes_provider.dart';

class NoteEditorScreen extends StatefulWidget {
  final String? noteId;

  const NoteEditorScreen({super.key, this.noteId});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleController;
  late QuillController _quillController;
  bool _isNewNote = true;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();

    final notesProvider = context.read<NotesProvider>();

    if (widget.noteId != null) {
      final note = notesProvider.getNote(widget.noteId!);
      if (note != null) {
        _isNewNote = false;
        _titleController.text = note.title;
        try {
          final delta = Delta.fromJson(jsonDecode(note.contentJson) as List);
          _quillController = QuillController(
            document: Document.fromDelta(delta),
            selection: const TextSelection.collapsed(offset: 0),
          );
        } catch (_) {
          _quillController = QuillController.basic();
        }
      } else {
        _quillController = QuillController.basic();
      }
    } else {
      _quillController = QuillController.basic();
    }

    _titleController.addListener(_markChanged);
    _quillController.addListener(_markChanged);
  }

  void _markChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _save() async {
    final title = _titleController.text;
    final contentJson =
        jsonEncode(_quillController.document.toDelta().toJson());
    final notesProvider = context.read<NotesProvider>();

    if (_isNewNote) {
      // Don't save completely empty notes
      final plainText = _quillController.document.toPlainText().trim();
      if (title.isEmpty && plainText.isEmpty) return;
      await notesProvider.addNote(title: title, contentJson: contentJson);
    } else {
      await notesProvider.updateNote(
        widget.noteId!,
        title: title,
        contentJson: contentJson,
      );
    }
  }

  Future<void> _delete() async {
    if (widget.noteId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Are you sure you want to delete this note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<NotesProvider>().deleteNote(widget.noteId!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && _hasChanges) {
          await _save();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNewNote ? 'New Note' : 'Edit Note'),
          actions: [
            if (!_isNewNote)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: _delete,
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _titleController,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  border: InputBorder.none,
                  filled: false,
                ),
                maxLines: 1,
              ),
            ),
            const Divider(height: 1),
            QuillSimpleToolbar(
              controller: _quillController,
              config: QuillSimpleToolbarConfig(
                showAlignmentButtons: false,
                showBackgroundColorButton: false,
                showCenterAlignment: false,
                showCodeBlock: false,
                showColorButton: false,
                showDirection: false,
                showFontFamily: false,
                showFontSize: false,
                showIndent: false,
                showInlineCode: false,
                showJustifyAlignment: false,
                showLeftAlignment: false,
                showLink: false,
                showQuote: false,
                showRightAlignment: false,
                showSearchButton: false,
                showSubscript: false,
                showSuperscript: false,
                multiRowsDisplay: false,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: QuillEditor.basic(
                  controller: _quillController,
                  config: const QuillEditorConfig(
                    placeholder: 'Start writing...',
                    padding: EdgeInsets.fromLTRB(0, 12, 0, 300),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
