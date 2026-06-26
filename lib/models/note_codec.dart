import 'dart:convert';
import 'dart:typed_data';

import 'note.dart';

/// Serializes a [Note]'s plaintext fields to/from the bytes that get encrypted
/// into a record blob. The note id is included for integrity even though it is
/// also the record key.
class NoteCodec {
  static Uint8List encode(Note note) {
    final map = {
      'id': note.id,
      'title': note.title,
      'content': note.contentJson,
      'color': note.colorIndex,
      'created': note.createdAt.millisecondsSinceEpoch,
      'updated': note.updatedAt.millisecondsSinceEpoch,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  static Note decode(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return Note(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      contentJson: map['content'] as String? ?? '[{"insert":"\\n"}]',
      colorIndex: map['color'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated'] as int),
    );
  }
}
