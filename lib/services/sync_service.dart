import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/note_record.dart';

class SyncException implements Exception {
  final int? statusCode;
  final String message;
  SyncException(this.message, {this.statusCode});
  @override
  String toString() =>
      'SyncException(${statusCode ?? '-'}): $message';
}

/// A note as the server reports it in a change feed or conflict response.
class RemoteChange {
  final String id;
  final Uint8List blob;
  final int rev;
  final bool deleted;
  final int updatedAtMs;

  RemoteChange({
    required this.id,
    required this.blob,
    required this.rev,
    required this.deleted,
    required this.updatedAtMs,
  });

  factory RemoteChange.fromJson(Map<String, dynamic> j) => RemoteChange(
        id: j['id'] as String? ?? '',
        blob: j['blob'] == null || (j['blob'] as String).isEmpty
            ? Uint8List(0)
            : base64Decode(j['blob'] as String),
        rev: j['rev'] as int,
        deleted: j['deleted'] as bool? ?? false,
        updatedAtMs: j['updated_at'] as int? ?? 0,
      );
}

/// A local change being pushed to the server.
class PushChange {
  final String id;
  final Uint8List blob;
  final int baseRev;
  final bool deleted;
  final int updatedAtMs;

  PushChange({
    required this.id,
    required this.blob,
    required this.baseRev,
    required this.deleted,
    required this.updatedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'blob': blob.isEmpty ? null : base64Encode(blob),
        'base_rev': baseRev,
        'deleted': deleted,
        'updated_at': updatedAtMs,
      };
}

class PushResult {
  final String id;
  final String status; // "ok" | "conflict"
  final int rev;
  final RemoteChange? server; // present on conflict

  PushResult({
    required this.id,
    required this.status,
    required this.rev,
    this.server,
  });

  bool get isConflict => status == 'conflict';

  factory PushResult.fromJson(Map<String, dynamic> j) => PushResult(
        id: j['id'] as String,
        status: j['status'] as String,
        rev: j['rev'] as int? ?? 0,
        server: j['server'] == null
            ? null
            : RemoteChange.fromJson((j['server'] as Map).cast<String, dynamic>()),
      );
}

class ChangesResponse {
  final int cursor;
  final List<RemoteChange> changes;
  ChangesResponse(this.cursor, this.changes);
}

class PushResponse {
  final int cursor;
  final List<PushResult> results;
  PushResponse(this.cursor, this.results);
}

class LoginResponse {
  final String token;
  final String wrappedDekB64;
  LoginResponse(this.token, this.wrappedDekB64);
}

class PreloginResponse {
  final String kdfSaltB64;
  final String kdfParamsJson;
  PreloginResponse(this.kdfSaltB64, this.kdfParamsJson);
}

/// Thin HTTP client for the SecretNotes sync protocol. Knows nothing about
/// encryption — it only moves opaque blobs and tokens.
class SyncClient {
  final String baseUrl;
  final http.Client _http;

  SyncClient(String baseUrl, {http.Client? client})
      : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  void close() => _http.close();

  Uri _u(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Map<String, dynamic> _decode(http.Response r) {
    final body = r.body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(r.body) as Map).cast<String, dynamic>();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw SyncException(
        body['error']?.toString() ?? 'request failed',
        statusCode: r.statusCode,
      );
    }
    return body;
  }

  Future<String> register({
    required String adminToken,
    required String username,
    required Uint8List authKey,
    required String kdfSaltB64,
    required String kdfParamsJson,
    required String wrappedDekB64,
  }) async {
    final r = await _http.post(
      _u('/v1/register'),
      headers: _headers(null),
      body: jsonEncode({
        'admin_token': adminToken,
        'username': username,
        'auth_key': base64Encode(authKey),
        'kdf_salt': kdfSaltB64,
        'kdf_params': kdfParamsJson,
        'wrapped_dek': wrappedDekB64,
      }),
    );
    return _decode(r)['token'] as String;
  }

  Future<PreloginResponse> prelogin(String username) async {
    final r = await _http.get(_u('/v1/prelogin', {'username': username}));
    final j = _decode(r);
    return PreloginResponse(j['kdf_salt'] as String, j['kdf_params'] as String);
  }

  Future<LoginResponse> login(String username, Uint8List authKey) async {
    final r = await _http.post(
      _u('/v1/login'),
      headers: _headers(null),
      body: jsonEncode({
        'username': username,
        'auth_key': base64Encode(authKey),
      }),
    );
    final j = _decode(r);
    return LoginResponse(j['token'] as String, j['wrapped_dek'] as String);
  }

  Future<ChangesResponse> changes(String token, int since) async {
    final r = await _http.get(
      _u('/v1/changes', {'since': '$since'}),
      headers: _headers(token),
    );
    final j = _decode(r);
    final list = (j['changes'] as List)
        .map((e) => RemoteChange.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return ChangesResponse(j['cursor'] as int, list);
  }

  Future<PushResponse> push(String token, List<PushChange> changes) async {
    final r = await _http.post(
      _u('/v1/push'),
      headers: _headers(token),
      body: jsonEncode({'changes': changes.map((c) => c.toJson()).toList()}),
    );
    final j = _decode(r);
    final results = (j['results'] as List)
        .map((e) => PushResult.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return PushResponse(j['cursor'] as int, results);
  }
}

/// What to do with a record when the server reports a change for it.
enum MergeAction {
  /// No local record — store the remote one.
  insert,

  /// Local exists but is clean — adopt the remote version.
  overwrite,

  /// Local has un-pushed edits that differ from the remote — keep both:
  /// save the local edits as a conflicted copy, then take the remote.
  keepBoth,

  /// We already have this revision (e.g. our own just-pushed change) — skip.
  ignore,
}

/// Pure conflict-resolution decision, kept side-effect-free for testing.
MergeAction decideRemote(NoteRecord? local, RemoteChange remote) {
  if (local == null) return MergeAction.insert;
  if (!local.dirty) {
    // Adopt remote unless it's strictly older than what we already hold.
    return remote.rev <= local.rev ? MergeAction.ignore : MergeAction.overwrite;
  }
  // Local has un-pushed edits. If the remote isn't actually ahead of our base,
  // there's nothing new to reconcile.
  if (remote.rev <= local.rev) return MergeAction.ignore;
  return MergeAction.keepBoth;
}
