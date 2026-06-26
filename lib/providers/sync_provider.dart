import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../services/auth_service.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';

enum SyncStatus { idle, syncing, error }

/// Result of linking a device to an existing account: the recovered session
/// keys the caller uses to unlock locally.
class LinkResult {
  final Uint8List dek;
  final Uint8List authKey;
  LinkResult(this.dek, this.authKey);
}

/// Owns all server interaction: account setup, device linking, and the
/// push/pull sync loop with conflict resolution.
class SyncProvider extends ChangeNotifier {
  final FlutterSecureStorage _store = const FlutterSecureStorage();
  final AuthService _auth = AuthService();
  final StorageService _vault = StorageService.instance;
  final Uuid _uuid = const Uuid();

  static const _kUrl = 'sync_url';
  static const _kUser = 'sync_username';
  static const _kToken = 'sync_token';
  static const _kCursor = 'sync_cursor';

  String? _url;
  String? _username;
  String? _token;
  int _cursor = 0;

  SyncStatus _status = SyncStatus.idle;
  String? _error;
  DateTime? _lastSyncedAt;

  // Live session keys (present only while unlocked).
  Uint8List? _authKey;

  String? get serverUrl => _url;
  String? get username => _username;
  bool get configured => _url != null && _token != null;
  bool get sessionActive => _authKey != null;
  SyncStatus get status => _status;
  String? get error => _error;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Load persisted sync configuration at startup.
  Future<void> load() async {
    _url = await _store.read(key: _kUrl);
    _username = await _store.read(key: _kUser);
    _token = await _store.read(key: _kToken);
    _cursor = int.tryParse(await _store.read(key: _kCursor) ?? '') ?? 0;
    notifyListeners();
  }

  /// Bind the unlocked session keys so sync/register can run.
  void attach(Uint8List authKey) {
    _authKey = authKey;
    notifyListeners();
  }

  void detach() {
    _authKey = null;
    _status = SyncStatus.idle;
    notifyListeners();
  }

  Future<void> _setCursor(int value) async {
    _cursor = value;
    await _store.write(key: _kCursor, value: '$value');
  }

  Future<void> _persistConfig(String url, String username, String token) async {
    _url = url;
    _username = username;
    _token = token;
    await _store.write(key: _kUrl, value: url);
    await _store.write(key: _kUser, value: username);
    await _store.write(key: _kToken, value: token);
  }

  // --- Account setup --------------------------------------------------------

  /// Register the current (unlocked) account on a server. The wrapped DEK and
  /// KDF parameters come from the local envelope; the server never sees keys.
  Future<void> registerAccount({
    required String url,
    required String username,
    required String adminToken,
  }) async {
    final authKey = _authKey;
    final envelope = await _auth.envelope();
    if (authKey == null || envelope == null) {
      throw SyncException('unlock the app before enabling sync');
    }
    final client = SyncClient(url);
    try {
      final token = await client.register(
        adminToken: adminToken,
        username: username,
        authKey: authKey,
        kdfSaltB64: envelope.saltB64,
        kdfParamsJson: envelope.paramsJson,
        wrappedDekB64: envelope.wrappedDekB64,
      );
      await _persistConfig(url, username, token);
      await _setCursor(0);
    } finally {
      client.close();
    }
    notifyListeners();
    await sync();
  }

  /// Link this device to an existing account: re-derive the keys from the
  /// password, fetch the wrapped DEK, and install the envelope locally.
  Future<LinkResult> linkDevice({
    required String url,
    required String username,
    required String password,
  }) async {
    final client = SyncClient(url);
    try {
      final pre = await client.prelogin(username);
      final params = (jsonDecode(pre.kdfParamsJson) as Map).cast<String, dynamic>();
      final masterKey = CryptoService.deriveMasterKey(
        password,
        base64Decode(pre.kdfSaltB64),
        memoryKib: params['m'] as int,
        iterations: params['t'] as int,
        lanes: params['p'] as int,
      );
      final authKey = CryptoService.authKey(masterKey);
      final login = await client.login(username, authKey);

      final dek = CryptoService.unwrapDek(
        CryptoService.wrapKey(masterKey),
        base64Decode(login.wrappedDekB64),
      );

      await _auth.installEnvelope(
        saltB64: pre.kdfSaltB64,
        paramsJson: pre.kdfParamsJson,
        wrappedDekB64: login.wrappedDekB64,
      );
      await _persistConfig(url, username, login.token);
      await _setCursor(0);

      return LinkResult(dek, authKey);
    } finally {
      client.close();
    }
  }

  /// Forget the server association (keeps local notes).
  Future<void> disconnect() async {
    await _store.delete(key: _kUrl);
    await _store.delete(key: _kUser);
    await _store.delete(key: _kToken);
    await _store.delete(key: _kCursor);
    _url = _username = _token = null;
    _cursor = 0;
    notifyListeners();
  }

  // --- The sync loop --------------------------------------------------------

  /// Called after a successful sync so the notes list can refresh.
  VoidCallback? onVaultChanged;

  bool _syncing = false;

  Future<void> sync() async {
    if (!configured || !sessionActive || _syncing) return;
    _syncing = true;
    _status = SyncStatus.syncing;
    _error = null;
    notifyListeners();

    final client = SyncClient(_url!);
    try {
      await _pull(client);
      await _push(client);
      _lastSyncedAt = DateTime.now();
      _status = SyncStatus.idle;
      onVaultChanged?.call();
    } on SyncException catch (e) {
      _status = SyncStatus.error;
      _error = e.message;
    } catch (e) {
      _status = SyncStatus.error;
      _error = 'sync failed';
    } finally {
      client.close();
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _pull(SyncClient client) async {
    final resp = await client.changes(_token!, _cursor);
    for (final remote in resp.changes) {
      final local = _vault.rawRecord(remote.id);
      switch (decideRemote(local, remote)) {
        case MergeAction.ignore:
          break;
        case MergeAction.insert:
        case MergeAction.overwrite:
          await _vault.applyRemote(
            id: remote.id,
            blob: remote.blob,
            rev: remote.rev,
            deleted: remote.deleted,
            updatedAtMs: remote.updatedAtMs,
          );
          break;
        case MergeAction.keepBoth:
          await _vault.saveConflictCopy(remote.id, _uuid.v4());
          await _vault.applyRemote(
            id: remote.id,
            blob: remote.blob,
            rev: remote.rev,
            deleted: remote.deleted,
            updatedAtMs: remote.updatedAtMs,
          );
          break;
      }
    }
    await _setCursor(resp.cursor);
  }

  Future<void> _push(SyncClient client) async {
    final dirty = _vault.dirtyRecords();
    if (dirty.isEmpty) return;

    final changes = dirty
        .map((r) => PushChange(
              id: r.id,
              blob: r.blob,
              baseRev: r.rev,
              deleted: r.deleted,
              updatedAtMs: r.updatedAt.millisecondsSinceEpoch,
            ))
        .toList();

    final resp = await client.push(_token!, changes);
    final byId = {for (final res in resp.results) res.id: res};

    for (final r in dirty) {
      final res = byId[r.id];
      if (res == null) continue;
      if (res.isConflict && res.server != null) {
        // Keep our local edit as a new note, then adopt the server's version.
        await _vault.saveConflictCopy(r.id, _uuid.v4());
        final s = res.server!;
        await _vault.applyRemote(
          id: r.id,
          blob: s.blob,
          rev: s.rev,
          deleted: s.deleted,
          updatedAtMs: s.updatedAtMs,
        );
      } else if (r.deleted) {
        // Tombstone acknowledged — drop it locally.
        await _vault.hardDelete(r.id);
      } else {
        await _vault.markSynced(r.id, res.rev);
      }
    }
    await _setCursor(resp.cursor);
  }
}
