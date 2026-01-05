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
                'Pitch',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _formatPitch(pitchSemitones),
                style: const TextStyle(
                  color: AppColors.primaryStart,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

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
      ),
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

  String _formatPitch(int semitones) {
    if (semitones == 0) return '0';
    return semitones > 0 ? '+$semitones' : '$semitones';
  }
}
