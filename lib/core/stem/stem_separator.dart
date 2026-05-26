import 'package:flutter/services.dart';

/// Dart bridge to the native ONNX Runtime stem separator
/// (StemSeparatorHandler.kt). Phase 1 exposes only [benchmark], used to
/// measure real on-device inference time per execution provider before
/// we build the full pipeline. See docs/STEM_ONNX_EXPORT_SPIKE.md.
class StemSeparator {
  StemSeparator._();
  static final StemSeparator instance = StemSeparator._();

  static const _channel = MethodChannel('com.quickplayer/stem_separator');

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
}
