/// Picks the htdemucs segment length / model variant by device RAM and
/// describes where each variant's binaries live on disk + on the model
/// CDN (GitHub Releases).
///
/// Activation memory scales superlinearly with segment length (the
/// transformer attention is O(T²)): ~1.4 GB at 2 s, ~2.4 GB at 3.9 s,
/// ~5 GB at 7.8 s. We pick the longest segment the device can hold so
/// quality scales with hardware without ever excluding a device — even
/// 4 GB phones get acceptable quality at 2 s. See
/// docs/STEM_ONNX_EXPORT_SPIKE.md.
library;

/// A single downloadable file for a model variant. Each variant ships
/// as a small graph (.onnx) + a large external-weights blob (.weights)
/// that ORT mmaps from the same directory.
class StemModelAsset {
  final String fileName;
  final String url;
  final int sizeBytes;
  // SHA-256 of the published asset. Optional: when null we skip
  // hash verification and rely on size + length-checked stream. Pin
  // these once the release artifacts are uploaded so a CDN swap or
  // truncated download can't corrupt the model silently.
  final String? sha256;

  const StemModelAsset({
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    this.sha256,
  });
}

class StemModelConfig {
  final double segmentSeconds;
  final String graphFile; // e.g. htdemucs_2s.onnx — what ORT opens
  final List<StemModelAsset> assets;

  const StemModelConfig({
    required this.segmentSeconds,
    required this.graphFile,
    required this.assets,
  });

  /// Total bytes the user has to download for this variant.
  int get totalBytes =>
      assets.fold(0, (sum, a) => sum + a.sizeBytes);

  static const _kReleaseTag = 'models-v2.1';
  static const _kBaseUrl =
      'https://github.com/innovai-studio/QuickPlayer/releases/download/$_kReleaseTag';

  // Sizes / hashes match stem_spike/models/dist/ as of 2026-05-28.
  // The 2 s and 3.9 s variants happen to share the same .weights bytes,
  // but they're hosted as distinct assets so ORT can mmap them by the
  // exact filename embedded in each .onnx graph.
  static const s2 = StemModelConfig(
    segmentSeconds: 2.0,
    graphFile: 'htdemucs_2s.onnx',
    assets: [
      StemModelAsset(
        fileName: 'htdemucs_2s.onnx',
        url: '$_kBaseUrl/htdemucs_2s.onnx',
        sizeBytes: 2072388,
        sha256:
            '78ce44c20697b34fc19fc7fce3aa6b08b4f37330f0b608c490ca28b141f7b86f',
      ),
      StemModelAsset(
        fileName: 'htdemucs_2s.weights',
        url: '$_kBaseUrl/htdemucs_2s.weights',
        sizeBytes: 167880704,
        sha256:
            'd7cf9e61a4f68a160e984d76cdf74224848cb5b3a8b02a68521f9df4545315c9',
      ),
    ],
  );

  static const s39 = StemModelConfig(
    segmentSeconds: 3.9,
    graphFile: 'htdemucs_3s9.onnx',
    assets: [
      StemModelAsset(
        fileName: 'htdemucs_3s9.onnx',
        url: '$_kBaseUrl/htdemucs_3s9.onnx',
        sizeBytes: 3447815,
        sha256:
            '8e2fd23ff62daba11e4430f4ba1bbf8f54d30a995920d543123594086d3de2c4',
      ),
      StemModelAsset(
        fileName: 'htdemucs_3s9.weights',
        url: '$_kBaseUrl/htdemucs_3s9.weights',
        sizeBytes: 167880704,
        sha256:
            'd7cf9e61a4f68a160e984d76cdf74224848cb5b3a8b02a68521f9df4545315c9',
      ),
    ],
  );

  static const s78 = StemModelConfig(
    segmentSeconds: 7.8,
    graphFile: 'htdemucs_7s8.onnx',
    assets: [
      StemModelAsset(
        fileName: 'htdemucs_7s8.onnx',
        url: '$_kBaseUrl/htdemucs_7s8.onnx',
        sizeBytes: 6408327,
        sha256:
            'cf7a57a791c467e2c838baed2a352716278793115f0dbef6e8567028e441dfae',
      ),
      StemModelAsset(
        fileName: 'htdemucs_7s8.weights',
        url: '$_kBaseUrl/htdemucs_7s8.weights',
        sizeBytes: 167880704,
        sha256:
            '1364558e42dd19130ae8c58da46a8ac08df2bb085b4d62e0b07d08adbacad2fd',
      ),
    ],
  );

  /// Conservative thresholds: leave headroom for Android + other apps.
  static StemModelConfig forRam(int totalRamMb) {
    if (totalRamMb >= 7500) return s78; // ~8 GB+ flagship
    if (totalRamMb >= 5500) return s39; // ~6 GB
    return s2; // 4 GB and below
  }

}
