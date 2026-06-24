import 'package:flutter/services.dart';

class AudioAnalysisResult {
  final int? bpm;
  final String? key;

  AudioAnalysisResult({this.bpm, this.key});

  factory AudioAnalysisResult.fromMap(Map<dynamic, dynamic> map) {
    return AudioAnalysisResult(
      bpm: map['bpm'] as int?,
      key: map['key'] as String?,
    );
  }
}

class AudioAnalyzerService {
  static const _channel = MethodChannel('com.quickplayer/audio_analyzer');

  /// Analyze audio file for BPM and musical key
  Future<AudioAnalysisResult> analyze(String filePath) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'analyzeBpmAndKey',
        {'filePath': filePath},
      );

      if (result != null) {
        return AudioAnalysisResult.fromMap(result);
      }

      return AudioAnalysisResult();
    } on PlatformException {
      return AudioAnalysisResult();
    }
  }
}
