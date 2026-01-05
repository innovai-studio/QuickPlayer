import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class SpeedControl extends StatelessWidget {
  final double speed;
  final int? originalBpm;
  final ValueChanged<double> onSpeedChanged;

  const SpeedControl({
    super.key,
    required this.speed,
    required this.onSpeedChanged,
    this.originalBpm,
  });

  int get speedPercent => (speed * 100).round();

  int? get effectiveBpm {
    if (originalBpm == null) return null;
    return (originalBpm! * speed).round();
  }

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
                'Speed',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  Text(
                    '$speedPercent%',
                    style: const TextStyle(
                      color: AppColors.primaryStart,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (effectiveBpm != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(${effectiveBpm} BPM)',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // +/- control with slider
          Row(
            children: [
              // Minus button
              _buildAdjustButton(
                icon: Icons.remove,
                onTap: () {
                  final newSpeed = (speed - 0.01).clamp(0.25, 2.0);
                  onSpeedChanged(newSpeed);
                },
                onLongPress: () {
                  final newSpeed = (speed - 0.05).clamp(0.25, 2.0);
                  onSpeedChanged(newSpeed);
                },
              ),
              const SizedBox(width: 12),

              // Slider
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.primaryStart,
                    inactiveTrackColor: AppColors.border,
                    thumbColor: AppColors.primaryStart,
                  ),
                  child: Slider(
                    value: speed,
                    min: 0.25,
                    max: 2.0,
                    divisions: 175, // 0.25 to 2.0 in 1% steps
                    onChanged: onSpeedChanged,
                  ),
                ),
              ),

              const SizedBox(width: 12),
              // Plus button
              _buildAdjustButton(
                icon: Icons.add,
                onTap: () {
                  final newSpeed = (speed + 0.01).clamp(0.25, 2.0);
                  onSpeedChanged(newSpeed);
                },
                onLongPress: () {
                  final newSpeed = (speed + 0.05).clamp(0.25, 2.0);
                  onSpeedChanged(newSpeed);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Preset buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [0.5, 0.75, 1.0, 1.25, 1.5].map((presetSpeed) {
              final isSelected = (speed - presetSpeed).abs() < 0.01;
              return GestureDetector(
                onTap: () => onSpeedChanged(presetSpeed),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryStart
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryStart
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    '${(presetSpeed * 100).round()}%',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustButton({
    required IconData icon,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          icon,
          color: AppColors.textPrimary,
          size: 20,
        ),
      ),
    );
  }
}
