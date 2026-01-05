import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../features/player/presentation/providers/player_provider.dart';
import '../extensions/duration_extension.dart';

class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final track = playerState.currentTrack;

    // Don't show if no track is loaded
    if (track == null) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(
          top: BorderSide(
            color: AppColors.primaryStart.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () => context.push('/player/${track.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Track info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${playerState.position.toDisplayString()} / ${playerState.duration.toDisplayString()}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Previous button
                IconButton(
                  onPressed: playerState.hasPrevious
                      ? () => ref.read(playerProvider.notifier).playPrevious()
                      : null,
                  icon: Icon(
                    Icons.skip_previous,
                    color: playerState.hasPrevious
                        ? AppColors.textPrimary
                        : AppColors.textSecondary.withValues(alpha: 0.5),
                    size: 24,
                  ),
                ),

                // Play/Pause button
                IconButton(
                  onPressed: () {
                    ref.read(playerProvider.notifier).togglePlay();
                  },
                  icon: Icon(
                    playerState.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: AppColors.textPrimary,
                    size: 28,
                  ),
                ),

                // Next button
                IconButton(
                  onPressed: playerState.hasNext
                      ? () => ref.read(playerProvider.notifier).playNext()
                      : null,
                  icon: Icon(
                    Icons.skip_next,
                    color: playerState.hasNext
                        ? AppColors.textPrimary
                        : AppColors.textSecondary.withValues(alpha: 0.5),
                    size: 24,
                  ),
                ),

                // Close button
                IconButton(
                  onPressed: () {
                    ref.read(playerProvider.notifier).stopAndClear();
                  },
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
