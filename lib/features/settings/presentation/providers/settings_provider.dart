import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/storage/storage_service.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

class SettingsState {
  final double defaultSpeed;
  final int defaultPitchSemitones;
  final bool showWaveform;
  final bool keepScreenOn;

  const SettingsState({
    this.defaultSpeed = 1.0,
    this.defaultPitchSemitones = 0,
    this.showWaveform = true,
    this.keepScreenOn = true,
  });

  SettingsState copyWith({
    double? defaultSpeed,
    int? defaultPitchSemitones,
    bool? showWaveform,
    bool? keepScreenOn,
  }) {
    return SettingsState(
      defaultSpeed: defaultSpeed ?? this.defaultSpeed,
      defaultPitchSemitones: defaultPitchSemitones ?? this.defaultPitchSemitones,
      showWaveform: showWaveform ?? this.showWaveform,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final StorageService _storage = StorageService();

  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _storage.init();
    state = SettingsState(
      defaultSpeed: _storage.getSetting<double>('defaultSpeed') ?? 1.0,
      defaultPitchSemitones: _storage.getSetting<int>('defaultPitchSemitones') ?? 0,
      showWaveform: _storage.getSetting<bool>('showWaveform') ?? true,
      keepScreenOn: _storage.getSetting<bool>('keepScreenOn') ?? true,
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

  Future<void> resetToDefaults() async {
    await _storage.setSetting('defaultSpeed', 1.0);
    await _storage.setSetting('defaultPitchSemitones', 0);
    await _storage.setSetting('showWaveform', true);
    await _storage.setSetting('keepScreenOn', true);
    state = const SettingsState();
  }
}
