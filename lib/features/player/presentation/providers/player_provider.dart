import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/audio/audio_effects_service.dart';
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
  final AudioEffectsService _effectsService = AudioEffectsService();
  final StorageService _storage = StorageService();
  final _uuid = const Uuid();
  final _random = math.Random();

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  bool _isAnalyzing = false;

  PlayerNotifier() : super(const AppPlayerState()) {
    _initStreams();
    _seedFocusFromSettings();
  }

  /// Seed the in-memory focus preset from persisted user default. Track-level
  /// memory still wins inside loadTrack -- this only matters for the very
  /// first track played in a session and for device-audio (which has no
  /// per-track memory of its own).
  Future<void> _seedFocusFromSettings() async {
    await _storage.init();
    final idx = _storage.getSetting<int>('defaultFocusModeIndex');
    if (idx == null || idx < 0 || idx >= EqPreset.values.length) return;
    final preset = EqPreset.values[idx];
    if (preset != state.focusMode) {
      state = state.copyWith(focusMode: preset);
    }
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
      // Effects capability becomes known after the first audio session id
      // arrives -- piggy-back on player state updates to surface it. When
      // it transitions to available, also seed band levels from the
      // currently-selected preset so the visualiser has data to render.
      if (_effectsService.isAvailable != state.focusAvailable) {
        final levels = _effectsService.presetBandLevels(state.focusMode);
        final bass = _effectsService.presetBassStrength(state.focusMode);
        state = state.copyWith(
          focusAvailable: _effectsService.isAvailable,
          bandLevelsMillibel: levels != null
              ? _normaliseToDeviceBands(levels)
              : state.bandLevelsMillibel,
          bassStrengthMilli: bass,
        );
      }
    });
  }

  /// Apply a Focus EQ preset. No-op effectively when device doesn't
  /// support effects, but state still updates so the UI reflects intent.
  ///
  /// Persists the choice on the current Track so the same preset is
  /// re-applied next time the track plays. Device-audio (isExternal)
  /// tracks are kept in memory only -- they aren't in the Hive box.
  Future<void> setFocusMode(EqPreset preset) async {
    await _effectsService.applyPreset(preset);

    final track = state.currentTrack;
    Track? updatedTrack;
    if (track != null) {
      // Switching back to a canned preset wipes any custom band memory
      // for this track so the next load resolves cleanly.
      updatedTrack = track.copyWith(
        focusPresetIndex: preset.index,
        clearFocusPreset: preset == EqPreset.flat,
        clearCustomEq: preset.isCanned,
      );
      if (!track.isExternal) {
        await _storage.saveTrack(updatedTrack);
      }
    }

    // Seed the visualiser's band levels from the preset table so the
    // sliders snap to the new shape. Custom presets don't have a table --
    // leave the existing levels in place.
    final newLevels = _effectsService.presetBandLevels(preset) != null
        ? _normaliseToDeviceBands(_effectsService.presetBandLevels(preset)!)
        : state.bandLevelsMillibel;
    final newBass = preset.isCanned
        ? _effectsService.presetBassStrength(preset)
        : state.bassStrengthMilli;

    state = state.copyWith(
      focusMode: preset,
      currentTrack: updatedTrack ?? track,
      bandLevelsMillibel: _normaliseToDeviceBands(newLevels),
      bassStrengthMilli: newBass,
    );
  }

  /// Apply a manual band-level edit. Flips focus mode to custom.
  Future<void> setBandLevel(int bandIndex, int millibel) async {
    if (!_effectsService.isAvailable) return;
    final levels = List<int>.from(state.bandLevelsMillibel);
    if (bandIndex < 0 || bandIndex >= levels.length) return;
    levels[bandIndex] = millibel;

    await _effectsService.applyCustom(
      bandLevelsMillibel: levels,
      bassStrengthMilli: state.bassStrengthMilli,
    );
    state = state.copyWith(
      focusMode: EqPreset.custom,
      bandLevelsMillibel: levels,
    );
    await _persistCustomEqIfNeeded();
  }

  /// Apply a manual bass-boost edit. Also flips to custom.
  Future<void> setBassStrength(int milli) async {
    if (!_effectsService.isAvailable) return;
    final clamped = milli.clamp(0, 1000);
    await _effectsService.applyCustom(
      bandLevelsMillibel: state.bandLevelsMillibel,
      bassStrengthMilli: clamped,
    );
    state = state.copyWith(
      focusMode: EqPreset.custom,
      bassStrengthMilli: clamped,
    );
    await _persistCustomEqIfNeeded();
  }

  /// Resize the band-level list to match the device's actual band count
  /// (capabilities reported by the platform). Linearly interpolates if
  /// our 5-element preset table doesn't line up with the device.
  List<int> _normaliseToDeviceBands(List<int> source) {
    final caps = _effectsService.capabilities;
    final target = caps.numberOfBands;
    if (target <= 0 || source.isEmpty) return source;
    if (source.length == target) return source;

    final out = List<int>.filled(target, 0);
    final srcLast = source.length - 1;
    final tgtLast = target - 1;
    for (int i = 0; i < target; i++) {
      final pos = tgtLast == 0 ? 0.0 : i * srcLast / tgtLast;
      final lo = pos.toInt().clamp(0, srcLast);
      final hi = (lo + 1).clamp(0, srcLast);
      final frac = pos - lo;
      out[i] = (source[lo] * (1 - frac) + source[hi] * frac).round();
    }
    return out;
  }

  Future<void> _persistCustomEqIfNeeded() async {
    final track = state.currentTrack;
    if (track == null || track.isExternal) return;
    final updated = track.copyWith(
      focusPresetIndex: EqPreset.custom.index,
      customBandLevels: List<int>.from(state.bandLevelsMillibel),
      customBassStrength: state.bassStrengthMilli,
    );
    await _storage.saveTrack(updated);
    state = state.copyWith(currentTrack: updated);
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

      // Update last played (only for non-external tracks)
      Track updatedTrack;
      if (!track.isExternal) {
        updatedTrack = track.copyWith(lastPlayedAt: DateTime.now());
        await _storage.saveTrack(updatedTrack);
        await _storage.setLastTrackId(track.id);
      } else {
        updatedTrack = track;
      }

      // Resolve which Focus preset to apply: track-specific memory wins,
      // otherwise fall back to whatever's currently active (which itself
      // was seeded from defaults at app start).
      final resolvedFocus = _resolveFocusForTrack(updatedTrack);
      final resolvedLevels = _resolveBandLevels(updatedTrack, resolvedFocus);
      final resolvedBass = _resolveBassStrength(updatedTrack, resolvedFocus);

      state = state.copyWith(
        currentTrack: updatedTrack,
        duration: duration ?? Duration.zero,
        position: Duration.zero,
        markers: markers,
        isLoading: false,
        clearAbLoop: true,
        focusMode: resolvedFocus,
        bandLevelsMillibel: resolvedLevels,
        bassStrengthMilli: resolvedBass,
      );

      // Apply on the audio session (no-op if effects unsupported).
      if (resolvedFocus == EqPreset.custom) {
        await _effectsService.applyCustom(
          bandLevelsMillibel: resolvedLevels,
          bassStrengthMilli: resolvedBass,
        );
      } else {
        await _effectsService.applyPreset(resolvedFocus);
      }

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

  EqPreset _resolveFocusForTrack(Track track) {
    final idx = track.focusPresetIndex;
    if (idx == null) return state.focusMode;
    if (idx < 0 || idx >= EqPreset.values.length) return EqPreset.flat;
    return EqPreset.values[idx];
  }

  /// Pick which band levels to seed in state for this (track, preset).
  /// Custom prefers the track's stored levels; canned presets pull from
  /// the preset table; falls back to current state when neither applies.
  List<int> _resolveBandLevels(Track track, EqPreset preset) {
    if (preset == EqPreset.custom) {
      final stored = track.customBandLevels;
      if (stored != null && stored.isNotEmpty) {
        return _normaliseToDeviceBands(List<int>.from(stored));
      }
      return _normaliseToDeviceBands(state.bandLevelsMillibel);
    }
    final canned = _effectsService.presetBandLevels(preset);
    if (canned != null) return _normaliseToDeviceBands(canned);
    return state.bandLevelsMillibel;
  }

  int _resolveBassStrength(Track track, EqPreset preset) {
    if (preset == EqPreset.custom) {
      return track.customBassStrength ?? state.bassStrengthMilli;
    }
    return _effectsService.presetBassStrength(preset);
  }

  /// Load and play audio directly from file path (for device audio)
  /// Creates a temporary Track object without saving to storage
  Future<void> loadFromPath({
    required String filePath,
    required String title,
    String? artist,
    int? durationMs,
  }) async {
    // Create a temporary Track object (not saved to Hive)
    final tempTrack = Track(
      id: 'device_${filePath.hashCode}',
      name: title,
      filePath: filePath,
      durationMs: durationMs ?? 0,
      fileSize: 0,
      createdAt: DateTime.now(),
      isExternal: true,
    );

    try {
      state = state.copyWith(
        isLoading: true,
        clearError: true,
        currentTrack: tempTrack,
        position: Duration.zero,
        duration: Duration.zero,
        clearAbLoop: true,
        // Clear queue since this is a single track play
        queue: [tempTrack],
        currentIndex: 0,
      );

      // Check if file exists
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Audio file not found: $filePath');
      }

      // Load file
      final duration = await _audioService.loadFile(filePath);
      final markers = _storage.getMarkersForTrack(tempTrack.id);

      // Device-audio tracks aren't persisted, so they don't carry their
      // own focus memory -- inherit whatever the player currently has.
      await _effectsService.applyPreset(state.focusMode);

      final loadedTrack = tempTrack.copyWith(
        durationMs: duration?.inMilliseconds ?? durationMs ?? 0,
      );

      state = state.copyWith(
        currentTrack: loadedTrack,
        duration: duration ?? Duration.zero,
        position: Duration.zero,
        markers: markers,
        isLoading: false,
        clearAbLoop: true,
      );

      // Device audio doesn't carry persisted BPM/Key, so always kick off
      // analysis. Result lives in memory only (skipped in _analyzeTrack
      // for isExternal tracks) so the UI updates without polluting Hive.
      _analyzeTrack(loadedTrack);

      await _audioService.play();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load audio: $e',
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

        // External (device-audio) tracks aren't in the Hive box, so skip
        // persistence and just update the in-memory player state.
        if (!track.isExternal) {
          await _storage.saveTrack(updatedTrack);
        }
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
