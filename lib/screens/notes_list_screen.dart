import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../providers/auth_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/sync_provider.dart';
import '../utils/color_utils.dart';
import 'lock_screen.dart';
import 'note_editor_screen.dart';
import 'sync_settings_screen.dart';

class NotesListScreen extends StatelessWidget {
  const NotesListScreen({super.key});

  String _extractPreview(String deltaJson) {
    try {
      final delta = Delta.fromJson(jsonDecode(deltaJson) as List);
      final doc = quill.Document.fromDelta(delta);
      final text = doc.toPlainText().trim();
      if (text.isEmpty) return '';
      final firstLine = text.split('\n').first;
      return firstLine.length > 80 ? firstLine.substring(0, 80) : firstLine;
    } catch (_) {
      return '';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _navigateToEditor(BuildContext context, {String? noteId}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(noteId: noteId),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text(
          'Delete "${note.title.isEmpty ? "Untitled" : note.title}"?',
        ),
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
    if (confirmed == true && context.mounted) {
      context.read<NotesProvider>().deleteNote(note.id);
    }
  }

  void _lock(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final notes = context.read<NotesProvider>();
    context.read<SyncProvider>().detach();
    notes.close();
    auth.lock();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LockScreen()),
      (_) => false,
    );
  }

  void _toggleBiometric(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    if (auth.biometricEnabled) {
      await auth.disableBiometric();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric unlock disabled')),
        );
      }
    } else {
      await auth.enableBiometric();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric unlock enabled')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SecretNotes'),
        actions: [
          Consumer<SyncProvider>(
            builder: (context, sync, _) {
              return IconButton(
                icon: Icon(
                  switch (sync.status) {
                    SyncStatus.syncing => Icons.sync,
                    SyncStatus.error => Icons.cloud_off_outlined,
                    SyncStatus.idle =>
                      sync.configured ? Icons.cloud_done_outlined : Icons.cloud_outlined,
                  },
                  color: sync.status == SyncStatus.error
                      ? Colors.redAccent
                      : (sync.configured ? Colors.teal : null),
                ),
                tooltip: 'Sync',
                onPressed: () {
                  if (sync.configured) sync.sync();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SyncSettingsScreen(),
                    ),
                  );
                },
              );
            },
          ),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (!auth.biometricAvailable) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(
                  auth.biometricEnabled
                      ? Icons.fingerprint
                      : Icons.fingerprint_outlined,
                  color: auth.biometricEnabled ? Colors.teal : null,
                ),
                tooltip: auth.biometricEnabled
                    ? 'Disable biometric'
                    : 'Enable biometric',
                onPressed: () => _toggleBiometric(context),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock',
            onPressed: () => _lock(context),
          ),
        ],
      ),
      body: Consumer<NotesProvider>(
        builder: (context, notesProvider, _) {
          final notes = notesProvider.notes;
          if (notes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.note_add_outlined,
                      size: 80, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  Text(
                    'No notes yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to create your first note',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(8),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                final color = getNoteColor(note.colorIndex);
                final preview = _extractPreview(note.contentJson);
                return GestureDetector(
                  onTap: () => _navigateToEditor(context, noteId: note.id),
                  onLongPress: () => _confirmDelete(context, note),
                  child: Card(
                    color: color.withValues(alpha: 0.85),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.title.isEmpty ? 'Untitled' : note.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              preview,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                              overflow: TextOverflow.fade,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(note.updatedAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToEditor(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
