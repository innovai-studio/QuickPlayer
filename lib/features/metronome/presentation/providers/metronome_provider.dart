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
    this.volume = 0.7,
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
      bpmIsUserSet: true,
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
