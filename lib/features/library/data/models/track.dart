import 'package:hive/hive.dart';

part 'track.g.dart';

@HiveType(typeId: 0)
class Track extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String filePath;

  @HiveField(3)
  final int durationMs;

  @HiveField(4)
  final int fileSize;

  @HiveField(5)
  final String? mimeType;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  DateTime? lastPlayedAt;

  @HiveField(8)
  int? bpm;

  @HiveField(9)
  String? musicalKey;

  /// Whether this track is from external storage (not copied to app directory)
  @HiveField(10, defaultValue: false)
  final bool isExternal;

  /// Index of the EqPreset most recently used for this track. Stored as int
  /// (rather than the enum directly) to avoid forcing a Hive type adapter on
  /// the enum and to remain robust to enum reordering -- see EqPreset doc.
  @HiveField(11)
  int? focusPresetIndex;

  Track({
    required this.id,
    required this.name,
    required this.filePath,
    required this.durationMs,
    required this.fileSize,
    this.mimeType,
    required this.createdAt,
    this.lastPlayedAt,
    this.bpm,
    this.musicalKey,
    this.isExternal = false,
    this.focusPresetIndex,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  Track copyWith({
    String? id,
    String? name,
    String? filePath,
    int? durationMs,
    int? fileSize,
    String? mimeType,
    DateTime? createdAt,
    DateTime? lastPlayedAt,
    int? bpm,
    String? musicalKey,
    bool? isExternal,
    int? focusPresetIndex,
    bool clearFocusPreset = false,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      createdAt: createdAt ?? this.createdAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      bpm: bpm ?? this.bpm,
      musicalKey: musicalKey ?? this.musicalKey,
      isExternal: isExternal ?? this.isExternal,
      focusPresetIndex:
          clearFocusPreset ? null : (focusPresetIndex ?? this.focusPresetIndex),
    );
  }

  @override
  String toString() => 'Track(id: $id, name: $name)';
}
