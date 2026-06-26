import 'package:flutter_test/flutter_test.dart';
import 'package:secretnotes/models/note.dart';
import 'package:secretnotes/models/note_codec.dart';
import 'package:secretnotes/services/crypto_service.dart';

void main() {
  test('Note survives encode/encrypt/decrypt/decode round-trip', () {
    final dek = CryptoService.generateDek();
    final note = Note(
      id: 'abc-123',
      title: 'Grocery list',
      contentJson: '[{"insert":"milk\\neggs\\n"}]',
      colorIndex: 3,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000123000),
    );

    final blob = CryptoService.encryptPayload(dek, NoteCodec.encode(note));
    final restored = NoteCodec.decode(CryptoService.decryptPayload(dek, blob));

    expect(restored.id, note.id);
    expect(restored.title, note.title);
    expect(restored.contentJson, note.contentJson);
    expect(restored.colorIndex, note.colorIndex);
    expect(restored.createdAt, note.createdAt);
    expect(restored.updatedAt, note.updatedAt);
  });
}
