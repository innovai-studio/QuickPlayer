import 'package:flutter/services.dart';

/// Dart bridge to the native ONNX Runtime stem separator
/// (StemSeparatorHandler.kt). Phase 1 exposes only [benchmark], used to
/// measure real on-device inference time per execution provider before
/// we build the full pipeline. See docs/STEM_ONNX_EXPORT_SPIKE.md.
class StemSeparator {
  StemSeparator._();
  static final StemSeparator instance = StemSeparator._();

  static const _channel = MethodChannel('com.quickplayer/stem_separator');
  static const _progress =
      EventChannel('com.quickplayer/stem_separator/progress');

  /// Progress/completion stream from the separation foreground service.
  /// Events are maps: {event: 'progress', progress: 0..1} |
  /// {event: 'done', stems: [paths]} | {event: 'error', error: msg}.
  ///
  /// Cached as a single broadcast stream: both the controller and the
  /// progress dialog listen, and calling receiveBroadcastStream() more
  /// than once opens duplicate native subscriptions whose sinks clobber
  /// each other (events then stop reaching one of the listeners).
  late final Stream<Map<String, dynamic>> progressStream = _progress
      .receiveBroadcastStream()
      .map((e) => Map<String, dynamic>.from(e as Map))
      .asBroadcastStream();

  /// Run one 7.8 s segment through the model under [provider]
  /// ('cpu' | 'xnnpack' | 'nnapi') and return the native timing map:
  /// {ok, loadMs, inferMs, fullSongEstSec, outShape, outAbsMean}.
  /// [inputRawPath] optionally points at an interleaved-stereo-f32 file
  /// so the run uses real audio (to sanity-check the output isn't zero).
  Future<Map<String, dynamic>?> benchmark({
    required String modelPath,
    String provider = 'cpu',
    int threads = 4,
    String? inputRawPath,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('benchmark', {
        'modelPath': modelPath,
        'provider': provider,
        'threads': threads,
        'inputRawPath': inputRawPath,
      });
      return res;
    } on PlatformException catch (e) {
      return {'ok': false, 'error': '${e.code}: ${e.message}'};
    }
  }

  /// Total device RAM in MB (for picking the segment length / model).
  Future<int> totalRamMb() async =>
      (await _channel.invokeMethod<int>('totalRamMb')) ?? 0;

  /// Whether a separation foreground service is currently running.
  Future<bool> isRunning() async =>
      (await _channel.invokeMethod<bool>('isRunning')) ?? false;

  /// Start the separation foreground service for [audioPath] → 4 stems
  /// under [outDir]. Returns {started: true} immediately; progress and
  /// completion arrive on [progressStream]. [provider] picks the ORT
  /// execution provider: 'cpu' (default, proven on all devices) or
  /// 'nnapi' (auto-falls-back to CPU if NPU init fails).
  Future<Map<String, dynamic>?> separate({
    required String modelPath,
    required String audioPath,
    required String outDir,
    int threads = 4,
    String provider = 'cpu',
  }) async {
    try {
      return await _channel.invokeMapMethod<String, dynamic>('separate', {
        'modelPath': modelPath,
        'audioPath': audioPath,
        'outDir': outDir,
        'threads': threads,
        'provider': provider,
      });
    } on PlatformException catch (e) {
      return {'ok': false, 'error': '${e.code}: ${e.message}'};
    }
  }
}
