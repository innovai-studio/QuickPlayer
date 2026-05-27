import 'package:hive/hive.dart';

part 'stem_set.g.dart';

/// A completed 4-stem separation for one track, cached on disk. Keyed by
/// trackId so re-opening a separated track skips the (multi-minute)
/// inference. Paths point at AAC .m4a files in the app's stem cache dir.
@HiveType(typeId: 5)
class StemSet extends HiveObject {
  @HiveField(0)
  final String trackId;

  @HiveField(1)
  final String drumsPath;

  @HiveField(2)
  final String bassPath;

  @HiveField(3)
  final String otherPath;

  @HiveField(4)
  final String vocalsPath;

  /// Segment length the model used (2.0 / 3.9 / 7.8 s) — recorded so we
  /// can show / re-separate at higher quality if the user later upgrades
  /// devices or we change the default.
  @HiveField(5)
  final double segmentSeconds;

  @HiveField(6)
  final int createdAtMs;

  StemSet({
    required this.trackId,
    required this.drumsPath,
    required this.bassPath,
    required this.otherPath,
    required this.vocalsPath,
    required this.segmentSeconds,
    required this.createdAtMs,
  });

  /// Stem paths in the canonical drums/bass/other/vocals order.
  List<String> get paths => [drumsPath, bassPath, otherPath, vocalsPath];

  static const sourceNames = ['drums', 'bass', 'other', 'vocals'];
}
