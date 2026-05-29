import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/model_installer.dart';
import '../../data/stem_model_config.dart';

/// Two-phase dialog: a confirmation card (size + "100% on-device" sell),
/// followed by the streaming progress UI for the download itself. Visual
/// language mirrors StemProgressDialog so the user perceives them as one
/// continuous flow (download → separate).
///
/// Caller awaits [showStemModelDownloadDialog]:
/// * true   → install succeeded, files on disk and ready for ORT;
/// * false  → user cancelled before / during download, or hit Cancel on
///            the error screen. Caller should NOT proceed to separation.
Future<bool> showStemModelDownloadDialog(
  BuildContext context, {
  required StemModelConfig config,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StemModelDownloadDialog(config: config),
  );
  return result ?? false;
}

class _StemModelDownloadDialog extends StatefulWidget {
  const _StemModelDownloadDialog({required this.config});
  final StemModelConfig config;

  @override
  State<_StemModelDownloadDialog> createState() =>
      _StemModelDownloadDialogState();
}

enum _Phase { confirm, downloading, failed }

class _StemModelDownloadDialogState extends State<_StemModelDownloadDialog> {
  _Phase _phase = _Phase.confirm;

  ModelInstaller? _installer;
  StreamSubscription<ModelInstallProgress>? _sub;
  ModelInstallProgress? _last;
  String? _errorMsg;
  int _remainingBytes = 0;

  @override
  void initState() {
    super.initState();
    // The confirm card shows "Download X MB" — subtract any asset that's
    // already on disk so a half-complete retry advertises the right
    // number (eg. graph already pulled, weights to go).
    () async {
      final rem = await ModelInstaller.remainingBytes(widget.config);
      if (mounted) setState(() => _remainingBytes = rem);
    }();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _installer?.dispose();
    super.dispose();
  }

  // ----- Flow control --------------------------------------------------

  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _errorMsg = null;
      _last = null;
    });
    final installer = ModelInstaller(widget.config);
    _installer = installer;
    _sub = installer.progressStream.listen((p) {
      if (mounted) setState(() => _last = p);
    });
    try {
      await installer.install();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      if (wasInstallCancelled(e)) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _errorMsg = e.toString();
      });
    } finally {
      await _sub?.cancel();
      _sub = null;
    }
  }

  void _cancel() {
    _installer?.cancel();
    Navigator.of(context).pop(false);
  }

  void _retry() {
    _sub?.cancel();
    _installer?.dispose();
    _installer = null;
    _startDownload();
  }

  // ----- Build ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: switch (_phase) {
          _Phase.confirm => _buildConfirm(context),
          _Phase.downloading => _buildProgress(context),
          _Phase.failed => _buildFailed(context),
        },
      ),
    );
  }

  Widget _buildConfirm(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mb = (_remainingBytes / (1024 * 1024)).toStringAsFixed(0);
    final seg = widget.config.segmentSeconds;
    final segLabel = seg == seg.truncateToDouble()
        ? seg.toStringAsFixed(0)
        : seg.toStringAsFixed(1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_download, color: AppColors.primaryStart),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.stemModelDownloadTitle,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$mb MB',
              style: const TextStyle(
                color: AppColors.primaryStart,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Bullet(
          icon: Icons.smartphone,
          text: l.stemModelBenefitOnDevice,
        ),
        const SizedBox(height: 6),
        _Bullet(
          icon: Icons.all_inclusive,
          text: l.stemModelBenefitNoLengthCap,
        ),
        const SizedBox(height: 6),
        _Bullet(
          icon: Icons.download_done,
          text: l.stemModelBenefitOnceOnly,
        ),
        const SizedBox(height: 14),
        Text(
          l.stemModelVariantNotice(segLabel),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.commonCancel,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 4),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryStart,
                foregroundColor: Colors.white,
              ),
              onPressed: _startDownload,
              child: Text(l.commonDownload),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final l = AppLocalizations.of(context);
    final p = _last;
    final fraction = p?.fraction ?? 0;
    final pct = (fraction * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_download, color: AppColors.primaryStart),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.stemModelDownloadingTitle,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$pct%',
              style: const TextStyle(
                color: AppColors.primaryStart,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction == 0 ? null : fraction,
            minHeight: 8,
            backgroundColor: AppColors.border,
            valueColor:
                const AlwaysStoppedAnimation(AppColors.primaryStart),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _phaseText(context, p),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              _rateText(p),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _bytesText(context, p),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
            Text(
              _etaText(context, p),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _cancel,
              child: Text(l.commonCancel,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFailed(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l.stemModelDownloadFailed,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _errorMsg ?? 'unknown error',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.commonClose,
                  style: const TextStyle(color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 4),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryStart,
                foregroundColor: Colors.white,
              ),
              onPressed: _retry,
              child: Text(l.commonRetry),
            ),
          ],
        ),
      ],
    );
  }

  // ----- Text helpers --------------------------------------------------

  String _phaseText(BuildContext context, ModelInstallProgress? p) {
    final l = AppLocalizations.of(context);
    if (p == null) return l.stemModelConnecting;
    final ext = p.assetName.split('.').last;
    return ext == 'onnx'
        ? l.stemModelPhaseGraph(p.assetIndex + 1, p.assetCount)
        : l.stemModelPhaseWeights(p.assetIndex + 1, p.assetCount);
  }

  String _rateText(ModelInstallProgress? p) {
    if (p == null || p.bytesPerSec <= 0) return '';
    final mbps = p.bytesPerSec / (1024 * 1024);
    if (mbps >= 1) return '${mbps.toStringAsFixed(1)} MB/s';
    final kbps = p.bytesPerSec / 1024;
    return '${kbps.toStringAsFixed(0)} KB/s';
  }

  String _bytesText(BuildContext context, ModelInstallProgress? p) {
    if (p == null) return '';
    final l = AppLocalizations.of(context);
    final dn = (p.bytesDone / (1024 * 1024)).toStringAsFixed(1);
    final tot = (p.bytesTotal / (1024 * 1024)).toStringAsFixed(0);
    return l.bytesProgress(dn, tot);
  }

  String _etaText(BuildContext context, ModelInstallProgress? p) {
    if (p == null || p.bytesPerSec <= 0 || p.fraction <= 0.01) return '';
    final l = AppLocalizations.of(context);
    final remaining = p.bytesTotal - p.bytesDone;
    final secs = (remaining / p.bytesPerSec).round();
    final m = secs ~/ 60, s = secs % 60;
    if (m == 0) return l.etaSecondsRemaining(s);
    if (m < 10) return l.etaMinutesSecondsRemaining(m, s);
    return l.etaMinutesRemaining(m);
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
