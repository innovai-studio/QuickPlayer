/// Picks the htdemucs segment length / model variant by device RAM.
///
/// Activation memory scales superlinearly with segment length (the
/// transformer attention is O(T²)): ~1.4 GB at 2 s, ~2.4 GB at 3.9 s,
/// ~5 GB at 7.8 s. We pick the longest segment the device can hold so
/// quality scales with hardware without ever excluding a device — even
/// 4 GB phones get acceptable quality at 2 s. See
/// docs/STEM_ONNX_EXPORT_SPIKE.md.
class StemModelConfig {
  final double segmentSeconds;
  final String fileName; // model file (external-data .onnx) under the models dir

  const StemModelConfig(this.segmentSeconds, this.fileName);

  static const s2 = StemModelConfig(2.0, 'htdemucs_2s.onnx');
  static const s39 = StemModelConfig(3.9, 'htdemucs_3s9.onnx');
  static const s78 = StemModelConfig(7.8, 'htdemucs_7s8.onnx');

  /// Conservative thresholds: leave headroom for Android + other apps.
  static StemModelConfig forRam(int totalRamMb) {
    if (totalRamMb >= 7500) return s78; // ~8 GB+ flagship
    if (totalRamMb >= 5500) return s39; // ~6 GB
    return s2; // 4 GB and below
  }
}
