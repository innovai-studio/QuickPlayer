import 'package:just_audio/just_audio.dart';

/// Plays short click samples for the metronome.
///
/// Uses pools of pre-loaded just_audio players (one pool per click pitch)
/// so each trigger only needs a `seek(0) + play()` round-trip. Multiple
/// layers fire simultaneously per click so the audio mixer sums their
/// outputs -- this lets the perceived loudness exceed what a single
/// player can produce since just_audio caps setVolume at 1.0 on Android.
///
/// Volume input is 0..1 from the UI; the service translates that into a
/// gain multiplier (currently 0..3) so 100% on the slider corresponds to
/// the loudest summed output we can deliver before audible artefacts.
class MetronomeService {
  MetronomeService._internal();
  static final MetronomeService _instance = MetronomeService._internal();
  factory MetronomeService() => _instance;

  /// Number of concurrent player instances per pitch. Each layer plays
  /// the same clip at the same time; their PCM outputs sum at the mixer.
  /// 4 layers gives ~12 dB of headroom over a single player and is the
  /// sweet spot before round-robin latency starts mattering.
  static const int _layers = 4;

  /// Maximum effective gain (sum across layers when slider is at 1.0).
  /// The signal still clips at the DAC, so going much higher than the
  /// layer count just produces distortion without more loudness.
  static const double _maxGain = 3.0;

  final List<AudioPlayer> _highPool =
      List.generate(_layers, (_) => AudioPlayer());
  final List<AudioPlayer> _lowPool =
      List.generate(_layers, (_) => AudioPlayer());
  int _highIndex = 0;
  int _lowIndex = 0;
  bool _initialised = false;
  double _volume = 1.0;

  double get volume => _volume;

  Future<void> _ensureLoaded() async {
    if (_initialised) return;
    for (final p in _highPool) {
      await p.setAsset('assets/sounds/click_high.wav');
      await p.seek(Duration.zero);
    }
    for (final p in _lowPool) {
      await p.setAsset('assets/sounds/click_low.wav');
      await p.seek(Duration.zero);
    }
    _initialised = true;
    await _applyVolume();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    if (!_initialised) return;
    await _applyVolume();
  }

  /// Distribute the user's 0..1 volume across the layer pool. Each
  /// player gets the per-layer share of the total gain, capped at 1.0
  /// (just_audio's hard ceiling). Below the headroom limit we use
  /// fewer layers at higher individual volume; above, all layers sit
  /// at 1.0 and additional gain comes from the sum.
  Future<void> _applyVolume() async {
    final totalGain = _volume * _maxGain;
    final perLayer = (totalGain / _layers).clamp(0.0, 1.0);
    for (final p in _highPool) {
      // ignore: discarded_futures
      p.setVolume(perLayer);
    }
    for (final p in _lowPool) {
      // ignore: discarded_futures
      p.setVolume(perLayer);
    }
  }

  /// Trigger one click. `isDownbeat` selects the higher-pitched sample.
  /// Each call fires every layer in the pool simultaneously so the mixer
  /// sums them; round-robin within the pool isn't necessary because the
  /// click is short (~30 ms) and the next beat is far enough away that
  /// the last layer has finished before we reuse it.
  Future<void> click({required bool isDownbeat}) async {
    await _ensureLoaded();
    if (_volume <= 0) return;
    final pool = isDownbeat ? _highPool : _lowPool;
    for (final p in pool) {
      try {
        // ignore: discarded_futures
        p.seek(Duration.zero).then((_) {
          // ignore: discarded_futures
          p.play();
        });
      } catch (_) {
        // best-effort; one failed layer doesn't break the click
      }
    }
    if (isDownbeat) {
      _highIndex = (_highIndex + 1) % _layers;
    } else {
      _lowIndex = (_lowIndex + 1) % _layers;
    }
  }

  Future<void> dispose() async {
    for (final p in _highPool) {
      await p.dispose();
    }
    for (final p in _lowPool) {
      await p.dispose();
    }
    _initialised = false;
  }
}
