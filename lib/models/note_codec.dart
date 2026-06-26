import 'dart:convert';
import 'dart:typed_data';

import 'note.dart';

/// Serializes a [Note]'s plaintext fields to/from the bytes that get encrypted
/// into a record blob. The note id is included for integrity even though it is
/// also the record key.
class NoteCodec {
  static Map<String, dynamic> toMap(Note note) => {
        'id': note.id,
        'title': note.title,
        'content': note.contentJson,
        'color': note.colorIndex,
        'created': note.createdAt.millisecondsSinceEpoch,
        'updated': note.updatedAt.millisecondsSinceEpoch,
      };

  static Note fromMap(Map<String, dynamic> map) => Note(
        id: map['id'] as String,
        title: map['title'] as String? ?? '',
        contentJson: map['content'] as String? ?? '[{"insert":"\\n"}]',
        colorIndex: map['color'] as int? ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated'] as int),
      );

  static Uint8List encode(Note note) =>
      Uint8List.fromList(utf8.encode(jsonEncode(toMap(note))));

  static Note decode(Uint8List bytes) =>
      fromMap((jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>());
}
