import 'package:flutter/material.dart';
import '../../../../core/audio/audio_effects_service.dart';
import '../../../../core/constants/app_colors.dart';
import 'eq_visualizer.dart';

/// Focus EQ card: a chip row of presets stacked above a frequency-response
/// curve and a per-band slider strip. Manual slider drags flip the chip
/// row to the `Custom` chip automatically.
///
/// The whole card collapses on devices that report effects unsupported,
/// so non-Android / older devices never see a dead control.
class FocusModeControl extends StatelessWidget {
  final EqPreset preset;
  final bool available;
  final AudioEffectsCapabilities capabilities;
  final List<int> bandLevelsMillibel;
  final int bassStrengthMilli;
  final ValueChanged<EqPreset> onPresetChanged;
  final void Function(int bandIndex, int millibel) onBandChanged;
  final ValueChanged<int> onBassChanged;

  const FocusModeControl({
    super.key,
    required this.preset,
    required this.available,
    required this.capabilities,
    required this.bandLevelsMillibel,
    required this.bassStrengthMilli,
    required this.onPresetChanged,
    required this.onBandChanged,
    required this.onBassChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();

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
                'Focus',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                preset == EqPreset.flat ? 'Off' : preset.label,
                style: TextStyle(
                  color: preset == EqPreset.flat
                      ? AppColors.textSecondary
                      : AppColors.primaryStart,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: EqPreset.values.map((value) {
                final isSelected = value == preset;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PresetChip(
                    label: value.label,
                    selected: isSelected,
                    onTap: () => onPresetChanged(value),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          EqVisualizer(
            capabilities: capabilities,
            bandLevelsMillibel: bandLevelsMillibel,
            bassStrengthMilli: bassStrengthMilli,
            onBandChanged: onBandChanged,
            onBassChanged: onBassChanged,
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryStart : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primaryStart : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
