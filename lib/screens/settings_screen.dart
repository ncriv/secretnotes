import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/sync_provider.dart';
import 'lock_screen.dart';
import 'sync_settings_screen.dart';

/// App configuration. Sync is presented as an explicitly optional feature —
/// the app is fully usable offline and never contacts a server unless the user
/// sets one up here.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _lock(BuildContext context) {
    context.read<SyncProvider>().detach();
    context.read<NotesProvider>().close();
    context.read<AuthProvider>().lock();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LockScreen()),
      (_) => false,
    );
  }

  Future<void> _toggleBiometric(BuildContext context, bool enable) async {
    final auth = context.read<AuthProvider>();
    if (enable) {
      await auth.enableBiometric();
    } else {
      await auth.disableBiometric();
    }
  }

  String _syncSubtitle(SyncProvider sync) {
    if (!sync.configured) return 'Off · notes stay on this device';
    final host = Uri.tryParse(sync.serverUrl ?? '')?.host ?? sync.serverUrl;
    final where = '${sync.username ?? '?'} · $host';
    return switch (sync.status) {
      SyncStatus.syncing => '$where · syncing…',
      SyncStatus.error => '$where · ${sync.error ?? 'sync error'}',
      SyncStatus.idle => where,
    };
  }

  (IconData, Color?) _syncIcon(SyncProvider sync) {
    if (!sync.configured) return (Icons.cloud_off_outlined, null);
    return switch (sync.status) {
      SyncStatus.syncing => (Icons.cloud_sync_outlined, Colors.blueGrey),
      SyncStatus.error => (Icons.cloud_off_outlined, Colors.redAccent),
      SyncStatus.idle => (Icons.cloud_done_outlined, Colors.teal),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _sectionHeader(context, 'Sync'),
          Consumer<SyncProvider>(
            builder: (context, sync, _) {
              final (icon, color) = _syncIcon(sync);
              return ListTile(
                leading: Icon(icon, color: color),
                title: const Text('Server sync'),
                subtitle: Text(_syncSubtitle(sync)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SyncSettingsScreen()),
                ),
              );
            },
          ),
          const Divider(),
          _sectionHeader(context, 'Security'),
          Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (!auth.biometricAvailable) {
                return const ListTile(
                  leading: Icon(Icons.fingerprint),
                  title: Text('Biometric unlock'),
                  subtitle: Text('Not available on this device'),
                  enabled: false,
                );
              }
              return SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Biometric unlock'),
                subtitle: const Text('Unlock with fingerprint or face'),
                value: auth.biometricEnabled,
                onChanged: (v) => _toggleBiometric(context, v),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock now'),
            onTap: () => _lock(context),
          ),
          const Divider(),
          _sectionHeader(context, 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About SecretNotes'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'SecretNotes',
              applicationVersion: '1.0.0',
              applicationLegalese:
                  'End-to-end encrypted notes. Notes are encrypted on this '
                  'device; sync, if enabled, only ever stores ciphertext.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.teal,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
      ),
    );
  }
}
