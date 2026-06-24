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

/// Storage key for "the trackId whose separation foreground service is
/// in flight right now." Survives Dart-isolate restart so when the user
/// swipes the app away mid-separation and reopens, the new StemController
/// can re-attach to the still-running service instead of falsely treating
/// the BUSY response as an error. Set on start, cleared on done/error.
const _inflightTrackKey = 'inflight_stem_track';

class StemController extends StateNotifier<StemState> {
  StemController(this.trackId) : super(const StemState()) {
    _init();
  }

  final String trackId;
  final _storage = StorageService();
  final _sep = StemSeparator.instance;
  StreamSubscription<Map<String, dynamic>>? _sub;
  // Captured at start so the `done` handler can persist the right
  // segment in the StemSet even when we re-attached to an in-flight
  // service (no fresh forRam() call to lean on).
  StemModelConfig? _activeConfig;

  /// Cache + auto-resume in one place. Order matters: cache hit wins (we
  /// never re-attach to a finished separation), then we check whether a
  /// service is still chewing through *this* trackId from a previous app
  /// session and reattach the progress stream if so.
  Future<void> _init() async {
    await _storage.init();
    final cached = _storage.getStemSet(trackId);
    if (cached != null && File(cached.drumsPath).existsSync()) {
      state =
          state.copyWith(status: StemStatus.ready, stems: cached, progress: 1);
      return;
    }
    await _resumeIfRunning();
  }

  /// If the native foreground service is still running AND its in-flight
  /// trackId matches ours, jump straight into the separating state and
  /// listen for the tail end of progress/done events. Lets the user swipe
  /// the app away during a 10-minute separation and reopen without losing
  /// the run.
  Future<void> _resumeIfRunning() async {
    final running = await _sep.isRunning();
    final inflight = _storage.getSetting<String>(_inflightTrackKey);
    if (!running) {
      // Service died (system kill, OOM) — wipe stale marker so future
      // separations don't get confused by a ghost.
      if (inflight != null && inflight.isNotEmpty) {
        await _storage.setSetting(_inflightTrackKey, '');
      }
      return;
    }
    if (inflight != trackId) {
      // Some other track is still being separated — leave its controller
      // to handle the events; ours stays idle.
      return;
    }
    // We're the in-flight one. Reattach to the live stream. Best-effort
    // RAM lookup so the eventual `done` handler can stamp a sensible
    // segment value in the cached StemSet; if it doesn't match the
    // running model exactly (rare RAM-tier flip across reboots) the
    // segment is metadata only, not used for playback.
    final ramMb = await _sep.totalRamMb();
    _activeConfig = StemModelConfig.forRam(ramMb);
    state = const StemState(status: StemStatus.separating, progress: 0);
    _subscribe();
  }

  /// Wires the progressStream listener that drives state for the current
  /// run. Pulled into its own method so both [separate] and
  /// [_resumeIfRunning] reuse the exact same event handling.
  void _subscribe() {
    _sub?.cancel();
    _sub = _sep.progressStream.listen((e) async {
      switch (e['event']) {
        case 'progress':
          state = state.copyWith(progress: (e['progress'] as num).toDouble());
        case 'done':
          final paths = (e['stems'] as List).cast<String>();
          final config = _activeConfig;
          final set = StemSet(
            trackId: trackId,
            drumsPath: paths[0],
            bassPath: paths[1],
            otherPath: paths[2],
            vocalsPath: paths[3],
            segmentSeconds: config?.segmentSeconds ?? 0,
            createdAtMs: DateTime.now().millisecondsSinceEpoch,
          );
          await _storage.saveStemSet(set);
          await _storage.setSetting(_inflightTrackKey, '');
          state = state.copyWith(
              status: StemStatus.ready, stems: set, progress: 1);
          _sub?.cancel();
        case 'error':
          await _storage.setSetting(_inflightTrackKey, '');
          state = state.copyWith(
              status: StemStatus.error, error: e['error']?.toString());
          _sub?.cancel();
      }
    });
  }

  /// Kick off separation for [track]. Picks the segment/model by device
  /// RAM, runs the foreground service, and caches the result on success.
  /// If a separation is already running for this same trackId, we treat
  /// the tap as "show me the progress" rather than starting a new one.
  Future<void> separate(Track track) async {
    if (state.status == StemStatus.separating) return;

    final ramMb = await _sep.totalRamMb();
    final config = StemModelConfig.forRam(ramMb);
    final modelPath = await _resolveModelPath(config);
    if (modelPath == null) {
      state = state.copyWith(
          status: StemStatus.error,
          error: 'Stem model not installed (${config.graphFile})');
      return;
    }
    _activeConfig = config;

    // Race-safe reattach: if a service is already running for us (rare
    // — usually [_resumeIfRunning] caught it at init, but a quick swipe
    // can land here too), just subscribe to the live stream instead of
    // pushing the native side into BUSY.
    if (await _sep.isRunning()) {
      final inflight = _storage.getSetting<String>(_inflightTrackKey);
      if (inflight == trackId) {
        state = const StemState(status: StemStatus.separating, progress: 0);
        _subscribe();
        return;
      }
      // A different track is mid-separation. Surface a clean error
      // rather than racing native's BUSY guard.
      state = state.copyWith(
          status: StemStatus.error,
          error: 'Another track is still being separated');
      return;
    }

    final outDir = await _stemDir(trackId);

    // Persist BEFORE starting so a crash between "service started" and
    // the first done event can still be recovered on next launch.
    await _storage.setSetting(_inflightTrackKey, trackId);
    state = const StemState(status: StemStatus.separating, progress: 0);
    _subscribe();

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
      await _storage.setSetting(_inflightTrackKey, '');
      state = state.copyWith(
          status: StemStatus.error,
          error: r?['error']?.toString() ?? 'start failed');
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
