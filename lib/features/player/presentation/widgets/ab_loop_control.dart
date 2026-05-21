import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/extensions/duration_extension.dart';
import '../../data/models/ab_loop.dart';

class ABLoopControl extends StatelessWidget {
  final ABLoop? abLoop;
  final Duration currentPosition;
  final Duration duration;
  final VoidCallback onSetA;
  final VoidCallback onSetB;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  const ABLoopControl({
    super.key,
    this.abLoop,
    required this.currentPosition,
    required this.duration,
    required this.onSetA,
    required this.onSetB,
    required this.onToggle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasA = abLoop?.hasPointA ?? false;
    final hasB = abLoop?.hasPointB ?? false;
    final isActive = abLoop?.isActive ?? false;
    final isComplete = abLoop?.isComplete ?? false;

    // Outer Container + title row + ACTIVE badge are handled by the
    // CollapsibleSurface wrapper at the player_screen level. The
    // wrapper passes the ACTIVE badge as headerTrailing so the
    // collapsed state still surfaces whether the loop is engaged.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // A-B buttons row
          Row(
            children: [
              // Set A button
              Expanded(
                child: _buildSetButton(
                  'A',
                  hasA ? abLoop!.pointA!.toDisplayString() : 'Set A',
                  hasA,
                  onSetA,
                ),
              ),
              const SizedBox(width: 12),

              // Set B button
              Expanded(
                child: _buildSetButton(
                  'B',
                  hasB ? abLoop!.pointB!.toDisplayString() : 'Set B',
                  hasB,
                  onSetB,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Toggle and Clear row
          Row(
            children: [
              // Toggle loop
              Expanded(
                child: GestureDetector(
                  onTap: isComplete ? onToggle : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.accent
                          : (isComplete
                              ? AppColors.primaryStart.withValues(alpha: 0.2)
                              : AppColors.border.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        isActive ? 'Disable Loop' : 'Enable Loop',
                        style: TextStyle(
                          color: isActive
                              ? Colors.black
                              : (isComplete
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Clear button
              GestureDetector(
                onTap: (hasA || hasB) ? onClear : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: (hasA || hasB)
                          ? AppColors.error
                          : AppColors.border.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: (hasA || hasB)
                          ? AppColors.error
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
    );
  }

  Widget _buildSetButton(
      String label, String displayText, bool isSet, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSet ? AppColors.accent.withValues(alpha: 0.2) : AppColors.border,
          borderRadius: BorderRadius.circular(8),
          border: isSet ? Border.all(color: AppColors.accent) : null,
        ),
        child: Center(
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSet ? AppColors.accent : AppColors.textSecondary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                displayText,
                style: TextStyle(
                  color: isSet ? AppColors.textPrimary : AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
