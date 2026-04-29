import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'audio_effects_service.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final AudioEffectsService _effects = AudioEffectsService();
  StreamSubscription<int?>? _sessionIdSubscription;

  // Streams
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<bool> get playingStream => _player.playingStream;

  // Getters
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get playing => _player.playing;
  double get speed => _player.speed;
  double get pitch => _player.pitch;

  AudioPlayerService() {
    _init();
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _sessionIdSubscription = _player.androidAudioSessionIdStream.listen((id) {
      if (id != null) _effects.attachToSession(id);
    });
  }

  /// Load audio from file path
  Future<Duration?> loadFile(String filePath) async {
    try {
      // Stop current playback and reset player state before loading new file
      await _player.stop();

      final duration = await _player.setFilePath(filePath);
      return duration;
    } catch (e) {
      rethrow;
    }
  }

  /// Play
  Future<void> play() async {
    await _player.play();
  }

  /// Pause
  Future<void> pause() async {
    await _player.pause();
  }

  /// Stop
  Future<void> stop() async {
    await _player.stop();
  }

  /// Seek to position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Set playback speed (0.25 - 2.0)
  /// Note: just_audio maintains pitch when changing speed
  Future<void> setSpeed(double speed) async {
    final clampedSpeed = speed.clamp(0.25, 2.0);
    await _player.setSpeed(clampedSpeed);
  }

  /// Set pitch (semitones: -12 to +12)
  /// Converts semitones to pitch ratio
  Future<void> setPitchSemitones(int semitones) async {
    final clampedSemitones = semitones.clamp(-12, 12);
    final pitchRatio = pow(2, clampedSemitones / 12).toDouble();
    await _player.setPitch(pitchRatio);
  }

  /// Set loop mode
  Future<void> setLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
  }

  /// Set clip for A-B loop
  Future<void> setClip({Duration? start, Duration? end}) async {
    await _player.setClip(start: start, end: end);
  }

  /// Clear clip (only if player has a source)
  Future<void> clearClip() async {
    // Only clear clip if there's a source loaded
    if (_player.audioSource != null) {
      await _player.setClip(start: null, end: null);
    }
  }

  /// Dispose
  Future<void> dispose() async {
    await _sessionIdSubscription?.cancel();
    await _effects.release();
    await _player.dispose();
  }
}
