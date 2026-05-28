import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/audio/audio_effects_service.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/stem/stem_separator.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../library/data/models/track.dart';
import '../../../stem/data/models/stem_set.dart';
import '../../../stem/presentation/screens/stem_mixer_screen.dart';
import '../../../stem/presentation/widgets/stem_progress_dialog.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Default Speed Section
          _buildSectionHeader('Playback Defaults'),
          _buildCard(
            children: [
              _buildSettingRow(
                'Default Speed',
                '${settings.defaultSpeed.toStringAsFixed(2)}x',
              ),
              Slider(
                value: settings.defaultSpeed,
                min: AppConstants.minSpeed,
                max: AppConstants.maxSpeed,
                divisions: ((AppConstants.maxSpeed - AppConstants.minSpeed) /
                        AppConstants.speedStep)
                    .round(),
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).setDefaultSpeed(value);
                },
              ),
              const Divider(color: AppColors.divider),
              _buildSettingRow(
                'Default Pitch',
                _formatPitch(settings.defaultPitchSemitones),
              ),
              Slider(
                value: settings.defaultPitchSemitones.toDouble(),
                min: AppConstants.minPitchSemitones.toDouble(),
                max: AppConstants.maxPitchSemitones.toDouble(),
                divisions: AppConstants.maxPitchSemitones -
                    AppConstants.minPitchSemitones,
                onChanged: (value) {
                  ref
                      .read(settingsProvider.notifier)
                      .setDefaultPitchSemitones(value.round());
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Default Focus
          _buildSectionHeader('Default Focus'),
          _buildCard(
            children: [
              _buildSettingRow(
                'Focus Preset',
                settings.defaultFocusMode == EqPreset.flat
                    ? 'Off'
                    : settings.defaultFocusMode.label,
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: EqPreset.values.map((preset) {
                    final isSelected = preset == settings.defaultFocusMode;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => ref
                            .read(settingsProvider.notifier)
                            .setDefaultFocusMode(preset),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
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
                            preset.label,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Display Section
          _buildSectionHeader('Display'),
          _buildCard(
            children: [
              _buildSwitchRow(
                'Show Waveform',
                'Display audio waveform visualization',
                settings.showWaveform,
                (value) {
                  ref.read(settingsProvider.notifier).setShowWaveform(value);
                },
              ),
              const Divider(color: AppColors.divider),
              _buildSwitchRow(
                'Keep Screen On',
                'Prevent screen from turning off during playback',
                settings.keepScreenOn,
                (value) {
                  ref.read(settingsProvider.notifier).setKeepScreenOn(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // About Section
          _buildSectionHeader('About'),
          _buildCard(
            children: [
              _buildInfoRow('App Name', AppConstants.appName),
              const Divider(color: AppColors.divider),
              _buildInfoRow('Version', AppConstants.appVersion),
            ],
          ),
          const SizedBox(height: 24),

          // Debug-only: on-device stem-separation benchmark (P1). Stripped
          // from release builds. Requires the model + segment pushed to
          // /data/local/tmp (see docs/STEM_ONNX_EXPORT_SPIKE.md).
          if (kDebugMode) ...[
            _buildSectionHeader('Debug — Stem Separation'),
            _buildCard(
              children: [
                Center(
                  child: TextButton(
                    onPressed: () => _runStemBenchmark(context),
                    child: const Text(
                      'Run stem benchmark (CPU/XNNPACK/NNAPI)',
                      style: TextStyle(color: AppColors.accent),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => _runStemSeparate(context),
                    child: const Text(
                      'Separate 20s excerpt (P2a)',
                      style: TextStyle(color: AppColors.accent),
                    ),
                  ),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => _openMixerWithExcerpt(context),
                    child: const Text(
                      'Open mixer w/ excerpt stems (P3)',
                      style: TextStyle(color: AppColors.accent),
                    ),
                  ),
                ),
                _NpuToggleRow(),
              ],
            ),
            const SizedBox(height: 24),
          ],

          // Reset Button
          Center(
            child: TextButton(
              onPressed: () => _showResetDialog(context, ref),
              child: const Text(
                'Reset to Defaults',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Debug: open the mixer directly on the excerpt stems already written
  /// to the app's external files dir (skips the ~11 min full separation
  /// so we can verify the mixer's sync + mute/solo/volume quickly).
  Future<void> _openMixerWithExcerpt(BuildContext context) async {
    final ext = await getExternalStorageDirectory();
    final dir = '${ext!.path}/stems_out';
    final stems = StemSet(
      trackId: 'debug_excerpt',
      drumsPath: '$dir/drums.m4a',
      bassPath: '$dir/bass.m4a',
      otherPath: '$dir/other.m4a',
      vocalsPath: '$dir/vocals.m4a',
      segmentSeconds: 2.0,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final track = Track(
      id: 'debug_excerpt',
      name: 'MERs excerpt (debug)',
      filePath: '$dir/drums.m4a',
      durationMs: 20000,
      fileSize: 0,
      createdAt: DateTime.now(),
    );
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StemMixerScreen(track: track, stems: stems),
    ));
  }

  Future<void> _runStemSeparate(BuildContext context) async {
    // App can't write to /data/local/tmp; use its external files dir
    // (pullable at /sdcard/Android/data/<pkg>/files/stems_out).
    final ext = await getExternalStorageDirectory();
    final outDir = '${ext!.path}/stems_out';
    final r = await StemSeparator.instance.separate(
      modelPath: '/data/local/tmp/htdemucs_2s.onnx',
      audioPath: '/data/local/tmp/mers_excerpt.m4a',
      outDir: outDir,
      threads: 4,
    );
    debugPrint('STEMSEP start $r');
    if (!context.mounted || r?['started'] != true) return;
    // Persistent progress dialog that updates smoothly from the stream.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const StemProgressDialog(),
    );
  }

  Future<void> _runStemBenchmark(BuildContext context) async {
    // 2 s segment model (~1.4 GB peak) to fit 4 GB devices; weights mmap'd.
    const model = '/data/local/tmp/htdemucs_2s.onnx';
    const seg = '/data/local/tmp/mers_seg2s.raw';
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Running stem benchmark… (see logcat)')),
    );
    final lines = <String>[];
    for (final provider in ['cpu', 'xnnpack', 'nnapi']) {
      final r = await StemSeparator.instance.benchmark(
        modelPath: model,
        provider: provider,
        threads: 4,
        inputRawPath: seg,
      );
      // Surfaced via debugPrint so it lands in logcat for capture.
      debugPrint('STEMBENCH[$provider] $r');
      if (r != null && r['ok'] == true) {
        lines.add('$provider: ${r['inferMs']}ms/seg '
            '→ ~${(r['fullSongEstSec'] as num).toStringAsFixed(0)}s/song '
            '(load ${r['loadMs']}ms, absMean ${(r['outAbsMean'] as num).toStringAsFixed(4)})');
      } else {
        lines.add('$provider: FAILED ${r?['error']}');
      }
    }
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Stem benchmark',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(lines.join('\n\n'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSettingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primaryStart,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primaryStart,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPitch(int semitones) {
    if (semitones == 0) return '0';
    return semitones > 0 ? '+$semitones' : '$semitones';
  }

  void _showResetDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text(
          'Reset Settings',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to reset all settings to defaults?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).resetToDefaults();
              Navigator.pop(context);
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Debug toggle: enable the NNAPI execution provider for stem separation.
/// Default OFF -- production users get the proven CPU path. We flip this
/// on per device once we've measured NPU acceleration vs CPU baseline on
/// a real flagship (P3-related, behind a feature flag for safety).
class _NpuToggleRow extends StatefulWidget {
  @override
  State<_NpuToggleRow> createState() => _NpuToggleRowState();
}

class _NpuToggleRowState extends State<_NpuToggleRow> {
  final _storage = StorageService();
  bool _on = false;

  @override
  void initState() {
    super.initState();
    _on = _storage.getSetting<bool>('stem_use_npu') == true;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Use NNAPI for stem separation',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
          ),
          Switch(
            value: _on,
            onChanged: (v) async {
              setState(() => _on = v);
              await _storage.setSetting('stem_use_npu', v);
            },
          ),
        ],
      ),
    );
  }
}
