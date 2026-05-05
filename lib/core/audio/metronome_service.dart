import 'package:just_audio/just_audio.dart';

/// Plays short click samples for the metronome.
///
/// One pre-loaded player per pitch -- earlier versions layered multiple
/// players to push perceived loudness higher, but the per-player play()
/// jitter (~5-30 ms) became audible as a smeared "echo" attack. A single
/// player with a heavily-clipped, harmonic-rich source produces the same
/// peak amplitude (PCM int16 cap) without sync drift, and the source
/// WAVs themselves carry the loudness now.
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
    await _highClick.seek(Duration.zero);
    await _lowClick.seek(Duration.zero);
    await _highClick.setVolume(_volume);
    await _lowClick.setVolume(_volume);
    _initialised = true;
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    if (!_initialised) return;
    await _highClick.setVolume(_volume);
    await _lowClick.setVolume(_volume);
  }

  /// Trigger one click. `isDownbeat` selects the higher-pitched sample.
  Future<void> click({required bool isDownbeat}) async {
    await _ensureLoaded();
    if (_volume <= 0) return;
    final player = isDownbeat ? _highClick : _lowClick;
    try {
      // ignore: discarded_futures
      player.seek(Duration.zero).then((_) {
        // ignore: discarded_futures
        player.play();
      });
    } catch (_) {
      // best-effort; click is non-critical
    }
  }

  Future<void> dispose() async {
    await _highClick.dispose();
    await _lowClick.dispose();
    _initialised = false;
  }
}
