import 'package:flutter/material.dart';
import '../../../../core/audio/waveform_extractor.dart';
import '../../../../core/constants/app_colors.dart';

/// Renders a peak-amplitude waveform of the current track, with a
/// scrubbable playhead overlay.
///
/// Real peaks come from [WaveformExtractor] (audio_waveforms plugin).
/// Extraction takes a couple of seconds on a typical 3-min song, so:
///   * If the caller already has cached peaks (from Track.waveformPeaks
///     in Hive), pass them through `cachedPeaks` and we render instantly.
///   * Otherwise we kick off extraction on mount and call back via
///     `onPeaksExtracted` so the caller can persist them on the Track.
///
/// While extraction is in flight we render a thin centre line as a
/// placeholder so layout doesn't jump.
class WaveformView extends StatefulWidget {
  final String filePath;
  final List<double>? cachedPeaks;
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<List<double>>? onPeaksExtracted;

  const WaveformView({
    super.key,
    required this.filePath,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.cachedPeaks,
    this.onPeaksExtracted,
  });

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  /// Number of bars drawn. 100 looks good at typical screen widths and
  /// keeps the Hive footprint small (~800 bytes per track).
  static const int _numSamples = 100;

  List<double>? _peaks;
  bool _extracting = false;

  @override
  void initState() {
    super.initState();
    _peaks = widget.cachedPeaks;
    if (_peaks == null) _kickOffExtraction();
  }

  @override
  void didUpdateWidget(WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      // New track. Use new cache if provided, otherwise re-extract.
      _peaks = widget.cachedPeaks;
      if (_peaks == null) _kickOffExtraction();
    } else if (widget.cachedPeaks != null &&
        !identical(widget.cachedPeaks, oldWidget.cachedPeaks)) {
      // Cache arrived after extraction was already in flight (e.g. the
      // parent persisted our previous result). Adopt it.
      _peaks = widget.cachedPeaks;
    }
  }

  Future<void> _kickOffExtraction() async {
    if (_extracting) return;
    _extracting = true;
    final result = await WaveformExtractor().extract(
      widget.filePath,
      numSamples: _numSamples,
    );
    if (!mounted) return;
    _extracting = false;
    if (result == null) return;
    setState(() => _peaks = result);
    widget.onPeaksExtracted?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.duration.inMilliseconds > 0
        ? widget.position.inMilliseconds / widget.duration.inMilliseconds
        : 0.0;
    final peaks = _peaks;

    return GestureDetector(
      onTapDown: (details) => _handleSeek(details.localPosition.dx),
      onHorizontalDragUpdate: (details) =>
          _handleSeek(details.localPosition.dx),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: peaks == null
              ? _LoadingPlaceholder(progress: progress.clamp(0.0, 1.0))
              : CustomPaint(
                  painter: WaveformPainter(
                    waveformData: peaks,
                    progress: progress.clamp(0.0, 1.0),
                    activeColor: AppColors.primaryStart,
                    inactiveColor:
                        AppColors.textSecondary.withValues(alpha: 0.3),
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

/// Rendered while real peaks are still being extracted. Animated
/// shimmer + an "Analyzing..." label so the user can tell the silence
/// isn't a hang -- waveform extraction is normally < 2 s on a typical
/// song but the first run after install can be longer.
class _LoadingPlaceholder extends StatefulWidget {
  final double progress;

  const _LoadingPlaceholder({required this.progress});

  @override
  State<_LoadingPlaceholder> createState() => _LoadingPlaceholderState();
}

class _LoadingPlaceholderState extends State<_LoadingPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        return CustomPaint(
          painter: _ShimmerPainter(
            shimmerPosition: _shimmer.value,
            progress: widget.progress,
          ),
          size: Size.infinite,
          child: const Center(
            child: Text(
              'Analyzing waveform...',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  /// 0..1 -- position of the highlight band travelling left-to-right.
  final double shimmerPosition;
  final double progress;

  _ShimmerPainter({
    required this.shimmerPosition,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Soft horizontal base bar.
    final centerY = size.height / 2;
    final basePaint = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.15)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), basePaint);

    // Shimmer band: a tall translucent gradient that sweeps across the
    // whole canvas. Travels from off-left to off-right and loops.
    const bandWidth = 0.25;
    final startX = (shimmerPosition * (1 + bandWidth * 2) - bandWidth) *
        size.width;
    final shimmerRect = Rect.fromLTWH(
      startX,
      0,
      bandWidth * size.width,
      size.height,
    );
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          AppColors.primaryStart.withValues(alpha: 0.0),
          AppColors.primaryStart.withValues(alpha: 0.35),
          AppColors.primaryStart.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(shimmerRect);
    canvas.drawRect(shimmerRect, shimmerPaint);

    // Playhead so the user can still scrub while we wait.
    final playheadX = progress * size.width;
    final playheadPaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter old) =>
      old.shimmerPosition != shimmerPosition || old.progress != progress;
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

    for (int i = 0; i < waveformData.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final barProgress = i / waveformData.length;
      final barHeight = waveformData[i] * maxBarHeight / 2;

      final paint = barProgress <= progress ? activePaint : inactivePaint;

      canvas.drawLine(
        Offset(x, centerY - barHeight),
        Offset(x, centerY + barHeight),
        paint,
      );
    }

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
        !identical(oldDelegate.waveformData, waveformData);
  }
}
