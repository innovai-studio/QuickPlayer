import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// One frame of spectrum data emitted to UI.
///
/// `bins` are magnitude values normalised to roughly 0 to 1, log-spaced over
/// 20 Hz to 20 kHz so they line up with the EQ curve's frequency axis. The
/// service downsamples whatever the platform delivers (typically 256 FFT
/// bins) to a fixed length so the painter can index into them directly.
class SpectrumFrame {
  final List<double> bins;
  final int sampleRate;
  const SpectrumFrame(this.bins, this.sampleRate);
}

enum SpectrumPermission { granted, denied, permanentlyDenied, unsupported }

/// Bridges com.quickplayer/spectrum to a broadcast Stream<SpectrumFrame>.
///
/// On non-Android platforms every method is a no-op and the stream stays
/// empty so widgets don't need to gate on Platform.isAndroid.
class SpectrumService {
  SpectrumService._internal();
  static final SpectrumService _instance = SpectrumService._internal();
  factory SpectrumService() => _instance;

  static const _control =
      MethodChannel('com.quickplayer/spectrum/control');
  static const _events =
      EventChannel('com.quickplayer/spectrum/stream');

  /// How many bins the UI gets per frame. Painter draws this many bars.
  static const int outputBinCount = 64;

  /// Min / max frequency mapped onto the output bins (matches EqVisualizer).
  static const double _minHz = 20;
  static const double _maxHz = 20000;

  final StreamController<SpectrumFrame> _frames =
      StreamController<SpectrumFrame>.broadcast();
  StreamSubscription<dynamic>? _eventSub;
  bool _running = false;
  int? _activeSessionId;

  Stream<SpectrumFrame> get frames => _frames.stream;
  bool get isRunning => _running;

  Future<SpectrumPermission> ensurePermission() async {
    if (!Platform.isAndroid) return SpectrumPermission.unsupported;
    final status = await Permission.microphone.status;
    if (status.isGranted) return SpectrumPermission.granted;
    if (status.isPermanentlyDenied) {
      return SpectrumPermission.permanentlyDenied;
    }
    final result = await Permission.microphone.request();
    if (result.isGranted) return SpectrumPermission.granted;
    if (result.isPermanentlyDenied) return SpectrumPermission.permanentlyDenied;
    return SpectrumPermission.denied;
  }

  /// Start FFT capture against the given audio session id. Idempotent for
  /// the same session id; rebinds to a new one. Caller must have already
  /// granted RECORD_AUDIO via ensurePermission.
  Future<bool> start(int sessionId) async {
    if (!Platform.isAndroid) return false;
    if (sessionId == 0) return false;
    if (_running && _activeSessionId == sessionId) return true;

    try {
      await _control.invokeMethod<Map<dynamic, dynamic>>(
        'start',
        {'sessionId': sessionId},
      );
      await _eventSub?.cancel();
      _eventSub = _events.receiveBroadcastStream().listen(
        _onPlatformFrame,
        onError: (_) {
          // Visualizer can fire async errors if the audio session goes
          // away (track switch, user kills audio focus). Drop the stream
          // and let the next start() rebind.
          _running = false;
        },
        cancelOnError: false,
      );
      _running = true;
      _activeSessionId = sessionId;
      return true;
    } on PlatformException {
      _running = false;
      return false;
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _control.invokeMethod<void>('stop');
    } on PlatformException {
      // ignore
    }
    _running = false;
    _activeSessionId = null;
  }

  void _onPlatformFrame(dynamic raw) {
    if (raw is! Map) return;
    final fft = raw['fft'];
    final samplingRate = (raw['samplingRate'] as int?) ?? 44100;
    if (fft is! List<int> && fft is! Uint8List) return;

    final List<int> bytes = fft is Uint8List ? fft : List<int>.from(fft);
    if (bytes.length < 2) return;

    // Visualizer FFT layout: [DC_real, Nyquist_real, R1, I1, R2, I2, ...]
    final int binCount = bytes.length ~/ 2;
    final List<double> magnitudes = List<double>.filled(binCount, 0);
    // DC bin
    magnitudes[0] = bytes[0].toDouble().abs();
    for (int k = 1; k < binCount; k++) {
      final int reByte = bytes[2 * k];
      final int imByte = bytes[2 * k + 1];
      final double re = _signed(reByte).toDouble();
      final double im = _signed(imByte).toDouble();
      magnitudes[k] = math.sqrt(re * re + im * im);
    }

    final downsampled = _logResample(magnitudes, samplingRate);
    if (_frames.isClosed) return;
    _frames.add(SpectrumFrame(downsampled, samplingRate));
  }

  int _signed(int byte) => byte > 127 ? byte - 256 : byte;

  /// Map linear FFT bins onto a log-frequency output of fixed length.
  /// Each output bin averages whatever input bins fall inside its range,
  /// then magnitudes are converted to a 0..1 dB-ish scale.
  List<double> _logResample(List<double> mags, int samplingRate) {
    if (mags.length < 4) return List<double>.filled(outputBinCount, 0);

    // The mags array covers DC..(samplingRate/2). We map output bin i to
    // a frequency by log-spacing between _minHz and _maxHz, then find the
    // input mag index by ratio.
    final double nyquist = samplingRate / 2.0;
    final int inputLen = mags.length;
    final double logMin = math.log(_minHz) / math.ln10;
    final double logMax = math.log(_maxHz) / math.ln10;

    final List<double> out = List<double>.filled(outputBinCount, 0);
    for (int i = 0; i < outputBinCount; i++) {
      final double frac = i / (outputBinCount - 1);
      final double logF = logMin + (logMax - logMin) * frac;
      final double freqHz = math.pow(10, logF).toDouble();
      final double freqIdx = (freqHz / nyquist) * (inputLen - 1);
      final int lo = freqIdx.floor().clamp(0, inputLen - 1);
      final int hi = (lo + 1).clamp(0, inputLen - 1);
      final double interp =
          mags[lo] * (1 - (freqIdx - lo)) + mags[hi] * (freqIdx - lo);

      // Convert magnitude to a 0..1 dB scale. Visualizer normalised mags
      // sit in roughly 0..128, so 20*log10(mag/128) gives dB <= 0.
      double db;
      if (interp <= 0.5) {
        db = -80;
      } else {
        db = 20 * (math.log(interp / 128.0) / math.ln10);
      }
      // Map -80..0 dB to 0..1 with a soft floor.
      final double normalised = ((db + 80) / 80).clamp(0.0, 1.0);
      out[i] = normalised;
    }
    return out;
  }
}
