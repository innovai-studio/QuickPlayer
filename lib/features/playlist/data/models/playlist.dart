import 'package:hive/hive.dart';

part 'playlist.g.dart';

@HiveType(typeId: 2)
class Playlist extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final List<String> trackIds;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  DateTime? updatedAt;

  Playlist({
    required this.id,
    required this.name,
    required this.trackIds,
    required this.createdAt,
    this.updatedAt,
  });

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? List.from(this.trackIds),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Playlist(id: $id, name: $name, tracks: ${trackIds.length})';
}
