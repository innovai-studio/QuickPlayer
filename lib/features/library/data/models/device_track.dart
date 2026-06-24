/// Unified device track model for cross-platform audio files
/// Used primarily for Linux platform where on_audio_query is not available
class DeviceTrack {
  final String id;
  final String title;
  final String filePath;
  final int durationMs;
  final String? artist;
  final String? album;
  final int? fileSize;

  const DeviceTrack({
    required this.id,
    required this.title,
    required this.filePath,
    required this.durationMs,
    this.artist,
    this.album,
    this.fileSize,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  @override
  String toString() => 'DeviceTrack(id: $id, title: $title)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceTrack && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
