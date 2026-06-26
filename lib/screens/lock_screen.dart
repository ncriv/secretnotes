import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/sync_provider.dart';
import '../services/storage_service.dart';
import 'link_device_screen.dart';
import 'notes_list_screen.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _biometricAutoTried = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    auth.addListener(_maybeAutoBiometric);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoBiometric();
    });
  }

  void _maybeAutoBiometric() {
    if (_biometricAutoTried) return;
    final auth = context.read<AuthProvider>();
    if (auth.isFirstLaunch) return;
    if (auth.biometricAvailable && auth.biometricEnabled) {
      _biometricAutoTried = true;
      _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    final auth = context.read<AuthProvider>();
    if (auth.biometricAvailable && auth.biometricEnabled) {
      final success = await auth.biometricLogin();
      if (success && mounted) {
        await _openNotes(auth);
      }
    }
  }

  Future<void> _openNotes(AuthProvider auth) async {
    final dek = auth.dek;
    if (dek == null) return;
    final notesProvider = context.read<NotesProvider>();
    final sync = context.read<SyncProvider>();

    await notesProvider.init(dek);

    // One-time migration of a pre-sync vault, if present. This is the only
    // potentially destructive step, so it is verify-then-keep: the original
    // box is preserved as a backup and we only mark the migration done after
    // every note has been confirmed to round-trip.
    final legacyKey = auth.consumeLegacyKey();
    if (legacyKey != null && await StorageService.hasLegacyVault()) {
      try {
        final count =
            await StorageService.instance.migrateLegacyVault(legacyKey, dek);
        await auth.finalizeMigration();
        notesProvider.reload();
        if (mounted && count > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Imported $count note${count == 1 ? '' : 's'} into the '
                'encrypted vault (a backup of the originals is kept).',
              ),
            ),
          );
        }
      } catch (e) {
        // Not finalized → migration retries on next unlock. Originals are safe.
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Migration not completed'),
              content: const Text(
                'Your existing notes could not be fully verified during '
                'upgrade, so nothing was changed or deleted — your original '
                'notes are safe. The app will try again next time you unlock.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    }

    // Bind the session to sync and kick off a background sync if configured.
    sync.onVaultChanged = notesProvider.reload;
    if (auth.authKey != null) sync.attach(auth.authKey!);
    if (sync.configured) sync.sync();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NotesListScreen()),
      );
    }
  }

  Future<void> _linkDevice() async {
    final linked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LinkDeviceScreen()),
    );
    if (linked == true && mounted) {
      await _openNotes(context.read<AuthProvider>());
    }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    final password = _passwordController.text;

    if (password.isEmpty) return;

    if (auth.isFirstLaunch) {
      if (password.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password must be at least 6 characters')),
        );
        return;
      }
      if (password != _confirmController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passwords do not match')),
        );
        return;
      }
      final success = await auth.setupPassword(password);
      if (success && mounted) {
        await _openNotes(auth);
      }
    } else {
      final success = await auth.login(password);
      if (success && mounted) {
        await _openNotes(auth);
      }
    }
  }

  @override
  void dispose() {
    context.read<AuthProvider>().removeListener(_maybeAutoBiometric);
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Consumer<AuthProvider>(
            builder: (context, auth, _) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, size: 80, color: Colors.teal),
                  const SizedBox(height: 16),
                  Text(
                    'SecretNotes',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    auth.isFirstLaunch
                        ? 'Set a master password to get started'
                        : 'Enter your password to unlock',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofocus: true,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () {
                          setState(() => _obscurePassword = !_obscurePassword);
                        },
                      ),
                    ),
                  ),
                  if (auth.isFirstLaunch) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmController,
                      obscureText: _obscureConfirm,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () {
                            setState(
                                () => _obscureConfirm = !_obscureConfirm);
                          },
                        ),
                      ),
                    ),
                  ],
                  if (auth.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      auth.error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: auth.isLoading ? null : _submit,
                      child: auth.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(auth.isFirstLaunch
                              ? 'Set Password'
                              : 'Unlock'),
                    ),
                  ),
                  if (!auth.isFirstLaunch &&
                      auth.biometricAvailable &&
                      auth.biometricEnabled) ...[
                    const SizedBox(height: 16),
                    IconButton(
                      onPressed: auth.isLoading ? null : _tryBiometric,
                      icon: const Icon(Icons.fingerprint, size: 48),
                      color: Colors.teal,
                    ),
                  ],
                  if (auth.isFirstLaunch) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: auth.isLoading ? null : _linkDevice,
                      icon: const Icon(Icons.cloud_sync, size: 18),
                      label: const Text('Link an existing account'),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
