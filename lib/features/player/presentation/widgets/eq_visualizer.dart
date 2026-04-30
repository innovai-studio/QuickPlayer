import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/audio/audio_effects_service.dart';
import '../../../../core/constants/app_colors.dart';

/// Renders a frequency-response curve and a row of vertical band sliders.
///
/// The curve is a visual approximation, not a true biquad response: each
/// band contributes a Gaussian peak around its center frequency on the
/// log-frequency axis, and BassBoost adds a low-shelf at the left edge.
/// This matches what users expect from "EQ visualisers" in apps like
/// Poweramp / Spotify and is cheap to recompute as sliders move.
class EqVisualizer extends StatelessWidget {
  final AudioEffectsCapabilities capabilities;
  final List<int> bandLevelsMillibel;
  final int bassStrengthMilli;
  final void Function(int bandIndex, int millibel) onBandChanged;
  final ValueChanged<int> onBassChanged;

  const EqVisualizer({
    super.key,
    required this.capabilities,
    required this.bandLevelsMillibel,
    required this.bassStrengthMilli,
    required this.onBandChanged,
    required this.onBassChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!capabilities.supported || bandLevelsMillibel.isEmpty) {
      return const SizedBox.shrink();
    }

    final minMb = capabilities.minBandLevelMillibel;
    final maxMb = capabilities.maxBandLevelMillibel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Curve
        SizedBox(
          height: 90,
          child: CustomPaint(
            painter: _ResponseCurvePainter(
              bandLevels: bandLevelsMillibel,
              centerFreqsMilliHz: capabilities.centerFrequenciesMilliHz,
              minLevel: minMb,
              maxLevel: maxMb,
              bassStrengthMilli: bassStrengthMilli,
              hasBassBoost: capabilities.hasBassBoost,
            ),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 4),
        // Sliders
        SizedBox(
          height: 140,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (int i = 0; i < bandLevelsMillibel.length; i++)
                Expanded(
                  child: _BandSlider(
                    levelMillibel: bandLevelsMillibel[i],
                    minMillibel: minMb,
                    maxMillibel: maxMb,
                    centerFreqMilliHz: i < capabilities.centerFrequenciesMilliHz.length
                        ? capabilities.centerFrequenciesMilliHz[i]
                        : 0,
                    onChanged: (value) => onBandChanged(i, value),
                  ),
                ),
              if (capabilities.hasBassBoost)
                Expanded(
                  child: _BassSlider(
                    strengthMilli: bassStrengthMilli,
                    onChanged: onBassChanged,
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
            color: strengthMilli == 0 ? AppColors.textSecondary : AppColors.accent,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
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

    final bgPaint = Paint()..color = AppColors.surfaceDark;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      bgPaint,
    );

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
          AppColors.primaryStart.withValues(alpha: 0.35),
          AppColors.primaryStart.withValues(alpha: 0.05),
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
      // Low-shelf approximation: full strength below 60 Hz, falling off
      // smoothly to ~0 by 250 Hz. Strength 1000 -> +800 millibel max.
      final shelfMax = bassStrengthMilli * 0.8; // peak boost in millibel
      const shelfCenterHz = 60;
      const shelfFalloff = 0.6; // log decade
      final logShelf = math.log(shelfCenterHz) / math.ln10;
      final dx = (logTarget - logShelf) / shelfFalloff;
      // Sigmoid-ish: 1.0 at shelfCenter, 0 well above
      final factor = 1 / (1 + math.exp(2 * dx));
      total += shelfMax * factor;
    }

    return total;
  }

  double _mapLevelToY(double mb, double h) {
    final clamped = mb.clamp(minLevel.toDouble(), maxLevel.toDouble());
    final span = (maxLevel - minLevel).toDouble();
    final t = span == 0 ? 0.5 : (clamped - minLevel) / span;
    // Higher mb -> smaller y (top of widget)
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
