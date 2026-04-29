import '../../../../core/audio/audio_effects_service.dart';
import '../../data/models/ab_loop.dart';
import '../../data/models/marker.dart';
import '../../data/models/play_mode.dart';
import '../../../library/data/models/track.dart';

class AppPlayerState {
  final Track? currentTrack;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double speed;
  final int pitchSemitones;
  final ABLoop? abLoop;
  final List<Marker> markers;
  final bool isLoading;
  final bool isAnalyzing;
  final String? error;

  // Queue-related fields
  final List<Track> queue;
  final int currentIndex;
  final PlayMode playMode;
  final String? queueSourceId; // null = Library, otherwise playlist ID
  final List<int>? shuffleOrder; // Shuffle indices when in shuffle mode

  // Focus EQ
  final EqPreset focusMode;
  final bool focusAvailable;

  const AppPlayerState({
    this.currentTrack,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.pitchSemitones = 0,
    this.abLoop,
    this.markers = const [],
    this.isLoading = false,
    this.isAnalyzing = false,
    this.error,
    this.queue = const [],
    this.currentIndex = 0,
    this.playMode = PlayMode.sequential,
    this.queueSourceId,
    this.shuffleOrder,
    this.focusMode = EqPreset.flat,
    this.focusAvailable = false,
  });

  /// Whether there's a next track in the queue
  bool get hasNext {
    if (queue.isEmpty) return false;
    if (playMode == PlayMode.loopAll) return true;
    if (playMode == PlayMode.shuffle && shuffleOrder != null) {
      final currentShuffleIndex = shuffleOrder!.indexOf(currentIndex);
      return currentShuffleIndex < shuffleOrder!.length - 1;
    }
    return currentIndex < queue.length - 1;
  }

  /// Whether there's a previous track in the queue
  bool get hasPrevious {
    if (queue.isEmpty) return false;
    if (playMode == PlayMode.loopAll) return true;
    if (playMode == PlayMode.shuffle && shuffleOrder != null) {
      final currentShuffleIndex = shuffleOrder!.indexOf(currentIndex);
      return currentShuffleIndex > 0;
    }
    return currentIndex > 0;
  }

  AppPlayerState copyWith({
    Track? currentTrack,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    double? speed,
    int? pitchSemitones,
    ABLoop? abLoop,
    List<Marker>? markers,
    bool? isLoading,
    bool? isAnalyzing,
    String? error,
    List<Track>? queue,
    int? currentIndex,
    PlayMode? playMode,
    String? queueSourceId,
    List<int>? shuffleOrder,
    EqPreset? focusMode,
    bool? focusAvailable,
    bool clearTrack = false,
    bool clearAbLoop = false,
    bool clearError = false,
    bool clearQueue = false,
    bool clearShuffleOrder = false,
  }) {
    return AppPlayerState(
      currentTrack: clearTrack ? null : (currentTrack ?? this.currentTrack),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      pitchSemitones: pitchSemitones ?? this.pitchSemitones,
      abLoop: clearAbLoop ? null : (abLoop ?? this.abLoop),
      markers: markers ?? this.markers,
      isLoading: isLoading ?? this.isLoading,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      error: clearError ? null : (error ?? this.error),
      queue: clearQueue ? const [] : (queue ?? this.queue),
      currentIndex: currentIndex ?? this.currentIndex,
      playMode: playMode ?? this.playMode,
      queueSourceId: queueSourceId ?? this.queueSourceId,
      shuffleOrder: clearShuffleOrder ? null : (shuffleOrder ?? this.shuffleOrder),
      focusMode: focusMode ?? this.focusMode,
      focusAvailable: focusAvailable ?? this.focusAvailable,
    );
  }
}
