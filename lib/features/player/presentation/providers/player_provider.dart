import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/audio/audio_player_service.dart';
import '../../../../core/audio/audio_analyzer_service.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../library/data/models/track.dart';
import '../../data/models/ab_loop.dart';
import '../../data/models/marker.dart';
import '../../data/models/play_mode.dart';
import 'player_state.dart';

final playerProvider = StateNotifierProvider<PlayerNotifier, AppPlayerState>((ref) {
  return PlayerNotifier();
});

class PlayerNotifier extends StateNotifier<AppPlayerState> {
  final AudioPlayerService _audioService = AudioPlayerService();
  final AudioAnalyzerService _analyzerService = AudioAnalyzerService();
  final StorageService _storage = StorageService();
  final _uuid = const Uuid();
  final _random = math.Random();

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  bool _isAnalyzing = false;

  PlayerNotifier() : super(const AppPlayerState()) {
    _initStreams();
  }

  void _initStreams() {
    _positionSubscription = _audioService.positionStream.listen((position) {
      state = state.copyWith(position: position);
      _checkAbLoop(position);
    });

    _audioService.playingStream.listen((playing) {
      state = state.copyWith(isPlaying: playing);
    });

    _audioService.durationStream.listen((duration) {
      if (duration != null) {
        state = state.copyWith(duration: duration);
      }
    });

    // Listen for track completion
    _playerStateSubscription = _audioService.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _onTrackComplete();
      }
    });
  }

  /// Handle track completion based on play mode
  void _onTrackComplete() {
    // Don't auto-advance if A-B loop is active
    if (state.abLoop?.isActive == true) return;

    switch (state.playMode) {
      case PlayMode.sequential:
        if (state.hasNext) {
          playNext();
        } else {
          // Stop at end of queue
          _audioService.stop();
        }
        break;
      case PlayMode.loopAll:
        playNext();
        break;
      case PlayMode.loopOne:
        // Seek to beginning and play again
        _audioService.seek(Duration.zero);
        _audioService.play();
        break;
      case PlayMode.shuffle:
        if (state.hasNext) {
          playNext();
        } else {
          // Stop at end of shuffled queue
          _audioService.stop();
        }
        break;
    }
  }

  void _checkAbLoop(Duration position) {
    final abLoop = state.abLoop;
    if (abLoop != null && abLoop.isActive && abLoop.isComplete) {
      if (position >= abLoop.pointB!) {
        _audioService.seek(abLoop.pointA!);
      }
    }
  }

  /// Load and play a track
  Future<void> loadTrack(Track track) async {
    try {
      // Clear previous track and show loading state
      state = state.copyWith(
        isLoading: true,
        clearError: true,
        currentTrack: track,  // Show new track info immediately
        position: Duration.zero,
        duration: Duration.zero,
        clearAbLoop: true,  // Clear A-B loop state for new track
      );

      // Check if file exists
      final file = File(track.filePath);
      if (!await file.exists()) {
        throw Exception('Audio file not found: ${track.filePath}');
      }

      // Load new file (this will stop previous playback and reset player)
      final duration = await _audioService.loadFile(track.filePath);
      final markers = _storage.getMarkersForTrack(track.id);

      // Update last played
      final updatedTrack = track.copyWith(lastPlayedAt: DateTime.now());
      await _storage.saveTrack(updatedTrack);
      await _storage.setLastTrackId(track.id);

      state = state.copyWith(
        currentTrack: updatedTrack,
        duration: duration ?? Duration.zero,
        position: Duration.zero,
        markers: markers,
        isLoading: false,
        clearAbLoop: true,
      );

      // Start analysis immediately (before play) if BPM/Key not set
      if (updatedTrack.bpm == null || updatedTrack.musicalKey == null) {
        // Don't await - run in background
        _analyzeTrack(updatedTrack);
      }

      await _audioService.play();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load track: $e',
      );
    }
  }

  /// Load a queue of tracks and start playing from a specific index
  Future<void> loadQueue(
    List<Track> tracks,
    int startIndex, {
    String? playlistId,
  }) async {
    if (tracks.isEmpty) return;

    final clampedIndex = startIndex.clamp(0, tracks.length - 1);

    // Generate shuffle order if in shuffle mode
    List<int>? shuffleOrder;
    if (state.playMode == PlayMode.shuffle) {
      shuffleOrder = _generateShuffleOrder(tracks.length, clampedIndex);
    }

    state = state.copyWith(
      queue: tracks,
      currentIndex: clampedIndex,
      queueSourceId: playlistId,
      shuffleOrder: shuffleOrder,
    );

    await loadTrack(tracks[clampedIndex]);
  }

  /// Generate a shuffled order with current track at the beginning
  List<int> _generateShuffleOrder(int length, int currentIndex) {
    final indices = List.generate(length, (i) => i);
    indices.remove(currentIndex);
    indices.shuffle(_random);
    return [currentIndex, ...indices];
  }

  /// Play the next track in the queue
  Future<void> playNext() async {
    if (state.queue.isEmpty) return;

    int nextIndex;

    if (state.playMode == PlayMode.shuffle && state.shuffleOrder != null) {
      // Find current position in shuffle order and move to next
      final shuffleOrder = state.shuffleOrder!;
      final currentShufflePos = shuffleOrder.indexOf(state.currentIndex);
      final nextShufflePos = currentShufflePos + 1;

      if (nextShufflePos >= shuffleOrder.length) {
        if (state.playMode == PlayMode.loopAll) {
          // Re-shuffle and start from beginning
          final newShuffleOrder = _generateShuffleOrder(state.queue.length, shuffleOrder[0]);
          state = state.copyWith(shuffleOrder: newShuffleOrder);
          nextIndex = newShuffleOrder[0];
        } else {
          return; // End of shuffle queue
        }
      } else {
        nextIndex = shuffleOrder[nextShufflePos];
      }
    } else {
      // Sequential or loop mode
      nextIndex = state.currentIndex + 1;
      if (nextIndex >= state.queue.length) {
        if (state.playMode == PlayMode.loopAll) {
          nextIndex = 0; // Wrap to beginning
        } else {
          return; // End of queue
        }
      }
    }

    state = state.copyWith(currentIndex: nextIndex);
    await loadTrack(state.queue[nextIndex]);
  }

  /// Play the previous track in the queue
  Future<void> playPrevious() async {
    if (state.queue.isEmpty) return;

    // If we're more than 3 seconds into the track, just restart it
    if (state.position.inSeconds > 3) {
      await _audioService.seek(Duration.zero);
      return;
    }

    int prevIndex;

    if (state.playMode == PlayMode.shuffle && state.shuffleOrder != null) {
      // Find current position in shuffle order and move to previous
      final shuffleOrder = state.shuffleOrder!;
      final currentShufflePos = shuffleOrder.indexOf(state.currentIndex);
      final prevShufflePos = currentShufflePos - 1;

      if (prevShufflePos < 0) {
        if (state.playMode == PlayMode.loopAll) {
          prevIndex = shuffleOrder.last;
        } else {
          await _audioService.seek(Duration.zero); // Just restart
          return;
        }
      } else {
        prevIndex = shuffleOrder[prevShufflePos];
      }
    } else {
      // Sequential or loop mode
      prevIndex = state.currentIndex - 1;
      if (prevIndex < 0) {
        if (state.playMode == PlayMode.loopAll) {
          prevIndex = state.queue.length - 1; // Wrap to end
        } else {
          await _audioService.seek(Duration.zero); // Just restart
          return;
        }
      }
    }

    state = state.copyWith(currentIndex: prevIndex);
    await loadTrack(state.queue[prevIndex]);
  }

  /// Set the play mode
  void setPlayMode(PlayMode mode) {
    // Generate shuffle order when switching to shuffle mode
    List<int>? shuffleOrder;
    if (mode == PlayMode.shuffle && state.queue.isNotEmpty) {
      shuffleOrder = _generateShuffleOrder(state.queue.length, state.currentIndex);
    }

    state = state.copyWith(
      playMode: mode,
      shuffleOrder: mode == PlayMode.shuffle ? shuffleOrder : null,
      clearShuffleOrder: mode != PlayMode.shuffle,
    );
  }

  /// Cycle through play modes
  void cyclePlayMode() {
    const modes = PlayMode.values;
    final currentIndex = modes.indexOf(state.playMode);
    final nextIndex = (currentIndex + 1) % modes.length;
    setPlayMode(modes[nextIndex]);
  }

  /// Play/Pause toggle
  Future<void> togglePlay() async {
    if (state.isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _audioService.seek(position);
  }

  /// Set speed
  Future<void> setSpeed(double speed) async {
    await _audioService.setSpeed(speed);
    state = state.copyWith(speed: speed);
  }

  /// Set pitch (in semitones)
  Future<void> setPitchSemitones(int semitones) async {
    await _audioService.setPitchSemitones(semitones);
    state = state.copyWith(pitchSemitones: semitones);
  }

  /// Set A point
  void setPointA() {
    final track = state.currentTrack;
    if (track == null) return;

    final newAbLoop = ABLoop(
      trackId: track.id,
      pointA: state.position,
      pointB: state.abLoop?.pointB,
      isActive: state.abLoop?.isActive ?? false,
    );
    state = state.copyWith(abLoop: newAbLoop);
  }

  /// Set B point
  void setPointB() {
    final track = state.currentTrack;
    if (track == null) return;

    final newAbLoop = ABLoop(
      trackId: track.id,
      pointA: state.abLoop?.pointA,
      pointB: state.position,
      isActive: state.abLoop?.isActive ?? false,
    );
    state = state.copyWith(abLoop: newAbLoop);
  }

  /// Toggle A-B loop
  Future<void> toggleAbLoop() async {
    final abLoop = state.abLoop;
    if (abLoop == null || !abLoop.isComplete) return;

    final newActive = !abLoop.isActive;
    final newAbLoop = abLoop.copyWith(isActive: newActive);

    if (newActive) {
      // Use setClip for reliable looping within the A-B range
      await _audioService.setClip(start: abLoop.pointA!, end: abLoop.pointB!);
      await _audioService.setLoopMode(LoopMode.one);
      // Seek to A if current position is outside the loop
      if (state.position < abLoop.pointA! || state.position > abLoop.pointB!) {
        await _audioService.seek(abLoop.pointA!);
      }
    } else {
      // Clear clip and disable loop
      await _audioService.clearClip();
      await _audioService.setLoopMode(LoopMode.off);
    }

    state = state.copyWith(abLoop: newAbLoop);
  }

  /// Clear A-B loop
  Future<void> clearAbLoop() async {
    await _audioService.clearClip();
    await _audioService.setLoopMode(LoopMode.off);
    state = state.copyWith(clearAbLoop: true);
  }

  /// Add marker at current position
  Future<void> addMarker(String label) async {
    final track = state.currentTrack;
    if (track == null) return;

    final marker = Marker(
      id: _uuid.v4(),
      trackId: track.id,
      positionMs: state.position.inMilliseconds,
      label: label,
      createdAt: DateTime.now(),
    );

    await _storage.saveMarker(marker);

    final updatedMarkers = [...state.markers, marker]
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    state = state.copyWith(markers: updatedMarkers);
  }

  /// Delete marker
  Future<void> deleteMarker(String markerId) async {
    await _storage.deleteMarker(markerId);
    final updatedMarkers = state.markers.where((m) => m.id != markerId).toList();
    state = state.copyWith(markers: updatedMarkers);
  }

  /// Jump to marker
  Future<void> jumpToMarker(Marker marker) async {
    await _audioService.seek(marker.position);
  }

  /// Stop playback and clear current track
  Future<void> stopAndClear() async {
    await _audioService.stop();
    state = const AppPlayerState();
  }

  /// Update current track info (for BPM/Key edits)
  void updateCurrentTrack(Track track) {
    if (state.currentTrack?.id == track.id) {
      state = state.copyWith(currentTrack: track);
    }
  }

  /// Analyze track for BPM and Key in background
  Future<void> _analyzeTrack(Track track) async {
    if (_isAnalyzing) return;
    _isAnalyzing = true;

    try {
      state = state.copyWith(isAnalyzing: true);

      final result = await _analyzerService.analyze(track.filePath);

      // Only update if this track is still current
      if (state.currentTrack?.id == track.id) {
        final updatedTrack = track.copyWith(
          bpm: result.bpm ?? track.bpm,
          musicalKey: result.key ?? track.musicalKey,
        );

        await _storage.saveTrack(updatedTrack);
        state = state.copyWith(
          currentTrack: updatedTrack,
          isAnalyzing: false,
        );
      }
    } catch (e) {
      state = state.copyWith(isAnalyzing: false);
    } finally {
      _isAnalyzing = false;
    }
  }

  /// Manually trigger analysis for current track
  Future<void> analyzeCurrentTrack() async {
    final track = state.currentTrack;
    if (track != null) {
      await _analyzeTrack(track);
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _audioService.dispose();
    super.dispose();
  }
}
