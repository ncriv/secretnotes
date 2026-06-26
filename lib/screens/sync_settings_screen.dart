import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';

/// Manage sync for the unlocked account: register on a server, view status,
/// sync on demand, or disconnect.
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _url = TextEditingController(text: 'https://');
  final _username = TextEditingController();
  final _adminToken = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _adminToken.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_url.text.isEmpty || _username.text.isEmpty || _adminToken.text.isEmpty) {
      setState(() => _error = 'All fields are required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final sync = context.read<SyncProvider>();
    try {
      await sync.registerAccount(
        url: _url.text.trim(),
        username: _username.text.trim(),
        adminToken: _adminToken.text.trim(),
      );
    } catch (e) {
      setState(() => _error = 'Could not enable sync: ${_clean(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _clean(Object e) => e
      .toString()
      .replaceFirst('SyncException(-): ', '')
      .replaceFirst('Exception: ', '');

  Future<void> _confirmDisconnect(SyncProvider sync) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect sync?'),
        content: const Text(
          'This device will stop syncing. Your notes stay on this device, and '
          'the copy on the server is left untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) await sync.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: Consumer<SyncProvider>(
        builder: (context, sync, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: sync.configured
                ? _connectedView(sync)
                : _setupView(sync),
          );
        },
      ),
    );
  }

  Widget _connectedView(SyncProvider sync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_done_outlined, color: Colors.teal),
            title: Text(sync.username ?? ''),
            subtitle: Text(sync.serverUrl ?? ''),
          ),
        ),
        const SizedBox(height: 8),
        _statusLine(sync),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: sync.status == SyncStatus.syncing ? null : () => sync.sync(),
          icon: const Icon(Icons.sync),
          label: const Text('Sync now'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _confirmDisconnect(sync),
          icon: const Icon(Icons.link_off),
          label: const Text('Disconnect'),
        ),
      ],
    );
  }

  Widget _statusLine(SyncProvider sync) {
    final (icon, text, color) = switch (sync.status) {
      SyncStatus.syncing => (Icons.sync, 'Syncing…', Colors.blueGrey),
      SyncStatus.error => (Icons.error_outline, sync.error ?? 'Sync error', Colors.redAccent),
      SyncStatus.idle => (
          Icons.check_circle_outline,
          sync.lastSyncedAt == null ? 'Not synced yet' : 'Up to date',
          Colors.teal,
        ),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ],
    );
  }

  Widget _setupView(SyncProvider sync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Create an account on your sync server. Notes are encrypted on this '
          'device before upload — the server only ever stores ciphertext. You '
          'need the server\'s admin token to register.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            prefixIcon: Icon(Icons.dns_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _username,
          decoration: const InputDecoration(
            labelText: 'Username',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _adminToken,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Admin token',
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.redAccent)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: _busy ? null : _register,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enable sync'),
          ),
        ),
      ],
    );
  }
}
