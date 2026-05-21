import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/extensions/duration_extension.dart';
import '../../data/models/marker.dart';

class MarkerListWidget extends StatelessWidget {
  final List<Marker> markers;
  final ValueChanged<Marker> onMarkerTap;
  final VoidCallback onAddMarker;
  final ValueChanged<String> onDeleteMarker;

  const MarkerListWidget({
    super.key,
    required this.markers,
    required this.onMarkerTap,
    required this.onAddMarker,
    required this.onDeleteMarker,
  });

  @override
  Widget build(BuildContext context) {
    // Outer Container + title row + Add button now live in the
    // CollapsibleSurface wrapper at the player_screen level. The Add
    // button is exposed via the wrapper's headerTrailing so users can
    // add a marker without expanding the section.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          if (markers.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No markers yet.\nTap "Add" to mark the current position.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ...markers.map((marker) => _buildMarkerItem(marker)),
        ],
    );
  }

  Widget _buildMarkerItem(Marker marker) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => onMarkerTap(marker),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Color dot
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: marker.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),

              // Time
              Text(
                marker.position.toDisplayString(),
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 12),

              // Label
              Expanded(
                child: Text(
                  marker.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Delete button
              GestureDetector(
                onTap: () => onDeleteMarker(marker.id),
                child: const Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
