import 'dart:convert';
import 'dart:typed_data';

import '../models/note.dart';
import '../models/note_codec.dart';
import 'crypto_service.dart';

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => 'BackupException: $message';
}

/// Thrown when restoring an encrypted backup without a password.
class BackupNeedsPassword implements Exception {}

/// Serializes notes to/from a portable backup document the user can save off
/// the device (via the share sheet) and restore later.
///
/// Two formats:
///   * **encrypted** — wraps the same envelope as the vault (KDF salt/params +
///     wrapped DEK) plus the notes encrypted under the DEK. Restorable on any
///     device with the master password; the file reveals nothing without it.
///   * **plaintext** — readable JSON. Convenient, but an unencrypted copy of
///     the notes; only the user should decide where it goes.
class BackupService {
  static const _format = 'secretnotes-backup';
  static const _version = 1;

  static String exportPlaintext(List<Note> notes, {String? timestamp}) {
    return const JsonEncoder.withIndent('  ').convert({
      'format': _format,
      'version': _version,
      'encrypted': false,
      'exported_at': ?timestamp,
      'notes': notes.map(NoteCodec.toMap).toList(),
    });
  }

  static String exportEncrypted({
    required String kdfSaltB64,
    required String kdfParamsJson,
    required String wrappedDekB64,
    required Uint8List dek,
    required List<Note> notes,
    String? timestamp,
  }) {
    final notesJson = jsonEncode(notes.map(NoteCodec.toMap).toList());
    final blob = CryptoService.encryptPayload(
      dek,
      Uint8List.fromList(utf8.encode(notesJson)),
    );
    return const JsonEncoder.withIndent('  ').convert({
      'format': _format,
      'version': _version,
      'encrypted': true,
      'exported_at': ?timestamp,
      'kdf_salt': kdfSaltB64,
      'kdf_params': kdfParamsJson,
      'wrapped_dek': wrappedDekB64,
      'notes': base64Encode(blob),
    });
  }

  static bool isEncrypted(String content) => _parse(content)['encrypted'] == true;

  /// Decode a backup document into notes. Encrypted backups require [password].
  static List<Note> restore(String content, {String? password}) {
    final map = _parse(content);
    if (map['encrypted'] == true) {
      if (password == null || password.isEmpty) throw BackupNeedsPassword();
      final salt = base64Decode(map['kdf_salt'] as String);
      final params =
          (jsonDecode(map['kdf_params'] as String) as Map).cast<String, dynamic>();
      final masterKey = CryptoService.deriveMasterKey(
        password,
        salt,
        memoryKib: params['m'] as int,
        iterations: params['t'] as int,
        lanes: params['p'] as int,
      );
      Uint8List dek;
      try {
        dek = CryptoService.unwrapDek(
          CryptoService.wrapKey(masterKey),
          base64Decode(map['wrapped_dek'] as String),
        );
      } catch (_) {
        throw BackupException('Wrong password for this backup.');
      }
      final notesJson =
          utf8.decode(CryptoService.decryptPayload(dek, base64Decode(map['notes'] as String)));
      return _notesFromList(jsonDecode(notesJson));
    }
    return _notesFromList(map['notes']);
  }

  static List<Note> _notesFromList(dynamic list) => (list as List)
      .map((e) => NoteCodec.fromMap((e as Map).cast<String, dynamic>()))
      .toList();

  static Map<String, dynamic> _parse(String content) {
    Map<String, dynamic> map;
    try {
      map = (jsonDecode(content) as Map).cast<String, dynamic>();
    } catch (_) {
      throw BackupException('This file is not a valid backup.');
    }
    if (map['format'] != _format) {
      throw BackupException('This is not a SecretNotes backup.');
    }
    return map;
  }
}
