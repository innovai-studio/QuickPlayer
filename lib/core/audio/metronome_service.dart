import 'package:flutter/services.dart';

/// Plays short click samples for the metronome.
///
/// Backed by a thin MethodChannel onto Android's SoundPool. The earlier
/// just_audio + audioplayers attempts both fought the audio focus model
/// once just_audio_background was wired up: the song would either pause
/// on every click (when focus was requested) or the click would simply
/// be silent (when focus was set to none). SoundPool side-steps the
/// whole focus model -- it's the canonical Android API for short
/// non-focus-requesting SFX that mixes into the music stream.
///
/// On non-Android platforms every method short-circuits silently so
/// future iOS support can plug in a separate AVAudioPlayerNode pool
/// without touching the metronome state machine.
class MetronomeService {
  MetronomeService._internal();
  static final MetronomeService _instance = MetronomeService._internal();
  factory MetronomeService() => _instance;

  static const _channel = MethodChannel('com.quickplayer/sound_pool');

  int? _highSoundId;
  int? _lowSoundId;
  bool _initialised = false;
  double _volume = 1.0;

  double get volume => _volume;

  Future<void> _ensureLoaded() async {
    if (_initialised) return;
    try {
      _highSoundId = await _channel.invokeMethod<int>('load', {
        'asset': 'assets/sounds/click_high.wav',
      });
      _lowSoundId = await _channel.invokeMethod<int>('load', {
        'asset': 'assets/sounds/click_low.wav',
      });
      _initialised = true;
    } on PlatformException {
      // Platform doesn't support our SoundPool channel (e.g. running on
      // Linux desktop). Leave _initialised = false so click() short-
      // circuits without raising.
    } on MissingPluginException {
      // Same path on platforms where the channel isn't registered.
    }
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    // SoundPool's per-stream volume is supplied at play() time; nothing
    // to push to the platform here.
  }

  /// Trigger one click. `isDownbeat` selects the higher-pitched sample.
  Future<void> click({required bool isDownbeat}) async {
    await _ensureLoaded();
    if (_volume <= 0) return;
    final id = isDownbeat ? _highSoundId : _lowSoundId;
    if (id == null) return;
    try {
      await _channel.invokeMethod<int>('play', {
        'soundId': id,
        'volume': _volume,
      });
    } on PlatformException {
      // best-effort; click is non-critical
    } on MissingPluginException {
      // ignore
    }
  }

  Future<void> dispose() async {
    if (!_initialised) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
    _highSoundId = null;
    _lowSoundId = null;
    _initialised = false;
  }
}
