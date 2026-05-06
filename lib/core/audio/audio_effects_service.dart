import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

/// Focus presets exposed in the UI. Index is persisted, so the order
/// must remain stable -- append new values rather than reordering.
///
/// `custom` is a sentinel meaning "use whatever bandLevels are currently in
/// the player state instead of the canned table". It surfaces in the chip
/// row as soon as the user manually drags any band slider.
enum EqPreset {
  flat,
  vocalBoost,
  guitarBoost,
  drumFocus,
  bassCut,
  custom,
}

extension EqPresetX on EqPreset {
  /// Human-readable label shown on the Focus chip.
  String get label {
    switch (this) {
      case EqPreset.flat:
        return 'None';
      case EqPreset.vocalBoost:
        return 'Vocal';
      case EqPreset.guitarBoost:
        return 'Guitar';
      case EqPreset.drumFocus:
        return 'Drums';
      case EqPreset.bassCut:
        return 'Bass-';
      case EqPreset.custom:
        return 'Custom';
    }
  }

  /// Whether this preset has a fixed band table. `custom` doesn't.
  bool get isCanned => this != EqPreset.custom;
}

/// Capabilities reported by the platform after init.
class AudioEffectsCapabilities {
  final bool supported;
  final int numberOfBands;
  final List<int> centerFrequenciesMilliHz;
  final int minBandLevelMillibel;
  final int maxBandLevelMillibel;
  final bool hasBassBoost;

  const AudioEffectsCapabilities({
    required this.supported,
    this.numberOfBands = 0,
    this.centerFrequenciesMilliHz = const [],
    this.minBandLevelMillibel = 0,
    this.maxBandLevelMillibel = 0,
    this.hasBassBoost = false,
  });

  static const unsupported = AudioEffectsCapabilities(supported: false);

  factory AudioEffectsCapabilities.fromMap(Map<dynamic, dynamic> map) {
    return AudioEffectsCapabilities(
      supported: map['supported'] as bool? ?? false,
      numberOfBands: map['numberOfBands'] as int? ?? 0,
      centerFrequenciesMilliHz: (map['centerFrequenciesMilliHz'] as List?)
              ?.map((e) => e as int)
              .toList() ??
          const [],
      minBandLevelMillibel: map['minBandLevelMillibel'] as int? ?? 0,
      maxBandLevelMillibel: map['maxBandLevelMillibel'] as int? ?? 0,
      hasBassBoost: map['hasBassBoost'] as bool? ?? false,
    );
  }
}

/// Bridges to the Android AudioEffects MethodChannel.
///
/// On non-Android platforms every call short-circuits and reports
/// "unsupported" without touching the channel, so callers don't need
/// to gate behaviour on Platform.isAndroid themselves.
class AudioEffectsService {
  AudioEffectsService._internal();
  static final AudioEffectsService _instance = AudioEffectsService._internal();
  factory AudioEffectsService() => _instance;

  static const _channel = MethodChannel('com.quickplayer/audio_effects');

  AudioEffectsCapabilities _capabilities = AudioEffectsCapabilities.unsupported;
  int? _boundSessionId;
  EqPreset _activePreset = EqPreset.flat;

  /// Cache of the most recent applyCustom(). When the audio session is
  /// rebound (typically on track change) we replay these values so the
  /// new Equalizer doesn't snap back to flat -- applyPreset(custom) is
  /// a no-op by design, so without the cache the user's tuning is lost
  /// every time tracks switch.
  List<int>? _lastCustomBandLevels;
  int _lastCustomBassStrength = 0;

  AudioEffectsCapabilities get capabilities => _capabilities;
  EqPreset get activePreset => _activePreset;

  /// Whether the current device + platform combination can apply EQ presets.
  bool get isAvailable => Platform.isAndroid && _capabilities.supported;

  /// Bind effects to the AudioTrack session reported by just_audio.
  /// Safe to call repeatedly with the same id; will rebuild on a new id.
  Future<void> attachToSession(int sessionId) async {
    if (!Platform.isAndroid) {
      _capabilities = AudioEffectsCapabilities.unsupported;
      return;
    }
    if (sessionId == 0 || sessionId == _boundSessionId) return;

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'init',
        {'sessionId': sessionId},
      );
      _capabilities = result == null
          ? AudioEffectsCapabilities.unsupported
          : AudioEffectsCapabilities.fromMap(result);
      _boundSessionId = sessionId;

      // Re-apply the active preset against the freshly-bound session.
      // applyPreset is a no-op for custom (no canned table to reach for),
      // so for custom we replay the cached band levels directly. Without
      // this, switching tracks would silently reset the user's tuning.
      if (_capabilities.supported) {
        if (_activePreset == EqPreset.custom &&
            _lastCustomBandLevels != null) {
          await applyCustom(
            bandLevelsMillibel: _lastCustomBandLevels!,
            bassStrengthMilli: _lastCustomBassStrength,
          );
        } else if (_activePreset != EqPreset.flat) {
          await applyPreset(_activePreset);
        }
      }
    } on PlatformException {
      _capabilities = AudioEffectsCapabilities.unsupported;
    }
  }

  /// Apply a preset. No-op when effects aren't available -- callers can
  /// still call this freely on iOS / Linux without checking platform.
  ///
  /// Custom is a no-op here -- callers should drive applyCustom directly.
  Future<void> applyPreset(EqPreset preset) async {
    _activePreset = preset;
    if (!isAvailable) return;
    if (!preset.isCanned) return;

    final config = _presetConfig(preset);
    try {
      await _channel.invokeMethod<void>('applyPreset', {
        'bandLevels': config.bandLevelsMillibel,
        'bassStrength': config.bassStrengthMilli,
      });
    } on PlatformException {
      // Swallow -- we'll surface a single capability flag instead of erroring
      // every call. The next attachToSession will re-detect support.
    }
  }

  /// Push raw band levels + bass strength to the platform without going
  /// through a preset. Used when the user is dragging EQ sliders.
  Future<void> applyCustom({
    required List<int> bandLevelsMillibel,
    required int bassStrengthMilli,
  }) async {
    _activePreset = EqPreset.custom;
    _lastCustomBandLevels = List<int>.from(bandLevelsMillibel);
    _lastCustomBassStrength = bassStrengthMilli;
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('applyPreset', {
        'bandLevels': bandLevelsMillibel,
        'bassStrength': bassStrengthMilli,
      });
    } on PlatformException {
      // ignore; capability flag will catch persistent failures
    }
  }

  /// Lookup the canned preset's band levels (5-band shape). Used by the
  /// player state to seed the visualiser when a preset is selected.
  /// Returns null for `custom` since it has no canonical table.
  List<int>? presetBandLevels(EqPreset preset) {
    if (!preset.isCanned) return null;
    return List<int>.from(_presetConfig(preset).bandLevelsMillibel);
  }

  int presetBassStrength(EqPreset preset) {
    if (!preset.isCanned) return 0;
    return _presetConfig(preset).bassStrengthMilli;
  }

  /// Master toggle. Use sparingly -- applying EqPreset.flat already produces
  /// silence-on-the-EQ behaviour.
  Future<void> setEnabled(bool enabled) async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } on PlatformException {
      // ignore
    }
  }

  /// Attach a LoudnessEnhancer to an arbitrary audio session id (e.g.
  /// the metronome's click players) at the requested gain in millibel.
  /// Keyed by session id on the platform so each click pitch can have
  /// its own enhancer alongside the main song's Equalizer + BassBoost.
  Future<bool> attachLoudnessToSession(
    int sessionId, {
    int gainMillibel = 1500,
  }) async {
    if (!Platform.isAndroid) return false;
    if (sessionId == 0) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('attachLoudness', {
        'sessionId': sessionId,
        'gainMillibel': gainMillibel,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> detachLoudnessFromSession(int sessionId) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('detachLoudness', {
        'sessionId': sessionId,
      });
    } on PlatformException {
      // ignore
    }
  }

  Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('release');
    } on PlatformException {
      // ignore
    }
    _boundSessionId = null;
    _capabilities = AudioEffectsCapabilities.unsupported;
  }

  /// 5-band preset table.
  ///
  /// Bands map to roughly 60 / 230 / 910 / 3.6k / 14k Hz on a typical
  /// device. The Kotlin handler interpolates onto whatever band count
  /// the device exposes, so these values stay device-independent.
  ///
  /// Levels are millibel (100 == +1 dB). Bass strength is milli-units
  /// (0..1000) for android.media.audiofx.BassBoost.
  _PresetConfig _presetConfig(EqPreset preset) {
    switch (preset) {
      case EqPreset.flat:
        return const _PresetConfig([0, 0, 0, 0, 0], 0);
      case EqPreset.vocalBoost:
        return const _PresetConfig([-300, -200, 400, 500, 0], 0);
      case EqPreset.guitarBoost:
        return const _PresetConfig([-200, 0, 300, 400, 200], 0);
      case EqPreset.drumFocus:
        return const _PresetConfig([400, 200, -200, 0, 300], 600);
      case EqPreset.bassCut:
        return const _PresetConfig([-800, -400, 0, 0, 0], 0);
      case EqPreset.custom:
        // Defensive: callers should never invoke the canned path for
        // custom -- but if they do, treat it as flat.
        return const _PresetConfig([0, 0, 0, 0, 0], 0);
    }
  }
}

class _PresetConfig {
  final List<int> bandLevelsMillibel;
  final int bassStrengthMilli;
  const _PresetConfig(this.bandLevelsMillibel, this.bassStrengthMilli);
}
