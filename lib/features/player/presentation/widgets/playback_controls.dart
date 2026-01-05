import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool hasPrevious;
  final bool hasNext;

  const PlaybackControls({
    super.key,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSeekBackward,
    required this.onSeekForward,
    this.onPrevious,
    this.onNext,
    this.hasPrevious = false,
    this.hasNext = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Previous track
        IconButton(
          iconSize: 32,
          icon: Icon(
            Icons.skip_previous,
            color: hasPrevious
                ? AppColors.textPrimary
                : AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          onPressed: hasPrevious ? onPrevious : null,
        ),
        const SizedBox(width: 8),

        // Rewind 10s
        IconButton(
          iconSize: 36,
          icon: const Icon(
            Icons.replay_10,
            color: AppColors.textPrimary,
          ),
          onPressed: onSeekBackward,
        ),
        const SizedBox(width: 16),

        // Play/Pause
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            gradient: AppColors.primaryGradient,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            iconSize: 40,
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: onPlayPause,
          ),
        ),
        const SizedBox(width: 16),

        // Forward 10s
        IconButton(
          iconSize: 36,
          icon: const Icon(
            Icons.forward_10,
            color: AppColors.textPrimary,
          ),
          onPressed: onSeekForward,
        ),
        const SizedBox(width: 8),

        // Next track
        IconButton(
          iconSize: 32,
          icon: Icon(
            Icons.skip_next,
            color: hasNext
                ? AppColors.textPrimary
                : AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          onPressed: hasNext ? onNext : null,
        ),
      ],
    );
  }
}
