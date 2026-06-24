import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/audio/audio_effects_service.dart';
import '../../../../core/audio/spectrum_service.dart';
import '../../../../core/constants/app_colors.dart';

/// Renders a frequency-response curve and a row of vertical band sliders,
/// optionally with a real-time FFT spectrum overlay behind the curve.
///
/// The curve is a visual approximation, not a true biquad response: each
/// band contributes a Gaussian peak around its center frequency on the
/// log-frequency axis, and BassBoost adds a low-shelf at the left edge.
/// The spectrum bars are downsampled FFT magnitudes from
/// [SpectrumService] mapped onto the same log axis so they line up.
class EqVisualizer extends StatefulWidget {
  final AudioEffectsCapabilities capabilities;
  final List<int> bandLevelsMillibel;
  final int bassStrengthMilli;
  final bool spectrumEnabled;
  final void Function(int bandIndex, int millibel) onBandChanged;
  final ValueChanged<int> onBassChanged;
  final VoidCallback onEnableSpectrum;

  const EqVisualizer({
    super.key,
    required this.capabilities,
    required this.bandLevelsMillibel,
    required this.bassStrengthMilli,
    required this.spectrumEnabled,
    required this.onBandChanged,
    required this.onBassChanged,
    required this.onEnableSpectrum,
  });

  @override
  State<EqVisualizer> createState() => _EqVisualizerState();
}

class _EqVisualizerState extends State<EqVisualizer> {
  /// Smoothed magnitude bins; same length as SpectrumService.outputBinCount.
  /// Updated on every incoming frame with attack/release envelope so the
  /// painted bars don't flicker.
  late List<double> _smoothedBins;
  StreamSubscription<SpectrumFrame>? _spectrumSub;

  @override
  void initState() {
    super.initState();
    _smoothedBins = List<double>.filled(SpectrumService.outputBinCount, 0);
    if (widget.spectrumEnabled) _subscribeSpectrum();
  }

  @override
  void didUpdateWidget(EqVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spectrumEnabled != oldWidget.spectrumEnabled) {
      if (widget.spectrumEnabled) {
        _subscribeSpectrum();
      } else {
        _unsubscribeSpectrum();
        _smoothedBins =
            List<double>.filled(SpectrumService.outputBinCount, 0);
      }
    }
  }

  @override
  void dispose() {
    _unsubscribeSpectrum();
    super.dispose();
  }

  void _subscribeSpectrum() {
    _spectrumSub?.cancel();
    _spectrumSub = SpectrumService().frames.listen(_onFrame);
  }

  void _unsubscribeSpectrum() {
    _spectrumSub?.cancel();
    _spectrumSub = null;
  }

  void _onFrame(SpectrumFrame frame) {
    if (frame.bins.length != _smoothedBins.length) return;
    // Attack ~ 0.6 (fast rise), release ~ 0.15 (slow decay).
    for (int i = 0; i < _smoothedBins.length; i++) {
      final target = frame.bins[i];
      final current = _smoothedBins[i];
      final coef = target > current ? 0.6 : 0.15;
      _smoothedBins[i] = current + (target - current) * coef;
    }
    // Listener is called on stream events, never inside build, so this
    // setState is safe.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.capabilities.supported || widget.bandLevelsMillibel.isEmpty) {
      return const SizedBox.shrink();
    }

    final minMb = widget.capabilities.minBandLevelMillibel;
    final maxMb = widget.capabilities.maxBandLevelMillibel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Curve + spectrum overlay
        SizedBox(
          height: 110,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Backing rect
                Container(color: AppColors.surfaceDark),

                // Spectrum layer (only paints when frames arrive). We snapshot
                // the bins per build so the painter's shouldRepaint can
                // compare against the previous frame's values (in-place
                // mutation would alias both old and new and skip repaints).
                if (widget.spectrumEnabled)
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _SpectrumPainter(
                        bins: List<double>.from(_smoothedBins),
                      ),
                      size: Size.infinite,
                    ),
                  ),

                // EQ response curve on top
                CustomPaint(
                  painter: _ResponseCurvePainter(
                    bandLevels: widget.bandLevelsMillibel,
                    centerFreqsMilliHz:
                        widget.capabilities.centerFrequenciesMilliHz,
                    minLevel: minMb,
                    maxLevel: maxMb,
                    bassStrengthMilli: widget.bassStrengthMilli,
                    hasBassBoost: widget.capabilities.hasBassBoost,
                  ),
                  size: Size.infinite,
                ),

                // Tap-to-enable overlay
                if (!widget.spectrumEnabled)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: GestureDetector(
                        onTap: widget.onEnableSpectrum,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.graphic_eq,
                                  size: 12, color: AppColors.textSecondary),
                              SizedBox(width: 4),
                              Text(
                                'Live spectrum',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Sliders. Bass+ sits leftmost so its position lines up with
        // where it actually colours the spectrum (the low-frequency end).
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.capabilities.hasBassBoost)
                Expanded(
                  child: _BassSlider(
                    strengthMilli: widget.bassStrengthMilli,
                    onChanged: widget.onBassChanged,
                  ),
                ),
              for (int i = 0; i < widget.bandLevelsMillibel.length; i++)
                Expanded(
                  child: _BandSlider(
                    levelMillibel: widget.bandLevelsMillibel[i],
                    minMillibel: minMb,
                    maxMillibel: maxMb,
                    centerFreqMilliHz: i <
                            widget.capabilities.centerFrequenciesMilliHz.length
                        ? widget.capabilities.centerFrequenciesMilliHz[i]
                        : 0,
                    onChanged: (value) => widget.onBandChanged(i, value),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BandSlider extends StatelessWidget {
  final int levelMillibel;
  final int minMillibel;
  final int maxMillibel;
  final int centerFreqMilliHz;
  final ValueChanged<int> onChanged;

  const _BandSlider({
    required this.levelMillibel,
    required this.minMillibel,
    required this.maxMillibel,
    required this.centerFreqMilliHz,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primaryStart,
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.primaryStart,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: levelMillibel.toDouble(),
                min: minMillibel.toDouble(),
                max: maxMillibel.toDouble(),
                onChanged: (value) => onChanged(value.round()),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatHz(centerFreqMilliHz),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
          ),
        ),
        Text(
          _formatDb(levelMillibel),
          style: TextStyle(
            color: levelMillibel == 0
                ? AppColors.textSecondary
                : AppColors.primaryStart,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatHz(int milliHz) {
    if (milliHz <= 0) return '--';
    final hz = milliHz / 1000;
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(1)}k';
    return hz.round().toString();
  }

  String _formatDb(int mb) {
    final db = mb / 100;
    if (db == 0) return '0';
    return db > 0 ? '+${db.toStringAsFixed(0)}' : db.toStringAsFixed(0);
  }
}

class _BassSlider extends StatelessWidget {
  final int strengthMilli;
  final ValueChanged<int> onChanged;

  const _BassSlider({
    required this.strengthMilli,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: AppColors.border,
                thumbColor: AppColors.accent,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: strengthMilli.toDouble(),
                min: 0,
                max: 1000,
                onChanged: (value) => onChanged(value.round()),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Bass+',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
        Text(
          strengthMilli == 0 ? 'Off' : '${(strengthMilli / 10).round()}%',
          style: TextStyle(
            color: strengthMilli == 0
                ? AppColors.textSecondary
                : AppColors.accent,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Paints a real-time spectrum bar chart with log-frequency x axis.
class _SpectrumPainter extends CustomPainter {
  final List<double> bins;

  _SpectrumPainter({required this.bins});

  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final barWidth = w / bins.length;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          AppColors.textSecondary.withValues(alpha: 0.5),
          AppColors.textSecondary.withValues(alpha: 0.18),
        ],
      ).createShader(Offset.zero & size);

    final path = Path();
    path.moveTo(0, h);
    for (int i = 0; i < bins.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final y = h - bins[i].clamp(0.0, 1.0) * h;
      if (i == 0) {
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.lineTo(w, h);
    path.close();
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) {
    if (old.bins.length != bins.length) return true;
    for (int i = 0; i < bins.length; i++) {
      if ((old.bins[i] - bins[i]).abs() > 0.005) return true;
    }
    return false;
  }
}

class _ResponseCurvePainter extends CustomPainter {
  static const _logMin = 1.30103; // log10(20)  Hz
  static const _logMax = 4.30103; // log10(20000) Hz

  final List<int> bandLevels; // millibel
  final List<int> centerFreqsMilliHz;
  final int minLevel;
  final int maxLevel;
  final int bassStrengthMilli;
  final bool hasBassBoost;

  _ResponseCurvePainter({
    required this.bandLevels,
    required this.centerFreqsMilliHz,
    required this.minLevel,
    required this.maxLevel,
    required this.bassStrengthMilli,
    required this.hasBassBoost,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Center (0 dB) baseline
    final zeroPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final centerY = h / 2;
    canvas.drawLine(Offset(0, centerY), Offset(w, centerY), zeroPaint);

    // Minor grid: ±6dB and ±12dB lines
    final gridPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (final db in [-12, -6, 6, 12]) {
      final mb = db * 100;
      final y = _mapLevelToY(mb.toDouble(), h);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Build curve: sample N points along log-freq axis.
    const samples = 96;
    final curvePoints = <Offset>[];
    final fillPath = Path();
    fillPath.moveTo(0, centerY);

    for (int s = 0; s < samples; s++) {
      final fraction = s / (samples - 1);
      final logF = _logMin + (_logMax - _logMin) * fraction;
      final freqHz = math.pow(10, logF).toDouble();
      final levelMb = _evaluateLevel(freqHz);
      final x = fraction * w;
      final y = _mapLevelToY(levelMb, h);
      curvePoints.add(Offset(x, y));
      if (s == 0) {
        fillPath.moveTo(x, centerY);
        fillPath.lineTo(x, y);
      } else {
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(w, centerY);
    fillPath.close();

    // Filled area under curve (between curve and 0dB line) with gradient.
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primaryStart.withValues(alpha: 0.30),
          AppColors.primaryStart.withValues(alpha: 0.04),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    // Curve line
    final linePaint = Paint()
      ..color = AppColors.primaryStart
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final linePath = Path();
    for (int i = 0; i < curvePoints.length; i++) {
      final p = curvePoints[i];
      if (i == 0) {
        linePath.moveTo(p.dx, p.dy);
      } else {
        linePath.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(linePath, linePaint);

    // Per-band marker dots at center frequencies
    final dotPaint = Paint()..color = AppColors.primaryStart;
    for (int i = 0; i < bandLevels.length; i++) {
      if (i >= centerFreqsMilliHz.length) break;
      final freqHz = centerFreqsMilliHz[i] / 1000;
      if (freqHz <= 0) continue;
      final logF = math.log(freqHz) / math.ln10;
      final fraction = ((logF - _logMin) / (_logMax - _logMin)).clamp(0.0, 1.0);
      final x = fraction * w;
      final y = _mapLevelToY(bandLevels[i].toDouble(), h);
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }
  }

  /// Evaluate the EQ response at a given frequency (Hz).
  /// Each band contributes a Gaussian centred at its freq with width Q≈1.
  /// BassBoost is approximated as a low-shelf below 250 Hz.
  double _evaluateLevel(double freqHz) {
    if (freqHz <= 0) return 0;
    double total = 0;
    final logTarget = math.log(freqHz) / math.ln10;

    for (int i = 0; i < bandLevels.length; i++) {
      if (i >= centerFreqsMilliHz.length) break;
      final centerHz = centerFreqsMilliHz[i] / 1000;
      if (centerHz <= 0) continue;
      final logCenter = math.log(centerHz) / math.ln10;
      // 1.0 octave Gaussian width (in log10 units, log10(2) ≈ 0.301)
      const sigma = 0.35;
      final dx = (logTarget - logCenter) / sigma;
      total += bandLevels[i] * math.exp(-0.5 * dx * dx);
    }

    if (hasBassBoost && bassStrengthMilli > 0) {
      final shelfMax = bassStrengthMilli * 0.8;
      const shelfCenterHz = 60;
      const shelfFalloff = 0.6;
      final logShelf = math.log(shelfCenterHz) / math.ln10;
      final dx = (logTarget - logShelf) / shelfFalloff;
      final factor = 1 / (1 + math.exp(2 * dx));
      total += shelfMax * factor;
    }

    return total;
  }

  double _mapLevelToY(double mb, double h) {
    final clamped = mb.clamp(minLevel.toDouble(), maxLevel.toDouble());
    final span = (maxLevel - minLevel).toDouble();
    final t = span == 0 ? 0.5 : (clamped - minLevel) / span;
    return h - t * h;
  }

  @override
  bool shouldRepaint(covariant _ResponseCurvePainter old) {
    if (old.bandLevels.length != bandLevels.length) return true;
    for (int i = 0; i < bandLevels.length; i++) {
      if (old.bandLevels[i] != bandLevels[i]) return true;
    }
    return old.bassStrengthMilli != bassStrengthMilli ||
        old.hasBassBoost != hasBassBoost ||
        old.minLevel != minLevel ||
        old.maxLevel != maxLevel;
  }
}
