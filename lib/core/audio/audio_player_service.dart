import 'dart:async';
import 'dart:math';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:audio_session/audio_session.dart';
import 'audio_effects_service.dart';
import 'spectrum_service.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final AudioEffectsService _effects = AudioEffectsService();
  final SpectrumService _spectrum = SpectrumService();
  StreamSubscription<int?>? _sessionIdSubscription;
  int? _lastSessionId;
  bool _spectrumDesired = false;

  /// Stream of audio session ids forwarded from just_audio so callers
  /// (PlayerNotifier) can react when a new session is bound.
  Stream<int?> get sessionIdStream => _player.androidAudioSessionIdStream;
  int? get lastSessionId => _lastSessionId;
  bool get spectrumRunning => _spectrum.isRunning;

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
      if (id == null) return;
      _lastSessionId = id;
      _effects.attachToSession(id);
      // If the user has opted into spectrum, rebind it to the new session.
      if (_spectrumDesired) _spectrum.start(id);
    });
  }

  /// Toggle spectrum capture. Returns false when the platform reports
  /// the visualiser unavailable (permission denied or device unsupported).
  Future<bool> setSpectrumEnabled(bool enabled) async {
    _spectrumDesired = enabled;
    if (!enabled) {
      await _spectrum.stop();
      return false;
    }
    final id = _lastSessionId;
    if (id == null || id == 0) {
      // No session yet -- the listener above will start it once one arrives.
      return true;
    }
    return _spectrum.start(id);
  }

  /// Load audio from file path with optional metadata for the system
  /// notification / lockscreen UI. Without metadata the controls show
  /// the file path which looks awful, so callers should pass the
  /// track's display name + artist when available.
  Future<Duration?> loadFile(
    String filePath, {
    String? id,
    String? title,
    String? artist,
    String? album,
  }) async {
    try {
      await _player.stop();

      // The MediaItem tag is what just_audio_background reads to
      // populate the foreground notification + lockscreen + Bluetooth
      // metadata. id must be unique per track so MediaSession can
      // distinguish them when stepping through a queue.
      final source = AudioSource.uri(
        Uri.file(filePath),
        tag: MediaItem(
          id: id ?? filePath,
          title: title ?? _filenameOf(filePath),
          artist: artist,
          album: album,
        ),
      );
      final duration = await _player.setAudioSource(source);
      return duration;
    } catch (e) {
      rethrow;
    }
  }

  String _filenameOf(String path) {
    final slash = path.lastIndexOf('/');
    final raw = slash < 0 ? path : path.substring(slash + 1);
    // Drop extension for prettier display.
    final dot = raw.lastIndexOf('.');
    return dot <= 0 ? raw : raw.substring(0, dot);
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
    await _spectrum.stop();
    await _effects.release();
    await _player.dispose();
  }
}
