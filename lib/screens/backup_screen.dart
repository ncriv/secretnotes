import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/sync_provider.dart';
import '../services/backup_service.dart';

/// Export notes to a file the user controls (via the system share sheet) and
/// restore from one (via the file picker) — the mobile-native way around the
/// app sandbox having no user-visible filesystem.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  String _stamp() =>
      DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;

  Future<void> _shareDocument(String content, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    await Share.shareXFiles([XFile(file.path)], subject: 'SecretNotes backup');
  }

  Future<void> _exportEncrypted() async {
    final auth = context.read<AuthProvider>();
    final notes = context.read<NotesProvider>().notes;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final env = await auth.envelope();
      final dek = auth.dek;
      if (env == null || dek == null) {
        throw BackupException('Vault is locked.');
      }
      final content = BackupService.exportEncrypted(
        kdfSaltB64: env.saltB64,
        kdfParamsJson: env.paramsJson,
        wrappedDekB64: env.wrappedDekB64,
        dek: dek,
        notes: notes,
        timestamp: DateTime.now().toIso8601String(),
      );
      await _shareDocument(content, 'secretnotes-${_stamp()}.encrypted.json');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_clean(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPlaintext() async {
    final notes = context.read<NotesProvider>().notes;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export unencrypted?'),
        content: const Text(
          'This writes your notes as plain, readable text with no encryption. '
          'Anyone who gets the file can read them. Only save it somewhere you '
          'trust, and delete it when done.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Export anyway',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final content = BackupService.exportPlaintext(
        notes,
        timestamp: DateTime.now().toIso8601String(),
      );
      await _shareDocument(content, 'secretnotes-${_stamp()}.plaintext.json');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_clean(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final notesProvider = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;

    setState(() => _busy = true);
    try {
      final file = picked.files.single;
      final content = file.bytes != null
          ? String.fromCharCodes(file.bytes!)
          : await File(file.path!).readAsString();

      String? password;
      if (BackupService.isEncrypted(content)) {
        password = await _askPassword();
        if (password == null) {
          setState(() => _busy = false);
          return; // cancelled
        }
      }

      final notes = BackupService.restore(content, password: password);
      final count = await notesProvider.importNotes(notes);
      if (sync.configured && sync.sessionActive) sync.sync();
      messenger.showSnackBar(
        SnackBar(content: Text('Imported $count note${count == 1 ? '' : 's'}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_clean(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Master password for this backup',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  String _clean(Object e) => e
      .toString()
      .replaceFirst('BackupException: ', '')
      .replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Save a copy of your notes to a file you control — your cloud '
              'drive, Files, or email to yourself. Encrypted backups can be '
              'restored on any device with your master password.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _exportEncrypted,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Export encrypted backup'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _exportPlaintext,
              icon: const Icon(Icons.warning_amber_outlined),
              label: const Text('Export plaintext (unencrypted)'),
            ),
            const Divider(height: 40),
            OutlinedButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import / restore from file'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Importing merges notes into this device by id and re-syncs if '
              'sync is on.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
