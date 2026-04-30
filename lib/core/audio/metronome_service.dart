import 'package:just_audio/just_audio.dart';

/// Plays short click samples for the metronome.
///
/// Uses two pre-loaded just_audio players (one per click pitch) so each
/// trigger only needs a `seek(0) + play()` round-trip instead of loading
/// the asset every beat. Latency is dominated by the OS audio path; for a
/// practice metronome a few milliseconds of jitter is acceptable.
class MetronomeService {
  MetronomeService._internal();
  static final MetronomeService _instance = MetronomeService._internal();
  factory MetronomeService() => _instance;

  final AudioPlayer _highClick = AudioPlayer();
  final AudioPlayer _lowClick = AudioPlayer();
  bool _initialised = false;
  double _volume = 1.0;

  double get volume => _volume;

  Future<void> _ensureLoaded() async {
    if (_initialised) return;
    await _highClick.setAsset('assets/sounds/click_high.wav');
    await _lowClick.setAsset('assets/sounds/click_low.wav');
    await _highClick.setVolume(_volume);
    await _lowClick.setVolume(_volume);
    // Pre-roll: seek to start so first play() is fast.
    await _highClick.seek(Duration.zero);
    await _lowClick.seek(Duration.zero);
    _initialised = true;
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    if (!_initialised) return;
    await _highClick.setVolume(_volume);
    await _lowClick.setVolume(_volume);
  }

  /// Trigger one click. `isDownbeat` selects the higher-pitched sample.
  /// Safe to call from a hot loop -- if a previous click is still playing
  /// we just rewind it.
  Future<void> click({required bool isDownbeat}) async {
    await _ensureLoaded();
    final player = isDownbeat ? _highClick : _lowClick;
    try {
      await player.seek(Duration.zero);
      // Don't await -- play() returns when playback completes which we
      // don't want to block on.
      // ignore: discarded_futures
      player.play();
    } catch (_) {
      // Asset missing or transient failure; click is best-effort.
    }
  }

  Future<void> dispose() async {
    await _highClick.dispose();
    await _lowClick.dispose();
    _initialised = false;
  }
}
