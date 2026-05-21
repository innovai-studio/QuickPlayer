import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';

class PitchControl extends StatelessWidget {
  final int pitchSemitones;
  final ValueChanged<int> onPitchChanged;

  const PitchControl({
    super.key,
    required this.pitchSemitones,
    required this.onPitchChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Outer Container + title row are now provided by the
    // CollapsibleSurface wrapper at the player_screen level.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primaryStart,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.primaryStart,
            ),
            child: Slider(
              value: pitchSemitones.toDouble(),
              min: AppConstants.minPitchSemitones.toDouble(),
              max: AppConstants.maxPitchSemitones.toDouble(),
              divisions: AppConstants.maxPitchSemitones -
                  AppConstants.minPitchSemitones,
              onChanged: (value) => onPitchChanged(value.round()),
            ),
          ),

          // Quick buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildButton('-1', () => onPitchChanged(pitchSemitones - 1)),
              const SizedBox(width: 16),
              _buildButton(
                'Reset',
                () => onPitchChanged(0),
                isReset: true,
              ),
              const SizedBox(width: 16),
              _buildButton('+1', () => onPitchChanged(pitchSemitones + 1)),
            ],
          ),
        ],
    );
  }

  Widget _buildButton(String label, VoidCallback onTap, {bool isReset = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isReset && pitchSemitones == 0
              ? AppColors.primaryStart
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isReset && pitchSemitones == 0
                ? AppColors.primaryStart
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isReset && pitchSemitones == 0
                ? Colors.white
                : AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

}
