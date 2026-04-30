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
/// Common time signatures offered in the UI. Beats-per-bar drives both
/// the indicator dots and the downbeat detection that selects the high
/// click. Compound signatures (6/8, 12/8) collapse to their dotted-quarter
/// pulse rather than counting eighths -- a learner-friendly default.
enum TimeSignature {
  twoFour(2, 4, '2/4'),
  threeFour(3, 4, '3/4'),
  fourFour(4, 4, '4/4'),
  sixEight(6, 8, '6/8'),
  twelveEight(12, 8, '12/8');

  const TimeSignature(this.numerator, this.denominator, this.label);
  final int numerator;
  final int denominator;
  final String label;

  /// Number of audible clicks per bar. For compound signatures we count
  /// the dotted-quarter pulse, not every eighth.
  int get beatsPerBar {
    if (this == TimeSignature.sixEight) return 2;
    if (this == TimeSignature.twelveEight) return 4;
    return numerator;
  }
}

class MetronomeState {
  final bool enabled;
  final double bpm;
  final int phaseOffsetMs;
  final TimeSignature timeSignature;
  final int currentBeatIndex; // 0..beatsPerBar-1, drives the indicator lights
  final List<int> tapHistoryMs; // recent tap timestamps for live calibration
  final double volume; // 0..1

  /// Whether the user has explicitly set a BPM (via tap-to-sync). When
  /// false, late-arriving track BPM analysis is allowed to overwrite the
  /// default; when true, analysis is ignored to respect user intent.
  final bool bpmIsUserSet;

  const MetronomeState({
    this.enabled = false,
    this.bpm = 120,
    this.phaseOffsetMs = -1,
    this.timeSignature = TimeSignature.fourFour,
    this.currentBeatIndex = 0,
    this.tapHistoryMs = const [],
    this.volume = 1.0,
    this.bpmIsUserSet = false,
  });

  bool get isAligned => phaseOffsetMs >= 0 && bpm > 0;
  double get beatIntervalMs => 60000.0 / bpm;
  int get beatsPerBar => timeSignature.beatsPerBar;

  MetronomeState copyWith({
    bool? enabled,
    double? bpm,
    int? phaseOffsetMs,
    TimeSignature? timeSignature,
    int? currentBeatIndex,
    List<int>? tapHistoryMs,
    double? volume,
    bool? bpmIsUserSet,
  }) {
    return MetronomeState(
      enabled: enabled ?? this.enabled,
      bpm: bpm ?? this.bpm,
      phaseOffsetMs: phaseOffsetMs ?? this.phaseOffsetMs,
      timeSignature: timeSignature ?? this.timeSignature,
      currentBeatIndex: currentBeatIndex ?? this.currentBeatIndex,
      tapHistoryMs: tapHistoryMs ?? this.tapHistoryMs,
      volume: volume ?? this.volume,
      bpmIsUserSet: bpmIsUserSet ?? this.bpmIsUserSet,
    );
  }
}

final metronomeProvider =
    StateNotifierProvider<MetronomeNotifier, MetronomeState>((ref) {
  final notifier = MetronomeNotifier(ref);

  // Re-bind metronome whenever the player loads a different track. Compare
  // ids rather than full Track instances so transient copyWith updates
  // (lastPlayedAt, BPM analysis arriving) don't trigger a reset.
  ref.listen(playerProvider.select((s) => s.currentTrack?.id),
      (prev, next) {
    if (prev == next) return;
    final track = ref.read(playerProvider).currentTrack;
    notifier.onTrackLoaded(
      bpm: track?.bpm?.toDouble(),
      phaseOffsetMs: track?.metronomePhaseOffsetMs,
    );
  });

  // BPM analysis is async -- when it lands after the track is already
  // loaded, push the result into the metronome (unless the user has
  // already tapped a value).
  ref.listen(playerProvider.select((s) => s.currentTrack?.bpm), (prev, next) {
    if (next == null || next == prev) return;
    notifier.onAnalyzerBpm(next);
  });

  return notifier;
});

class MetronomeNotifier extends StateNotifier<MetronomeState> {
  final Ref _ref;
  final MetronomeService _click = MetronomeService();
  final StorageService _storage = StorageService();
  Ticker? _ticker;
  int _lastClickedBeatNumber = -1;

  /// Beat number that should be flagged as the downbeat. Default 0 (start
  /// of track). After tap-to-sync we move it forward so the first click
  /// after the user's last tap fires as the downbeat -- aligns with the
  /// "tap a full bar then expect 滴" cadence learners use.
  int _downbeatAnchor = 0;

  /// Wall-clock anchor for smooth click scheduling. Player position only
  /// updates in 100-200 ms chunks, which is too coarse for jitter-free
  /// click cadence. We capture (wallNowMs, playerPosMs) the moment the
  /// metronome enables / re-syncs, then derive each tick's effective
  /// position by interpolating wall-clock forward. We periodically check
  /// the result against the actual player position to catch pauses,
  /// seeks, and A-B-loop jumps; large deviations trigger a re-anchor.
  int? _anchorWallMs;
  int? _anchorPosMs;
  static const int _resyncThresholdMs = 250;

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
    // Allow turning the metronome on without an explicit tap-to-sync.
    // We default the phase anchor to 0 so clicks start from the track's
    // beginning at the current bpm. Users who want to lock to the song
    // can refine later with the Tap button.
    final phase = state.phaseOffsetMs >= 0 ? state.phaseOffsetMs : 0;
    state = state.copyWith(enabled: true, phaseOffsetMs: phase);
    _lastClickedBeatNumber = -1;
    _resetAnchor();
    _startTicker();
  }

  Future<void> disable() async {
    if (!state.enabled) return;
    _stopTicker();
    _resetAnchor();
    state = state.copyWith(enabled: false);
  }

  void _resetAnchor() {
    _anchorWallMs = null;
    _anchorPosMs = null;
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
      bpmIsUserSet: true,
    );

    // The user already heard the audio they tapped on, so don't fire a
    // click for the beat slot containing the most recent tap. Mark it
    // as "already clicked" -- the next tick will pick up from the next
    // boundary forward.
    final intervalMs = 60000.0 / newBpm;
    final relLast = (history.last - history.first).toDouble();
    final lastBeat = (relLast / intervalMs).floor();
    _lastClickedBeatNumber = lastBeat;

    // Treat the next beat after the user's final tap as the downbeat. If
    // the user counted "1, 2, 3, 4" while tapping, the next click should
    // be "1" of the new bar -- the high "滴" tick learners listen for.
    _downbeatAnchor = lastBeat + 1;

    // Re-anchor wall-clock so the next click fires on cadence with the
    // tap, not a lagging position-stream value.
    _resetAnchor();

    _persistOnTrack();
  }

  /// Manual override (e.g. from BPM analyzer result) -- keeps the existing
  /// phase offset but updates BPM.
  void setBpm(double bpm) {
    state = state.copyWith(bpm: bpm.clamp(30.0, 240.0));
    _persistOnTrack();
  }

  /// Update BPM from the audio analyser's result. Respects any value the
  /// user has already locked in via tap-to-sync.
  void onAnalyzerBpm(int bpm) {
    if (state.bpmIsUserSet) return;
    state = state.copyWith(bpm: bpm.toDouble().clamp(30.0, 240.0));
  }

  void setTimeSignature(TimeSignature ts) {
    state = state.copyWith(
      timeSignature: ts,
      currentBeatIndex: 0,
    );
    _lastClickedBeatNumber = -1;
  }

  // ---- volume ---------------------------------------------------------

  void nudgeVolume(double delta) {
    final next = (state.volume + delta).clamp(0.0, 1.0);
    state = state.copyWith(volume: next);
    // ignore: discarded_futures
    _click.setVolume(next);
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
      timeSignature: state.timeSignature, // carry signature across tracks
      volume: state.volume, // carry volume too
      // bpmIsUserSet stays default false on track switch -- analysis can
      // freely seed BPM until the user taps to override.
    );
    _lastClickedBeatNumber = -1;
    _downbeatAnchor = 0;
    _resetAnchor();
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
    if (!player.isPlaying) {
      // Pause: drop the wall-clock anchor so the next play() re-locks
      // against the resumed position cleanly.
      _resetAnchor();
      return;
    }

    final actualPosMs = player.position.inMilliseconds;
    final wallNowMs = DateTime.now().millisecondsSinceEpoch;

    // (Re)anchor wall-clock against the current player position when we
    // either don't have an anchor yet or the actual position has drifted
    // far from the prediction (seek, A-B loop wrap, big lag).
    int effectivePosMs;
    if (_anchorWallMs == null || _anchorPosMs == null) {
      _anchorWallMs = wallNowMs;
      _anchorPosMs = actualPosMs;
      effectivePosMs = actualPosMs;
    } else {
      final predictedPos = _anchorPosMs! + (wallNowMs - _anchorWallMs!);
      if ((predictedPos - actualPosMs).abs() > _resyncThresholdMs) {
        _anchorWallMs = wallNowMs;
        _anchorPosMs = actualPosMs;
        effectivePosMs = actualPosMs;
      } else {
        effectivePosMs = predictedPos;
      }
    }

    final intervalMs = state.beatIntervalMs;
    final relMs = effectivePosMs - state.phaseOffsetMs;
    if (relMs < 0) return;

    final beatNumber = (relMs / intervalMs).floor();
    if (beatNumber <= _lastClickedBeatNumber) return;

    _lastClickedBeatNumber = beatNumber;
    // beatInBar is computed relative to the downbeat anchor so the user's
    // last tap counts as the previous bar's last beat and the next click
    // is "1".
    final relBeat = beatNumber - _downbeatAnchor;
    final beatInBar =
        ((relBeat % state.beatsPerBar) + state.beatsPerBar) % state.beatsPerBar;
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
