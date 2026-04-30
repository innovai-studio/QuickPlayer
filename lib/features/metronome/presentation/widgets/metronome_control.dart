import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/metronome_provider.dart';

/// In-player metronome card.
///
/// Shows the current BPM, four beat indicator dots (downbeat highlighted),
/// a "Tap to sync" button that records taps to derive bpm + phase offset,
/// and an ON/OFF switch. Click playback runs in [MetronomeNotifier]'s
/// ticker; this widget just reads and forwards interactions.
class MetronomeControl extends ConsumerWidget {
  const MetronomeControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(metronomeProvider);
    final notifier = ref.read(metronomeProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Metronome',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Switch(
                value: state.enabled,
                onChanged: state.isAligned
                    ? (_) => notifier.toggle()
                    : null,
                activeColor: AppColors.primaryStart,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // BPM + beat indicator
          Row(
            children: [
              Text(
                '${state.bpm.round()} BPM',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _BeatIndicator(
                  beatsPerBar: state.beatsPerBar,
                  current: state.currentBeatIndex,
                  active: state.enabled,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Tap-to-sync button
          GestureDetector(
            onTap: () => notifier.tap(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: state.tapHistoryMs.isNotEmpty
                    ? AppColors.primaryGradient
                    : null,
                color: state.tapHistoryMs.isEmpty
                    ? AppColors.background
                    : null,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Text(
                  state.tapHistoryMs.length < 2
                      ? 'Tap on each beat to sync'
                      : 'Tap to refine (${state.tapHistoryMs.length} taps)',
                  style: TextStyle(
                    color: state.tapHistoryMs.isEmpty
                        ? AppColors.textSecondary
                        : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (!state.isAligned) ...[
            const SizedBox(height: 8),
            const Text(
              'Tap the button on the beat 4 times. The metronome locks to '
              'your tap timing and will stay aligned through pauses and '
              'A-B loops.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BeatIndicator extends StatelessWidget {
  final int beatsPerBar;
  final int current;
  final bool active;

  const _BeatIndicator({
    required this.beatsPerBar,
    required this.current,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: List.generate(beatsPerBar, (i) {
        final isCurrent = active && i == current;
        final isDownbeat = i == 0;
        return Container(
          width: isDownbeat ? 14 : 10,
          height: isDownbeat ? 14 : 10,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCurrent
                ? (isDownbeat ? AppColors.accent : AppColors.primaryStart)
                : AppColors.border,
          ),
        );
      }),
    );
  }
}
