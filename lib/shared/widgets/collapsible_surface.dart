import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/storage/storage_service.dart';

/// Card-style container with a tappable header that hides or shows a body.
///
/// Used for the player-screen control panels (Speed, Pitch, Focus EQ,
/// Metronome, A-B Loop, Markers) so the user can collapse the ones they
/// aren't actively touching to avoid mis-taps. Header status is always
/// visible -- the user can read e.g. "Speed: 75%" without expanding.
///
/// `persistKey` stores the expand/collapse choice in the settings box so
/// the layout survives across app launches.
class CollapsibleSurface extends StatefulWidget {
  /// Left-aligned section title (e.g. Text('Speed')).
  final Widget title;

  /// Right-aligned status / quick-control widget rendered next to the
  /// chevron. Shown both when collapsed and expanded so the user can
  /// glance at the current value or hit a switch without opening the
  /// section. `null` for sections without a meaningful summary.
  final Widget? headerTrailing;

  /// The collapsible content shown when expanded.
  final Widget body;

  /// Settings-box key used to persist the expanded state. `null` keeps
  /// state in memory only (resets on app restart).
  final String? persistKey;

  /// Default expansion when no persisted value is found.
  final bool initiallyExpanded;

  const CollapsibleSurface({
    super.key,
    required this.title,
    this.headerTrailing,
    required this.body,
    this.persistKey,
    this.initiallyExpanded = false,
  });

  @override
  State<CollapsibleSurface> createState() => _CollapsibleSurfaceState();
}

class _CollapsibleSurfaceState extends State<CollapsibleSurface> {
  late bool _expanded;
  final _storage = StorageService();

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    final key = widget.persistKey;
    if (key != null) {
      final stored = _storage.getSetting<bool>(_settingKey(key));
      if (stored != null) _expanded = stored;
    }
  }

  String _settingKey(String key) => 'card.$key.expanded';

  void _toggle() {
    setState(() => _expanded = !_expanded);
    final key = widget.persistKey;
    if (key != null) {
      // ignore: discarded_futures
      _storage.setSetting(_settingKey(key), _expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header is always visible. Tappable area is just the title +
          // chevron portion -- a trailing widget like a Switch handles
          // its own taps without toggling the section.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _toggle,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: widget.title),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: const Icon(
                              Icons.expand_more,
                              size: 22,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.headerTrailing != null) ...[
                  const SizedBox(width: 8),
                  widget.headerTrailing!,
                ],
              ],
            ),
          ),

          // Body collapses into the header row when not expanded.
          // ClipRect prevents the partial body from bleeding outside
          // the rounded corners during the animation.
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              heightFactor: _expanded ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: widget.body,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
