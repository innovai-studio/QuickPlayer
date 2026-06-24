import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'stem_model_config.dart';

/// One progress tick. `bytesDone` / `bytesTotal` are cumulative across
/// every asset in the variant so a single linear bar can render the whole
/// install. `assetIndex` / `assetCount` + `assetName` drive the per-file
/// caption (e.g. "Graph (1/2)" → "Weights (2/2)"). `bytesPerSec` is a
/// short EMA so the rate text doesn't jitter every frame.
class ModelInstallProgress {
  final int bytesDone;
  final int bytesTotal;
  final int assetIndex;
  final int assetCount;
  final String assetName;
  final double bytesPerSec;

  const ModelInstallProgress({
    required this.bytesDone,
    required this.bytesTotal,
    required this.assetIndex,
    required this.assetCount,
    required this.assetName,
    required this.bytesPerSec,
  });

  double get fraction =>
      bytesTotal == 0 ? 0 : (bytesDone / bytesTotal).clamp(0.0, 1.0);
}

/// Downloads htdemucs model variants from GitHub Releases into the app's
/// support dir so ORT can later mmap them via [StemModelConfig.graphFile].
///
/// Design choices:
/// * One installer instance per attempt — `cancel()` aborts the in-flight
///   stream + deletes the partial .tmp file. New install starts fresh
///   (no resume yet; ~166 MB on a working connection is < 5 min on LTE).
/// * Atomic install: each file streams into `<name>.tmp` and only renames
///   to its final name after size + (optional) sha256 verify. A torn
///   download therefore never leaves a half-broken model in place — the
///   next `isInstalled()` call simply sees nothing.
/// * Streams `ModelInstallProgress` so the UI matches StemProgressDialog's
///   single-bar idiom across both files in the variant.
class ModelInstaller {
  ModelInstaller(this.config);

  final StemModelConfig config;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30);

  final _controller = StreamController<ModelInstallProgress>.broadcast();
  Stream<ModelInstallProgress> get progressStream => _controller.stream;

  bool _cancelled = false;
  HttpClientRequest? _activeRequest;
  IOSink? _activeSink;
  File? _activeTmp;

  /// Returns the absolute path to the models directory for this app
  /// (creating it on demand). All variant files live flat under here so
  /// ORT can resolve `external_data_info` by relative filename.
  static Future<Directory> modelsDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/models');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Path to the graph file the native pipeline should open for [config]
  /// (ORT mmaps any sibling .weights blobs from the same directory). Looks
  /// at the installed appSupport/models/ location first, then the dev-only
  /// /data/local/tmp/ adb-push fallback. Returns null when nothing is on
  /// disk — caller should kick off [install] in that case.
  static Future<String?> resolveGraphPath(StemModelConfig config) async {
    final dir = await modelsDir();
    // Full install — including the sibling .weights blob — must be
    // present. Falling back to just the .onnx existence check skips the
    // download dialog after a partial install (graph done, weights
    // interrupted), then hands an incomplete model to ORT which crashes
    // on mmap'ing the missing weights file.
    if (await isInstalled(config)) {
      return '${dir.path}/${config.graphFile}';
    }
    // Dev fallback: assume manually adb-pushed alongside its weights;
    // no per-asset audit (the dev knows what they pushed).
    final dev = File('/data/local/tmp/${config.graphFile}');
    if (dev.existsSync()) return dev.path;
    return null;
  }

  /// True if every asset for [config] is already on disk at its expected
  /// size. We don't re-hash on every check — a size mismatch is the only
  /// way a successful install gets corrupted later (manual edit / FS
  /// glitch), and full hashing 160 MB per launch is wasted I/O.
  static Future<bool> isInstalled(StemModelConfig config) async {
    final dir = await modelsDir();
    for (final a in config.assets) {
      final f = File('${dir.path}/${a.fileName}');
      if (!f.existsSync()) return false;
      if (await f.length() != a.sizeBytes) return false;
    }
    return true;
  }

  /// Total bytes the user still needs to download for this variant.
  /// (Subtracts any asset that's already on disk + correct-sized — lets
  /// a partial install resume without re-pulling the small graph.)
  static Future<int> remainingBytes(StemModelConfig config) async {
    final dir = await modelsDir();
    var rem = 0;
    for (final a in config.assets) {
      final f = File('${dir.path}/${a.fileName}');
      if (f.existsSync() && await f.length() == a.sizeBytes) continue;
      rem += a.sizeBytes;
    }
    return rem;
  }

  /// Pull every missing asset for [config]. Throws on network / size /
  /// hash failure (after cleaning up the .tmp), completes normally on
  /// success. Caller should listen to [progressStream] for ticks.
  Future<void> install() async {
    final dir = await modelsDir();

    // Skip assets already present + correct-sized so a mid-install retry
    // (after a kill or a flaky leg) only re-pulls what's actually missing.
    final pending = <StemModelAsset>[];
    var alreadyOnDisk = 0;
    for (final a in config.assets) {
      final f = File('${dir.path}/${a.fileName}');
      if (f.existsSync() && await f.length() == a.sizeBytes) {
        alreadyOnDisk += a.sizeBytes;
      } else {
        pending.add(a);
      }
    }
    final totalBytes = config.totalBytes;

    var doneSoFar = alreadyOnDisk;
    for (var i = 0; i < pending.length; i++) {
      final asset = pending[i];
      // Index reported to UI is over the full asset list, not the pending
      // subset — "2/2" reads right when only the weights file is missing.
      final overallIndex = config.assets.indexOf(asset);
      await _downloadOne(
        asset,
        dir,
        baseDone: doneSoFar,
        total: totalBytes,
        assetIndex: overallIndex,
        assetCount: config.assets.length,
      );
      doneSoFar += asset.sizeBytes;
      _controller.add(ModelInstallProgress(
        bytesDone: doneSoFar,
        bytesTotal: totalBytes,
        assetIndex: overallIndex,
        assetCount: config.assets.length,
        assetName: asset.fileName,
        bytesPerSec: 0,
      ));
    }
  }

  Future<void> _downloadOne(
    StemModelAsset asset,
    Directory dir, {
    required int baseDone,
    required int total,
    required int assetIndex,
    required int assetCount,
  }) async {
    final finalFile = File('${dir.path}/${asset.fileName}');
    final tmp = File('${finalFile.path}.tmp');
    if (tmp.existsSync()) tmp.deleteSync();
    _activeTmp = tmp;

    final req = await _http.getUrl(Uri.parse(asset.url));
    if (_cancelled) {
      req.abort();
      throw const _InstallCancelled();
    }
    _activeRequest = req;
    req.followRedirects = true;
    req.maxRedirects = 5;
    req.headers.set(HttpHeaders.userAgentHeader, 'QuickPlayer-ModelInstaller');

    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw HttpException(
          'HTTP ${resp.statusCode} fetching ${asset.fileName}');
    }
    // GitHub Releases sends Content-Length on the final redirected leg;
    // we still trust the manifest size as the source of truth (used for
    // progress total + the post-download size check).

    final sink = tmp.openWrite();
    _activeSink = sink;
    var received = 0;
    var emaBps = 0.0;
    var lastTickMs = DateTime.now().millisecondsSinceEpoch;
    var lastTickBytes = 0;

    try {
      await for (final chunk in resp) {
        if (_cancelled) throw const _InstallCancelled();
        sink.add(chunk);
        received += chunk.length;

        // Throttle progress emissions to ~10 Hz — Flutter doesn't need a
        // tick per TCP packet and broadcasting on every chunk pegs the UI
        // thread on a fast LAN download.
        final now = DateTime.now().millisecondsSinceEpoch;
        final dt = now - lastTickMs;
        if (dt >= 100) {
          final inst = (received - lastTickBytes) * 1000.0 / dt;
          emaBps = emaBps == 0 ? inst : (emaBps * 0.7 + inst * 0.3);
          lastTickMs = now;
          lastTickBytes = received;
          _controller.add(ModelInstallProgress(
            bytesDone: baseDone + received,
            bytesTotal: total,
            assetIndex: assetIndex,
            assetCount: assetCount,
            assetName: asset.fileName,
            bytesPerSec: emaBps,
          ));
        }
      }
      await sink.flush();
      await sink.close();
      _activeSink = null;
    } catch (e) {
      try { await sink.close(); } catch (_) {}
      _activeSink = null;
      if (tmp.existsSync()) try { tmp.deleteSync(); } catch (_) {}
      rethrow;
    } finally {
      _activeRequest = null;
    }

    if (received != asset.sizeBytes) {
      if (tmp.existsSync()) try { tmp.deleteSync(); } catch (_) {}
      throw HttpException(
          'Size mismatch for ${asset.fileName}: '
          'got $received, expected ${asset.sizeBytes}');
    }

    if (asset.sha256 != null) {
      final ok = await _verifySha256(tmp, asset.sha256!);
      if (!ok) {
        if (tmp.existsSync()) try { tmp.deleteSync(); } catch (_) {}
        throw HttpException('SHA-256 mismatch for ${asset.fileName}');
      }
    }

    // Atomic-ish rename: replace any prior file in-place. Same-fs rename
    // on Android's app dir is atomic; if it's not, deleting first keeps
    // us from leaving a half-overwritten target.
    if (finalFile.existsSync()) finalFile.deleteSync();
    await tmp.rename(finalFile.path);
    _activeTmp = null;
  }

  /// Streaming SHA-256 so we don't load 160 MB into RAM to verify it.
  Future<bool> _verifySha256(File f, String expectedHex) async {
    final got = await sha256.bind(f.openRead()).first;
    return got.toString().toLowerCase() == expectedHex.toLowerCase();
  }

  /// Abort the in-flight download. Idempotent. Safe to call from a
  /// button handler in the UI.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    try { _activeRequest?.abort(); } catch (_) {}
    try { _activeSink?.close(); } catch (_) {}
    final tmp = _activeTmp;
    if (tmp != null && tmp.existsSync()) {
      try { tmp.deleteSync(); } catch (_) {}
    }
  }

  Future<void> dispose() async {
    cancel();
    _http.close(force: true);
    await _controller.close();
  }
}

class _InstallCancelled implements Exception {
  const _InstallCancelled();
  @override
  String toString() => 'Model install cancelled';
}

/// Public type — UI checks for this to render "Cancelled" instead of an
/// error message when the user pressed the cancel button.
bool wasInstallCancelled(Object e) => e is _InstallCancelled;
