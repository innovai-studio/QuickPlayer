import 'package:flutter/services.dart';

/// Position/state snapshot streamed from the native mixer.
class MixerState {
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool playing;
  final bool ready;

  const MixerState({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.playing,
    required this.ready,
  });

  factory MixerState.fromMap(Map m) => MixerState(
        position: Duration(milliseconds: (m['pos'] as num?)?.toInt() ?? 0),
        duration: Duration(milliseconds: (m['dur'] as num?)?.toInt() ?? 0),
        buffered: Duration(milliseconds: (m['buffered'] as num?)?.toInt() ?? 0),
        playing: m['playing'] == true,
        ready: m['ready'] == true,
      );
}

/// Dart bridge to the native 4× ExoPlayer stem mixer
/// (StemMixerHandler.kt). just_audio can't be used for the mixer because
/// just_audio_background allows only a single instance app-wide.
class StemMixer {
  StemMixer._();
  static final StemMixer instance = StemMixer._();

  static const _channel = MethodChannel('com.quickplayer/stem_mixer');
  static const _position = EventChannel('com.quickplayer/stem_mixer/position');

  /// Position/state updates (~5/s) from the native mixer.
  Stream<MixerState> get stateStream => _position
      .receiveBroadcastStream()
      .map((e) => MixerState.fromMap(e as Map));

  /// Load the given stem files (drums/bass/other/vocals order) into four
  /// native players. Listen to [stateStream] for `ready`.
  Future<void> prepare(List<String> paths) =>
      _channel.invokeMethod('prepare', {'paths': paths});

  Future<void> play() => _channel.invokeMethod('play');
  Future<void> pause() => _channel.invokeMethod('pause');
  Future<void> seek(Duration to) =>
      _channel.invokeMethod('seek', {'ms': to.inMilliseconds});

  /// Set stem [index]'s volume (0..1). Mute = 0; solo = others 0.
  Future<void> setVolume(int index, double volume) =>
      _channel.invokeMethod('setVolume', {'index': index, 'volume': volume});

  Future<void> release() => _channel.invokeMethod('release');
}
