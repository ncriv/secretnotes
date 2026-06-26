import 'package:hive/hive.dart';

part 'note.g.dart';

@HiveType(typeId: 0)
class Note extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String contentJson;

  @HiveField(3)
  int colorIndex;

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  DateTime updatedAt;

  Note({
    required this.id,
    required this.title,
    required this.contentJson,
    required this.colorIndex,
    required this.createdAt,
    required this.updatedAt,
  });
}
