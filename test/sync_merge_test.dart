import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:secretnotes/models/note_record.dart';
import 'package:secretnotes/services/sync_service.dart';

NoteRecord _local({required int rev, required bool dirty}) => NoteRecord(
      id: 'n1',
      blob: Uint8List.fromList([1, 2, 3]),
      rev: rev,
      dirty: dirty,
      deleted: false,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

RemoteChange _remote({required int rev, bool deleted = false}) => RemoteChange(
      id: 'n1',
      blob: Uint8List.fromList([9, 9]),
      rev: rev,
      deleted: deleted,
      updatedAtMs: 2000,
    );

void main() {
  group('decideRemote', () {
    test('inserts when there is no local record', () {
      expect(decideRemote(null, _remote(rev: 5)), MergeAction.insert);
    });

    test('overwrites a clean local record with a newer remote', () {
      expect(
        decideRemote(_local(rev: 3, dirty: false), _remote(rev: 5)),
        MergeAction.overwrite,
      );
    });

    test('ignores a remote we already hold (clean, not newer)', () {
      expect(
        decideRemote(_local(rev: 5, dirty: false), _remote(rev: 5)),
        MergeAction.ignore,
      );
    });

    test('keeps both when local is dirty and remote is newer', () {
      expect(
        decideRemote(_local(rev: 3, dirty: true), _remote(rev: 5)),
        MergeAction.keepBoth,
      );
    });

    test('ignores when local is dirty but remote is not ahead', () {
      // e.g. our own change echoed back before we cleared the dirty flag.
      expect(
        decideRemote(_local(rev: 5, dirty: true), _remote(rev: 5)),
        MergeAction.ignore,
      );
    });

    test('keeps both for a remote tombstone over a dirty local edit', () {
      expect(
        decideRemote(_local(rev: 2, dirty: true), _remote(rev: 7, deleted: true)),
        MergeAction.keepBoth,
      );
    });
  });

  group('wire serialization', () {
    test('PushChange encodes empty blob as null (tombstone)', () {
      final c = PushChange(
        id: 'n1',
        blob: Uint8List(0),
        baseRev: 4,
        deleted: true,
        updatedAtMs: 123,
      );
      final json = c.toJson();
      expect(json['blob'], isNull);
      expect(json['deleted'], true);
      expect(json['base_rev'], 4);
    });

    test('RemoteChange round-trips from JSON', () {
      final r = RemoteChange.fromJson({
        'id': 'n1',
        'blob': 'AQID', // base64 of [1,2,3]
        'rev': 9,
        'deleted': false,
        'updated_at': 555,
      });
      expect(r.id, 'n1');
      expect(r.blob, equals(Uint8List.fromList([1, 2, 3])));
      expect(r.rev, 9);
      expect(r.updatedAtMs, 555);
    });

    test('PushResult parses a conflict with server version', () {
      final res = PushResult.fromJson({
        'id': 'n1',
        'status': 'conflict',
        'rev': 3,
        'server': {
          'id': 'n1',
          'blob': 'AQID',
          'rev': 3,
          'deleted': false,
          'updated_at': 99,
        },
      });
      expect(res.isConflict, true);
      expect(res.server, isNotNull);
      expect(res.server!.rev, 3);
    });
  });
}
