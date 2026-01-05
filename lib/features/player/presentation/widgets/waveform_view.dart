import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class WaveformView extends StatefulWidget {
  final String filePath;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const WaveformView({
    super.key,
    required this.filePath,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  // Generate consistent waveform pattern based on file path
  late List<double> _waveformData;

  @override
  void initState() {
    super.initState();
    _generateWaveformData();
  }

  @override
  void didUpdateWidget(WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _generateWaveformData();
    }
  }

  void _generateWaveformData() {
    // Generate a consistent pseudo-random waveform based on file path hash
    final random = Random(widget.filePath.hashCode);
    _waveformData = List.generate(100, (index) {
      // Create a more natural waveform pattern
      final base = 0.3 + random.nextDouble() * 0.7;
      // Add some smoothing by considering neighbors
      return base;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.duration.inMilliseconds > 0
        ? widget.position.inMilliseconds / widget.duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTapDown: (details) => _handleSeek(details.localPosition.dx),
      onHorizontalDragUpdate: (details) => _handleSeek(details.localPosition.dx),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CustomPaint(
            painter: WaveformPainter(
              waveformData: _waveformData,
              progress: progress.clamp(0.0, 1.0),
              activeColor: AppColors.primaryStart,
              inactiveColor: AppColors.textSecondary.withValues(alpha: 0.3),
              playheadColor: AppColors.accent,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }

  void _handleSeek(double localX) {
    final renderBox = context.findRenderObject() as RenderBox;
    final width = renderBox.size.width;
    final progress = (localX / width).clamp(0.0, 1.0);
    final newPosition = Duration(
      milliseconds: (progress * widget.duration.inMilliseconds).round(),
    );
    widget.onSeek(newPosition);
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final Color playheadColor;

  WaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.playheadColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    final barWidth = size.width / waveformData.length;
    final centerY = size.height / 2;
    final maxBarHeight = size.height * 0.8;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth * 0.6;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth * 0.6;

    // Draw waveform bars
    for (int i = 0; i < waveformData.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final barProgress = i / waveformData.length;
      final barHeight = waveformData[i] * maxBarHeight / 2;

      final paint = barProgress <= progress ? activePaint : inactivePaint;

      // Draw bar (centered vertically)
      canvas.drawLine(
        Offset(x, centerY - barHeight),
        Offset(x, centerY + barHeight),
        paint,
      );
    }

    // Draw playhead
    final playheadX = progress * size.width;
    final playheadPaint = Paint()
      ..color = playheadColor
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.waveformData != waveformData;
  }
}
