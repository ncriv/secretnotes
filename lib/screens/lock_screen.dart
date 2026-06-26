import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/notes_provider.dart';
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
    if (auth.encryptionKey == null) return;
    final notesProvider = context.read<NotesProvider>();
    await notesProvider.init(auth.encryptionKey!);
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NotesListScreen()),
      );
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
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
