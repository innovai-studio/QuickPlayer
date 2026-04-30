import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/metronome_provider.dart';

/// In-player metronome card.
///
/// Shows the current BPM, beat indicator dots (downbeat highlighted),
/// a "Tap to sync" button that records taps to derive bpm + phase offset,
/// time-signature chips, +/- volume controls, and an ON/OFF switch.
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
          // Header: title + on/off
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
                onChanged:
                    state.isAligned ? (_) => notifier.toggle() : null,
                activeColor: AppColors.primaryStart,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // BPM + beat dots
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
              const SizedBox(width: 8),
              Text(
                state.timeSignature.label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              _BeatIndicator(
                beatsPerBar: state.beatsPerBar,
                current: state.currentBeatIndex,
                active: state.enabled,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Time signature chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: TimeSignature.values.map((ts) {
                final selected = state.timeSignature == ts;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => notifier.setTimeSignature(ts),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryStart
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? AppColors.primaryStart
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        ts.label,
                        style: TextStyle(
                          color:
                              selected ? Colors.white : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Tap-to-sync + volume row
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => notifier.tap(),
                  child: Container(
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
                            ? 'Tap on each beat'
                            : 'Tap to refine (${state.tapHistoryMs.length})',
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
              ),
              const SizedBox(width: 12),
              _VolumeStepper(
                volume: state.volume,
                onMinus: () => notifier.nudgeVolume(-0.1),
                onPlus: () => notifier.nudgeVolume(0.1),
              ),
            ],
          ),
          if (!state.isAligned) ...[
            const SizedBox(height: 8),
            const Text(
              'Tap the button on the beat 4 times to lock in.',
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

class _VolumeStepper extends StatelessWidget {
  final double volume;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _VolumeStepper({
    required this.volume,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (volume * 100).round();
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _StepperButton(
            icon: Icons.remove,
            onTap: volume > 0 ? onMinus : null,
          ),
          Container(
            width: 1,
            height: 24,
            color: AppColors.border,
          ),
          SizedBox(
            width: 44,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  percent == 0
                      ? Icons.volume_off
                      : (percent < 50
                          ? Icons.volume_down
                          : Icons.volume_up),
                  color: percent == 0
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                  size: 16,
                ),
                Text(
                  '$percent',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: AppColors.border,
          ),
          _StepperButton(
            icon: Icons.add,
            onTap: volume < 1 ? onPlus : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null
              ? AppColors.textSecondary.withValues(alpha: 0.4)
              : AppColors.textPrimary,
        ),
      ),
    );
  }
}
