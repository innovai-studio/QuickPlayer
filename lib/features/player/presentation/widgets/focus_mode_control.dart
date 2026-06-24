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
  final bool spectrumEnabled;
  final ValueChanged<EqPreset> onPresetChanged;
  final void Function(int bandIndex, int millibel) onBandChanged;
  final ValueChanged<int> onBassChanged;
  final ValueChanged<bool> onSpectrumToggle;

  const FocusModeControl({
    super.key,
    required this.preset,
    required this.available,
    required this.capabilities,
    required this.bandLevelsMillibel,
    required this.bassStrengthMilli,
    required this.spectrumEnabled,
    required this.onPresetChanged,
    required this.onBandChanged,
    required this.onBassChanged,
    required this.onSpectrumToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (!available) return const SizedBox.shrink();

    // Outer Container + title row + status indicators (preset label,
    // spectrum toggle icon) live in the CollapsibleSurface wrapper at
    // the player_screen level. We render only the body here: preset
    // chip row + EQ visualiser + sliders.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            spectrumEnabled: spectrumEnabled,
            onBandChanged: onBandChanged,
            onBassChanged: onBassChanged,
            onEnableSpectrum: () => onSpectrumToggle(true),
          ),
        ],
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
