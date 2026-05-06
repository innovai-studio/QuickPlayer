import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'audio_effects_service.dart';

/// Plays short click samples for the metronome.
///
/// One pre-loaded player per pitch. The system audio path on Android
/// caps just_audio's setVolume at 1.0, so we attach a native
/// LoudnessEnhancer (audiofx) to each click player's audio session for
/// an extra ~+15 dB of headroom -- subjectively roughly 2x louder than
/// uncompensated playback. Without this the click reaches int16 PCM
/// peak at 100% on the slider but still sounds quiet next to a loud
/// song.
class MetronomeService {
  MetronomeService._internal();
  static final MetronomeService _instance = MetronomeService._internal();
  factory MetronomeService() => _instance;

  static const int _loudnessGainMillibel = 3000;

  final AudioPlayer _highClick = AudioPlayer();
  final AudioPlayer _lowClick = AudioPlayer();
  bool _initialised = false;
  double _volume = 1.0;
  int? _highSessionId;
  int? _lowSessionId;
  StreamSubscription<int?>? _highSessionSub;
  StreamSubscription<int?>? _lowSessionSub;

  double get volume => _volume;

  Future<void> _ensureLoaded() async {
    if (_initialised) return;
    await _highClick.setAsset('assets/sounds/click_high.wav');
    await _lowClick.setAsset('assets/sounds/click_low.wav');
    await _highClick.seek(Duration.zero);
    await _lowClick.seek(Duration.zero);
    await _highClick.setVolume(_volume);
    await _lowClick.setVolume(_volume);

    // just_audio doesn't expose the audio session id until ExoPlayer has
    // bound an AudioTrack, which only happens after the first play().
    // Subscribe to the stream so the LoudnessEnhancer attaches as soon
    // as a session id appears for each player.
    _highSessionSub = _highClick.androidAudioSessionIdStream.listen((id) {
      if (id != null && id != _highSessionId) {
        _highSessionId = id;
        // ignore: discarded_futures
        AudioEffectsService().attachLoudnessToSession(id,
            gainMillibel: _loudnessGainMillibel);
      }
    });
    _lowSessionSub = _lowClick.androidAudioSessionIdStream.listen((id) {
      if (id != null && id != _lowSessionId) {
        _lowSessionId = id;
        // ignore: discarded_futures
        AudioEffectsService().attachLoudnessToSession(id,
            gainMillibel: _loudnessGainMillibel);
      }
    });

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
    await _highSessionSub?.cancel();
    await _lowSessionSub?.cancel();
    final effects = AudioEffectsService();
    if (_highSessionId != null) {
      await effects.detachLoudnessFromSession(_highSessionId!);
    }
    if (_lowSessionId != null) {
      await effects.detachLoudnessFromSession(_lowSessionId!);
    }
    await _highClick.dispose();
    await _lowClick.dispose();
    _initialised = false;
  }
}
