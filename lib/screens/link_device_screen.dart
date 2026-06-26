import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/sync_provider.dart';

/// First-launch flow for a device joining an existing account: re-derive the
/// keys from the password, fetch the wrapped DEK, and adopt the session.
class LinkDeviceScreen extends StatefulWidget {
  const LinkDeviceScreen({super.key});

  @override
  State<LinkDeviceScreen> createState() => _LinkDeviceScreenState();
}

class _LinkDeviceScreenState extends State<LinkDeviceScreen> {
  final _url = TextEditingController(text: 'https://');
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_url.text.isEmpty || _username.text.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'All fields are required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final sync = context.read<SyncProvider>();
    final auth = context.read<AuthProvider>();
    try {
      final result = await sync.linkDevice(
        url: _url.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      );
      auth.adoptSession(result.dek, result.authKey);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not link: ${_clean(e)}';
      });
    }
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('SyncException(-): ', '').replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link existing account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter your sync server and the master password for your '
              'account. Your notes will be downloaded and decrypted on this '
              'device — the password never leaves it.',
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
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Master password',
                prefixIcon: Icon(Icons.key),
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
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Link device'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
