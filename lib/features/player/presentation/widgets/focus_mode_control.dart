import 'package:flutter/material.dart';
import '../../../../core/audio/audio_effects_service.dart';
import '../../../../core/constants/app_colors.dart';

/// Single-tap chip row for picking a Focus EQ preset.
///
/// Hidden entirely when the device cannot run Equalizer effects, so the
/// player screen doesn't show a control that does nothing.
class FocusModeControl extends StatelessWidget {
  final EqPreset preset;
  final bool available;
  final ValueChanged<EqPreset> onChanged;

  const FocusModeControl({
    super.key,
    required this.preset,
    required this.available,
    required this.onChanged,
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
                    onTap: () => onChanged(value),
                  ),
                );
              }).toList(),
            ),
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
