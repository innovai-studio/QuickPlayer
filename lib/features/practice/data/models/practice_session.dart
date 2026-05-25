import 'package:hive/hive.dart';

part 'practice_session.g.dart';

/// A single span of active playback. The recorder opens a new session
/// on play, accumulates while playing, and flushes on pause / stop /
/// track-change. We don't merge across pauses -- two pauses in a song
/// produce two sessions -- so the data faithfully reflects how the
/// user actually used the app and we can sum it any way we want at
/// query time.
@HiveType(typeId: 4)
class PracticeSession extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String trackId;

  /// UTC ms timestamp of when playback started. Stored as int rather
  /// than DateTime so the Hive payload stays compact and ordering is
  /// straightforward.
  @HiveField(2)
  final int startedAtMs;

  @HiveField(3)
  int durationMs;

  /// Snapshot of the track's display name at the moment the session was
  /// opened. We store it here instead of looking up `trackId` later
  /// because most playback flows through `loadFromPath` (device-audio
  /// tab), which creates an ephemeral Track that never lands in the
  /// library Hive box -- so a later lookup by id would always miss and
  /// the UI would show "Removed track" for every real session.
  @HiveField(4)
  final String? trackName;

  PracticeSession({
    required this.id,
    required this.trackId,
    required this.startedAtMs,
    required this.durationMs,
    this.trackName,
  });

  DateTime get startedAt =>
      DateTime.fromMillisecondsSinceEpoch(startedAtMs, isUtc: true);

  /// Local-time start, used by the UI when bucketing into calendar days.
  DateTime get startedAtLocal => startedAt.toLocal();

  Duration get duration => Duration(milliseconds: durationMs);
}
