import 'dart:typed_data';

import 'package:hive/hive.dart';

/// On-disk and on-wire unit of sync.
///
/// [blob] is the AES-256-GCM ciphertext (`nonce || ct || tag`) of the padded,
/// JSON-serialized note. Everything outside [blob] is sync metadata that the
/// server is allowed to see; the note's actual content/title is only ever
/// inside [blob], decryptable with the DEK.
class NoteRecord {
  /// Stable note id (UUID), shared across devices. Opaque to the server.
  String id;

  /// Encrypted, padded note payload. Empty for a tombstone.
  Uint8List blob;

  /// Last server-assigned revision. 0 means "never synced".
  int rev;

  /// True when there are local changes not yet pushed to the server.
  bool dirty;

  /// Tombstone marker — a delete that must propagate to other devices.
  bool deleted;

  /// Last modification time (local clock), used for sorting and LWW.
  DateTime updatedAt;

  NoteRecord({
    required this.id,
    required this.blob,
    this.rev = 0,
    this.dirty = false,
    this.deleted = false,
    required this.updatedAt,
  });
}

/// Hand-written Hive adapter (typeId 1) so the project needs no codegen step.
class NoteRecordAdapter extends TypeAdapter<NoteRecord> {
  @override
  final int typeId = 1;

  @override
  NoteRecord read(BinaryReader reader) {
    final id = reader.readString();
    final blob = reader.readByteList();
    final rev = reader.readInt();
    final dirty = reader.readBool();
    final deleted = reader.readBool();
    final updatedAtMs = reader.readInt();
    return NoteRecord(
      id: id,
      blob: Uint8List.fromList(blob),
      rev: rev,
      dirty: dirty,
      deleted: deleted,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
    );
  }

  @override
  void write(BinaryWriter writer, NoteRecord obj) {
    writer.writeString(obj.id);
    writer.writeByteList(obj.blob);
    writer.writeInt(obj.rev);
    writer.writeBool(obj.dirty);
    writer.writeBool(obj.deleted);
    writer.writeInt(obj.updatedAt.millisecondsSinceEpoch);
  }
}
