import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/stem/stem_separator.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../library/data/models/track.dart';
import '../../data/model_installer.dart';
import '../../data/models/stem_set.dart';
import '../../data/stem_model_config.dart';

enum StemStatus { idle, separating, ready, error }

class StemState {
  final StemStatus status;
  final double progress;
  final StemSet? stems;
  final String? error;

  const StemState({
    this.status = StemStatus.idle,
    this.progress = 0,
    this.stems,
    this.error,
  });

  StemState copyWith({
    StemStatus? status,
    double? progress,
    StemSet? stems,
    String? error,
  }) =>
      StemState(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        stems: stems ?? this.stems,
        error: error,
      );
}

/// Per-track stem-separation state, keyed by trackId so each track keeps
/// its own status while the user navigates.
final stemControllerProvider =
    StateNotifierProvider.family<StemController, StemState, String>(
  (ref, trackId) => StemController(trackId),
);

class StemController extends StateNotifier<StemState> {
  StemController(this.trackId) : super(const StemState()) {
    _loadCache();
  }

  final String trackId;
  final _storage = StorageService();
  final _sep = StemSeparator.instance;
  StreamSubscription<Map<String, dynamic>>? _sub;

  /// If this track was already separated and the files still exist, jump
  /// straight to ready.
  Future<void> _loadCache() async {
    await _storage.init();
    final cached = _storage.getStemSet(trackId);
    if (cached != null && File(cached.drumsPath).existsSync()) {
      state = state.copyWith(status: StemStatus.ready, stems: cached, progress: 1);
    }
  }

  /// Kick off separation for [track]. Picks the segment/model by device
  /// RAM, runs the foreground service, and caches the result on success.
  Future<void> separate(Track track) async {
    if (state.status == StemStatus.separating) return;
    state = const StemState(status: StemStatus.separating, progress: 0);

    final ramMb = await _sep.totalRamMb();
    final config = StemModelConfig.forRam(ramMb);
    final modelPath = await _resolveModelPath(config);
    if (modelPath == null) {
      state = state.copyWith(
          status: StemStatus.error,
          error: 'Stem model not installed (${config.graphFile})');
      return;
    }
    final outDir = await _stemDir(trackId);

    _sub?.cancel();
    _sub = _sep.progressStream.listen((e) async {
      switch (e['event']) {
        case 'progress':
          state = state.copyWith(progress: (e['progress'] as num).toDouble());
        case 'done':
          final paths = (e['stems'] as List).cast<String>();
          final set = StemSet(
            trackId: trackId,
            drumsPath: paths[0],
            bassPath: paths[1],
            otherPath: paths[2],
            vocalsPath: paths[3],
            segmentSeconds: config.segmentSeconds,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          await _storage.saveStemSet(set);
          state = state.copyWith(
              status: StemStatus.ready, stems: set, progress: 1);
          _sub?.cancel();
        case 'error':
          state = state.copyWith(
              status: StemStatus.error, error: e['error']?.toString());
          _sub?.cancel();
      }
    });

    // NPU acceleration is opt-in (default off) until we've measured it
    // on real flagships; the native side falls back to CPU on any NNAPI
    // init failure anyway.
    final useNnapi = _storage.getSetting<bool>('stem_use_npu') == true;
    final r = await _sep.separate(
      modelPath: modelPath,
      audioPath: track.filePath,
      outDir: outDir,
      provider: useNnapi ? 'nnapi' : 'cpu',
    );
    if (r?['started'] != true) {
      state = state.copyWith(
          status: StemStatus.error, error: r?['error']?.toString() ?? 'start failed');
      _sub?.cancel();
    }
  }

  Future<void> clear() async {
    await _storage.deleteStemSet(trackId);
    final dir = Directory(await _stemDir(trackId));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    state = const StemState();
  }

  /// Resolve the model file. Delegates to [ModelInstaller.resolveGraphPath]
  /// so the action button and the controller can't drift on what counts as
  /// "installed" (CDN-installed under appSupport/models vs. dev-pushed
  /// /data/local/tmp).
  Future<String?> _resolveModelPath(StemModelConfig c) =>
      ModelInstaller.resolveGraphPath(c);

  Future<String> _stemDir(String id) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/stems/$id');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
