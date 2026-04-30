import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/metronome_service.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../player/presentation/providers/player_provider.dart';

/// One self-contained piece of metronome state.
///
/// `phaseOffsetMs` is the player-position (in ms) of "beat zero" --
/// the alignment anchor the user established by tap-to-sync. Subsequent
/// beat times are `phaseOffsetMs + n * (60000 / bpm)`.
class MetronomeState {
  final bool enabled;
  final double bpm;
  final int phaseOffsetMs;
  final int beatsPerBar;
  final int currentBeatIndex; // 0..beatsPerBar-1, drives the indicator lights
  final List<int> tapHistoryMs; // recent tap timestamps for live calibration

  const MetronomeState({
    this.enabled = false,
    this.bpm = 120,
    this.phaseOffsetMs = 0,
    this.beatsPerBar = 4,
    this.currentBeatIndex = 0,
    this.tapHistoryMs = const [],
  });

  bool get isAligned => phaseOffsetMs >= 0 && bpm > 0;
  double get beatIntervalMs => 60000.0 / bpm;

  MetronomeState copyWith({
    bool? enabled,
    double? bpm,
    int? phaseOffsetMs,
    int? beatsPerBar,
    int? currentBeatIndex,
    List<int>? tapHistoryMs,
  }) {
    return MetronomeState(
      enabled: enabled ?? this.enabled,
      bpm: bpm ?? this.bpm,
      phaseOffsetMs: phaseOffsetMs ?? this.phaseOffsetMs,
      beatsPerBar: beatsPerBar ?? this.beatsPerBar,
      currentBeatIndex: currentBeatIndex ?? this.currentBeatIndex,
      tapHistoryMs: tapHistoryMs ?? this.tapHistoryMs,
    );
  }
}

final metronomeProvider =
    StateNotifierProvider<MetronomeNotifier, MetronomeState>((ref) {
  final notifier = MetronomeNotifier(ref);
  // Re-bind metronome whenever the player loads a new track. We compare
  // ids rather than full Track instances so transient copyWith updates
  // (e.g. lastPlayedAt, BPM analysis result) don't trigger a reset.
  ref.listen(playerProvider.select((s) => s.currentTrack?.id),
      (prev, next) {
    if (prev == next) return;
    final track = ref.read(playerProvider).currentTrack;
    notifier.onTrackLoaded(
      bpm: track?.bpm?.toDouble(),
      phaseOffsetMs: track?.metronomePhaseOffsetMs,
    );
  });
  return notifier;
});

class MetronomeNotifier extends StateNotifier<MetronomeState> {
  final Ref _ref;
  final MetronomeService _click = MetronomeService();
  final StorageService _storage = StorageService();
  Ticker? _ticker;
  int _lastClickedBeatNumber = -1;

  /// Window inside which we accept "we just crossed this beat" before
  /// declaring it missed. Player position polls in chunks so we can't be
  /// surgical, but 80ms is tight enough that double-clicks won't happen.
  static const int _beatTriggerWindowMs = 80;

  /// How long to wait between taps before discarding history. A user
  /// hesitating longer than 2 seconds was probably distracted -- start over.
  static const int _tapResetMs = 2000;

  MetronomeNotifier(this._ref) : super(const MetronomeState());

  // ---- enable/disable -------------------------------------------------

  Future<void> toggle() async {
    if (state.enabled) {
      await disable();
    } else {
      await enable();
    }
  }

  Future<void> enable() async {
    if (state.enabled) return;
    state = state.copyWith(enabled: true);
    _startTicker();
  }

  Future<void> disable() async {
    if (!state.enabled) return;
    _stopTicker();
    state = state.copyWith(enabled: false);
  }

  // ---- tap-to-sync ----------------------------------------------------

  /// Register a single tap. Two or more taps within _tapResetMs derive a
  /// new BPM + phase offset; the first tap of a fresh series sets the
  /// phase anchor against the current player position.
  void tap() {
    final pos = _ref.read(playerProvider).position.inMilliseconds;
    final history = List<int>.from(state.tapHistoryMs);

    if (history.isNotEmpty && pos - history.last > _tapResetMs) {
      history.clear();
    }
    history.add(pos);

    // Derive bpm from last 4 taps when we have enough samples.
    double newBpm = state.bpm;
    if (history.length >= 2) {
      final intervals = <int>[];
      final start = history.length >= 5 ? history.length - 5 : 0;
      for (int i = start + 1; i < history.length; i++) {
        intervals.add(history[i] - history[i - 1]);
      }
      final avgMs = intervals.reduce((a, b) => a + b) / intervals.length;
      if (avgMs > 0) {
        // Clamp to 30..240 to reject obvious mistaps.
        final candidate = (60000.0 / avgMs).clamp(30.0, 240.0);
        newBpm = candidate;
      }
    }

    // The first tap in this burst is the phase anchor.
    state = state.copyWith(
      bpm: newBpm,
      phaseOffsetMs: history.first,
      tapHistoryMs: history,
      currentBeatIndex: 0,
    );
    _lastClickedBeatNumber = -1;
    _persistOnTrack();
  }

  /// Manual override (e.g. from BPM analyzer result) -- keeps the existing
  /// phase offset but updates BPM.
  void setBpm(double bpm) {
    state = state.copyWith(bpm: bpm.clamp(30.0, 240.0));
    _persistOnTrack();
  }

  void setBeatsPerBar(int n) {
    state = state.copyWith(beatsPerBar: n.clamp(1, 12));
  }

  // ---- track lifecycle hooks -----------------------------------------

  /// Called by player_provider whenever it loads a new track. If the track
  /// has a stored phase offset, restore it; otherwise reset to a clean
  /// state and use the track's BPM if known.
  void onTrackLoaded({double? bpm, int? phaseOffsetMs}) {
    final wasEnabled = state.enabled;
    state = MetronomeState(
      enabled: false, // always start disabled on a fresh track
      bpm: bpm ?? state.bpm,
      phaseOffsetMs: phaseOffsetMs ?? -1,
      beatsPerBar: state.beatsPerBar,
    );
    _lastClickedBeatNumber = -1;
    if (wasEnabled && state.phaseOffsetMs >= 0) {
      // Restore "on" only if we have an alignment to use.
      enable();
    }
  }

  // ---- ticker / scheduling -------------------------------------------

  void _startTicker() {
    _ticker?.dispose();
    _ticker = Ticker(_onTick)..start();
  }

  void _stopTicker() {
    _ticker?.dispose();
    _ticker = null;
  }

  void _onTick(Duration _) {
    if (!state.enabled) return;
    if (state.phaseOffsetMs < 0 || state.bpm <= 0) return;

    final player = _ref.read(playerProvider);
    if (!player.isPlaying) return;

    final positionMs = player.position.inMilliseconds;
    final intervalMs = state.beatIntervalMs;
    final relMs = positionMs - state.phaseOffsetMs;
    if (relMs < -intervalMs) return; // before alignment

    final beatNumber = (relMs / intervalMs).floor();
    if (beatNumber == _lastClickedBeatNumber) return;

    final beatTimeMs = state.phaseOffsetMs + beatNumber * intervalMs;
    final lateBy = positionMs - beatTimeMs;
    if (lateBy < 0 || lateBy > _beatTriggerWindowMs) return;

    _lastClickedBeatNumber = beatNumber;
    final beatInBar = beatNumber.abs() % state.beatsPerBar;
    final isDownbeat = beatInBar == 0;
    state = state.copyWith(currentBeatIndex: beatInBar);
    // ignore: discarded_futures
    _click.click(isDownbeat: isDownbeat);
  }

  // ---- persistence ----------------------------------------------------

  Future<void> _persistOnTrack() async {
    final track = _ref.read(playerProvider).currentTrack;
    if (track == null || track.isExternal) return;
    final updated = track.copyWith(
      bpm: track.bpm ?? state.bpm.round(),
      metronomePhaseOffsetMs: state.phaseOffsetMs,
    );
    await _storage.saveTrack(updated);
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
