import 'package:flutter/services.dart';

/// Pulls a fixed-size set of peak amplitudes out of an audio file.
///
/// Backed by a thin MethodChannel onto a native (Kotlin) MediaCodec
/// pipeline that decodes the file, buckets the PCM into N windows, and
/// returns one RMS-normalised value per bucket. Replaces the previous
/// audio_waveforms-based implementation, which had a real bug
/// (WaveformExtractor.started never set to true) that leaked the
/// MediaCodec decoder on every call; the second extraction in a process
/// hung waiting for a free decoder.
///
/// Multiple back-to-back extractions are safe because each invocation
/// builds + tears down its own MediaExtractor and codec on the native
/// side. Returns null on any failure.
class WaveformExtractor {
  WaveformExtractor._();
  static final WaveformExtractor _instance = WaveformExtractor._();
  factory WaveformExtractor() => _instance;

  static const _channel = MethodChannel('com.quickplayer/waveform_peaks');

  Future<List<double>?> extract(
    String filePath, {
    int numSamples = 100,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('extract', {
        'filePath': filePath,
        'numSamples': numSamples,
      });
      if (raw == null) return null;
      return raw.whereType<num>().map((n) => n.toDouble()).toList();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // Platform without the channel (e.g. Linux desktop). UI falls
      // back to the placeholder centre line.
      return null;
    }
  }
}
