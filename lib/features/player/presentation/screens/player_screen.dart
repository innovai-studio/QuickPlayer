import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/audio/audio_effects_service.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../../shared/extensions/duration_extension.dart';
import '../../../library/data/models/track.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../data/models/play_mode.dart';
import '../providers/player_provider.dart';
import '../providers/player_state.dart';
import '../widgets/playback_controls.dart';
import '../widgets/speed_control.dart';
import '../widgets/pitch_control.dart';
import '../widgets/ab_loop_control.dart';
import '../widgets/focus_mode_control.dart';
import '../widgets/marker_list.dart';
import '../widgets/waveform_view.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String trackId;

  const PlayerScreen({super.key, required this.trackId});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTrack();
    });
  }

  Future<void> _loadTrack() async {
    // Check if this track is already loaded and playing
    final currentTrack = ref.read(playerProvider).currentTrack;
    if (currentTrack != null && currentTrack.id == widget.trackId) {
      // Track is already loaded, don't reload
      return;
    }

    // Device audio tracks (IDs starting with "device_") are loaded via loadFromPath
    // and won't be in StorageService. They're already loaded by the player provider.
    if (widget.trackId.startsWith('device_')) {
      // Device audio should already be loaded by loadFromPath call before navigation
      // If somehow not loaded yet, just return (the UI will show loading state)
      return;
    }

    final storage = StorageService();
    await storage.init();
    final track = storage.getTrack(widget.trackId);
    if (track != null) {
      ref.read(playerProvider.notifier).loadTrack(track);
    } else {
      // Track not found (possibly deleted) - only for imported tracks
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Track not found')),
        );
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final settings = ref.watch(settingsProvider);
    final track = playerState.currentTrack;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          track?.name ?? 'Loading...',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
      ),
      body: playerState.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryStart),
            )
          : playerState.error != null
              ? Center(
                  child: Text(
                    playerState.error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Waveform or Progress bar
                      if (settings.showWaveform && track != null)
                        WaveformView(
                          filePath: track.filePath,
                          position: playerState.position,
                          duration: playerState.duration,
                          onSeek: (position) =>
                              ref.read(playerProvider.notifier).seek(position),
                        )
                      else
                        _buildProgressBar(playerState),
                      const SizedBox(height: 8),
                      // Time display
                      _buildTimeDisplay(playerState),
                      const SizedBox(height: 12),

                      // BPM and Key display
                      if (track != null) _buildTrackInfo(
                        track,
                        playerState.isAnalyzing,
                        playerState.speed,
                        playerState.pitchSemitones,
                      ),
                      const SizedBox(height: 16),

                      // Play mode toggle
                      _buildPlayModeToggle(playerState.playMode),
                      const SizedBox(height: 8),

                      // Playback controls
                      PlaybackControls(
                        isPlaying: playerState.isPlaying,
                        onPlayPause: () =>
                            ref.read(playerProvider.notifier).togglePlay(),
                        onSeekBackward: () => _seekRelative(-10),
                        onSeekForward: () => _seekRelative(10),
                        onPrevious: () =>
                            ref.read(playerProvider.notifier).playPrevious(),
                        onNext: () =>
                            ref.read(playerProvider.notifier).playNext(),
                        hasPrevious: playerState.hasPrevious,
                        hasNext: playerState.hasNext,
                      ),
                      const SizedBox(height: 32),

                      // Speed control
                      SpeedControl(
                        speed: playerState.speed,
                        originalBpm: track?.bpm,
                        onSpeedChanged: (speed) =>
                            ref.read(playerProvider.notifier).setSpeed(speed),
                      ),
                      const SizedBox(height: 16),

                      // Pitch control
                      PitchControl(
                        pitchSemitones: playerState.pitchSemitones,
                        onPitchChanged: (semitones) => ref
                            .read(playerProvider.notifier)
                            .setPitchSemitones(semitones),
                      ),
                      const SizedBox(height: 16),

                      // Focus EQ (hidden on devices without AudioEffect)
                      FocusModeControl(
                        preset: playerState.focusMode,
                        available: playerState.focusAvailable,
                        capabilities: AudioEffectsService().capabilities,
                        bandLevelsMillibel: playerState.bandLevelsMillibel,
                        bassStrengthMilli: playerState.bassStrengthMilli,
                        onPresetChanged: (preset) => ref
                            .read(playerProvider.notifier)
                            .setFocusMode(preset),
                        onBandChanged: (i, mb) => ref
                            .read(playerProvider.notifier)
                            .setBandLevel(i, mb),
                        onBassChanged: (m) => ref
                            .read(playerProvider.notifier)
                            .setBassStrength(m),
                      ),
                      if (playerState.focusAvailable)
                        const SizedBox(height: 16),

                      // A-B Loop control
                      ABLoopControl(
                        abLoop: playerState.abLoop,
                        currentPosition: playerState.position,
                        duration: playerState.duration,
                        onSetA: () => ref.read(playerProvider.notifier).setPointA(),
                        onSetB: () => ref.read(playerProvider.notifier).setPointB(),
                        onToggle: () =>
                            ref.read(playerProvider.notifier).toggleAbLoop(),
                        onClear: () =>
                            ref.read(playerProvider.notifier).clearAbLoop(),
                      ),
                      const SizedBox(height: 16),

                      // Markers
                      MarkerListWidget(
                        markers: playerState.markers,
                        onMarkerTap: (marker) =>
                            ref.read(playerProvider.notifier).jumpToMarker(marker),
                        onAddMarker: () => _showAddMarkerDialog(),
                        onDeleteMarker: (markerId) =>
                            ref.read(playerProvider.notifier).deleteMarker(markerId),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildProgressBar(AppPlayerState playerState) {
    final Duration position = playerState.position;
    final Duration duration = playerState.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: AppColors.primaryStart,
        inactiveTrackColor: AppColors.surfaceDark,
        thumbColor: AppColors.primaryStart,
        overlayColor: AppColors.primaryStart.withValues(alpha: 0.2),
      ),
      child: Slider(
        value: progress.clamp(0.0, 1.0),
        onChanged: (value) {
          final newPosition = Duration(
            milliseconds: (value * duration.inMilliseconds).round(),
          );
          ref.read(playerProvider.notifier).seek(newPosition);
        },
      ),
    );
  }

  Widget _buildTimeDisplay(AppPlayerState playerState) {
    final Duration position = playerState.position;
    final Duration duration = playerState.duration;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            position.toDisplayString(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Text(
            duration.toDisplayString(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackInfo(Track track, bool isAnalyzing, double speed, int pitchSemitones) {
    // Calculate effective BPM based on speed
    String bpmDisplay;
    if (isAnalyzing && track.bpm == null) {
      bpmDisplay = '...';
    } else if (track.bpm != null) {
      final effectiveBpm = (track.bpm! * speed).round();
      bpmDisplay = effectiveBpm.toString();
    } else {
      bpmDisplay = '--';
    }

    // Calculate transposed key based on pitch
    String keyDisplay;
    if (isAnalyzing && track.musicalKey == null) {
      keyDisplay = '...';
    } else if (track.musicalKey != null) {
      keyDisplay = _transposeKey(track.musicalKey!, pitchSemitones);
    } else {
      keyDisplay = '--';
    }

    return GestureDetector(
      onTap: () => _showEditTrackInfoDialog(track),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // BPM
            _buildInfoChip(
              icon: Icons.speed,
              label: 'BPM',
              value: bpmDisplay,
              isLoading: isAnalyzing && track.bpm == null,
            ),
            const SizedBox(width: 24),
            // Key
            _buildInfoChip(
              icon: Icons.music_note,
              label: 'Key',
              value: keyDisplay,
              isLoading: isAnalyzing && track.musicalKey == null,
            ),
            const SizedBox(width: 8),
            // Edit hint or analyzing indicator
            if (isAnalyzing)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primaryStart,
                ),
              )
            else
              const Icon(
                Icons.edit,
                color: AppColors.textSecondary,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }

  /// Transpose a musical key by semitones
  String _transposeKey(String key, int semitones) {
    if (semitones == 0) return key;

    final noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final flatNoteNames = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];

    // Parse the key (e.g., "C Major", "F# Minor", "Bb Major")
    String rootNote;
    String quality = '';
    bool useFlats = false;

    // Extract root note and quality
    final parts = key.split(' ');
    if (parts.isEmpty) return key;

    rootNote = parts[0];
    if (parts.length > 1) {
      quality = ' ${parts.sublist(1).join(' ')}';
    }

    // Check if original uses flats
    if (rootNote.contains('b')) {
      useFlats = true;
    }

    // Find the root note index
    int noteIndex = -1;
    for (int i = 0; i < noteNames.length; i++) {
      if (rootNote == noteNames[i] || rootNote == flatNoteNames[i]) {
        noteIndex = i;
        break;
      }
    }

    if (noteIndex == -1) return key;

    // Transpose
    int newIndex = (noteIndex + semitones) % 12;
    if (newIndex < 0) newIndex += 12;

    // Return transposed key
    final newRoot = useFlats ? flatNoteNames[newIndex] : noteNames[newIndex];
    return '$newRoot$quality';
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    bool isLoading = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.primaryStart, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: isLoading ? AppColors.textSecondary : AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showEditTrackInfoDialog(Track track) {
    final bpmController = TextEditingController(
      text: track.bpm?.toString() ?? '',
    );
    final keyController = TextEditingController(
      text: track.musicalKey ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text(
          'Edit Track Info',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: bpmController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'BPM',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                hintText: 'e.g. 120',
                hintStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Key',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                hintText: 'e.g. C major, Am',
                hintStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final bpm = int.tryParse(bpmController.text.trim());
              final key = keyController.text.trim();

              final updatedTrack = track.copyWith(
                bpm: bpm,
                musicalKey: key.isEmpty ? null : key,
              );

              // Save to storage
              final storage = StorageService();
              await storage.init();
              await storage.saveTrack(updatedTrack);

              // Update player state
              ref.read(playerProvider.notifier).updateCurrentTrack(updatedTrack);

              // Refresh library
              ref.read(libraryProvider.notifier).loadTracks();

              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayModeToggle(PlayMode playMode) {
    IconData icon;
    String label;

    switch (playMode) {
      case PlayMode.sequential:
        icon = Icons.arrow_forward;
        label = 'Sequential';
        break;
      case PlayMode.loopAll:
        icon = Icons.repeat;
        label = 'Loop All';
        break;
      case PlayMode.loopOne:
        icon = Icons.repeat_one;
        label = 'Loop One';
        break;
      case PlayMode.shuffle:
        icon = Icons.shuffle;
        label = 'Shuffle';
        break;
    }

    return GestureDetector(
      onTap: () => ref.read(playerProvider.notifier).cyclePlayMode(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: playMode == PlayMode.sequential
                  ? AppColors.textSecondary
                  : AppColors.primaryStart,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: playMode == PlayMode.sequential
                    ? AppColors.textSecondary
                    : AppColors.primaryStart,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _seekRelative(int seconds) {
    final playerState = ref.read(playerProvider);
    final newPosition = playerState.position + Duration(seconds: seconds);
    final clampedPosition = Duration(
      milliseconds: newPosition.inMilliseconds.clamp(
        0,
        playerState.duration.inMilliseconds,
      ),
    );
    ref.read(playerProvider.notifier).seek(clampedPosition);
  }

  void _showAddMarkerDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text(
          'Add Marker',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Marker name',
            hintStyle: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final label = controller.text.trim();
              if (label.isNotEmpty) {
                ref.read(playerProvider.notifier).addMarker(label);
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
