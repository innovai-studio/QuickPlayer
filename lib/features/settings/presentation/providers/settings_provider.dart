import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/audio_effects_service.dart';
import '../../../../core/storage/storage_service.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final double defaultSpeed;
  final int defaultPitchSemitones;
  final bool showWaveform;
  final bool keepScreenOn;
  final EqPreset defaultFocusMode;

  const SettingsState({
    this.defaultSpeed = 1.0,
    this.defaultPitchSemitones = 0,
    this.showWaveform = true,
    this.keepScreenOn = true,
    this.defaultFocusMode = EqPreset.flat,
  });

  SettingsState copyWith({
    double? defaultSpeed,
    int? defaultPitchSemitones,
    bool? showWaveform,
    bool? keepScreenOn,
    EqPreset? defaultFocusMode,
  }) {
    return SettingsState(
      defaultSpeed: defaultSpeed ?? this.defaultSpeed,
      defaultPitchSemitones: defaultPitchSemitones ?? this.defaultPitchSemitones,
      showWaveform: showWaveform ?? this.showWaveform,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      defaultFocusMode: defaultFocusMode ?? this.defaultFocusMode,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final StorageService _storage = StorageService();
  static const _focusKey = 'defaultFocusModeIndex';

  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _storage.init();
    final focusIndex = _storage.getSetting<int>(_focusKey);
    state = SettingsState(
      defaultSpeed: _storage.getSetting<double>('defaultSpeed') ?? 1.0,
      defaultPitchSemitones: _storage.getSetting<int>('defaultPitchSemitones') ?? 0,
      showWaveform: _storage.getSetting<bool>('showWaveform') ?? true,
      keepScreenOn: _storage.getSetting<bool>('keepScreenOn') ?? true,
      defaultFocusMode: _resolveFocusPreset(focusIndex),
    );
  }

  Future<void> setDefaultSpeed(double speed) async {
    await _storage.setSetting('defaultSpeed', speed);
    state = state.copyWith(defaultSpeed: speed);
  }

  Future<void> setDefaultPitchSemitones(int semitones) async {
    await _storage.setSetting('defaultPitchSemitones', semitones);
    state = state.copyWith(defaultPitchSemitones: semitones);
  }

  Future<void> setShowWaveform(bool show) async {
    await _storage.setSetting('showWaveform', show);
    state = state.copyWith(showWaveform: show);
  }

  Future<void> setKeepScreenOn(bool keep) async {
    await _storage.setSetting('keepScreenOn', keep);
    state = state.copyWith(keepScreenOn: keep);
  }

  Future<void> setDefaultFocusMode(EqPreset preset) async {
    await _storage.setSetting(_focusKey, preset.index);
    state = state.copyWith(defaultFocusMode: preset);
  }

  Future<void> resetToDefaults() async {
    await _storage.setSetting('defaultSpeed', 1.0);
    await _storage.setSetting('defaultPitchSemitones', 0);
    await _storage.setSetting('showWaveform', true);
    await _storage.setSetting('keepScreenOn', true);
    await _storage.setSetting(_focusKey, EqPreset.flat.index);
    state = const SettingsState();
  }

  /// Map a stored index back to an enum value, falling back to flat if the
  /// stored index is out of range (e.g. preset removed in a later version).
  EqPreset _resolveFocusPreset(int? index) {
    if (index == null) return EqPreset.flat;
    if (index < 0 || index >= EqPreset.values.length) return EqPreset.flat;
    return EqPreset.values[index];
  }
}
