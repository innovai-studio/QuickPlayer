import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/stem/stem_separator.dart';
import '../../../../l10n/app_localizations.dart';

/// Persistent, smoothly-updating progress dialog for an in-flight stem
/// separation. Shows: percent + live ETA derived from elapsed/progress,
/// and a per-stem checklist that ticks each stem as the encoding phase
/// finalises it (the pipeline emits progress 0.85→1.0 in four steps,
/// one per encoded stem).
class StemProgressDialog extends StatefulWidget {
  const StemProgressDialog({super.key});

  @override
  State<StemProgressDialog> createState() => _StemProgressDialogState();
}

class _StemProgressDialogState extends State<StemProgressDialog> {
  // Pipeline emits 0.85 + 0.15 * (s+1)/4 after each stem is AAC-encoded.
  static const _stemDoneAt = [0.8875, 0.925, 0.9625, 1.0];

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _eta; // forces a tick every second so ETA refreshes even between progress events
  double _progress = 0;
  bool _failed = false;
  String? _errorMsg;
  final _start = DateTime.now();

  @override
  void initState() {
    super.initState();
    _sub = StemSeparator.instance.progressStream.listen((e) {
      if (!mounted) return;
      switch (e['event']) {
        case 'progress':
          setState(() => _progress = (e['progress'] as num).toDouble());
        case 'done':
          setState(() => _progress = 1);
          Future.delayed(const Duration(milliseconds: 600), _close);
        case 'error':
          setState(() {
            _failed = true;
            _errorMsg = e['error']?.toString();
          });
      }
    });
    _eta = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _eta?.cancel();
    super.dispose();
  }

  String _etaText(AppLocalizations l) {
    if (_progress < 0.1) return l.stemEtaEstimating;
    if (_progress >= 1.0) return l.stemPhaseDone;
    final elapsed = DateTime.now().difference(_start).inSeconds;
    final remaining = (elapsed * (1 - _progress) / _progress).round();
    final m = remaining ~/ 60, s = remaining % 60;
    if (m == 0) return l.etaSecondsRemaining(s);
    if (m < 10) return l.etaMinutesSecondsRemaining(m, s);
    return l.etaMinutesRemaining(m);
  }

  String _phaseText(AppLocalizations l) {
    if (_failed) return l.stemFailedWithReason(_errorMsg ?? '');
    if (_progress < 0.05) return l.stemPhaseDecoding;
    if (_progress < 0.85) return l.stemPhaseSeparating;
    if (_progress < 1.0) {
      final encoded = _stemDoneAt.where((t) => _progress >= t).length;
      return l.stemPhaseEncoding(encoded + 1, 4);
    }
    return l.stemPhaseDone;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pct = (_progress * 100).round();
    return Dialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.graphic_eq, color: AppColors.primaryStart),
                const SizedBox(width: 10),
                Text(l.stemSeparatingTitle,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (!_failed)
                  Text('$pct%',
                      style: const TextStyle(
                          color: AppColors.primaryStart,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _failed ? null : _progress,
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(
                    _failed ? AppColors.error : AppColors.primaryStart),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(_phaseText(l),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ),
                if (!_failed && _progress < 1.0)
                  Text(_etaText(l),
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 14),
            ..._buildStemRows(l),
            if (_failed)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _close,
                  child: Text(l.commonClose),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStemRows(AppLocalizations l) {
    final names = [
      l.stemNameDrums,
      l.stemNameBass,
      l.stemNameOther,
      l.stemNameVocals,
    ];
    return List.generate(4, (i) {
      final done = _progress >= _stemDoneAt[i];
      final active =
          !done && _progress >= 0.85 && _progress < _stemDoneAt[i] &&
              (i == 0 || _progress >= _stemDoneAt[i - 1]);
      final color = done
          ? AppColors.success
          : active
              ? AppColors.primaryStart
              : AppColors.textSecondary.withValues(alpha: 0.6);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: done
                  ? const Icon(Icons.check_circle, color: AppColors.success, size: 18)
                  : active
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primaryStart),
                        )
                      : Icon(Icons.radio_button_unchecked,
                          color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Text(names[i],
                style: TextStyle(
                    color: done ? AppColors.textPrimary : color,
                    fontSize: 13,
                    fontWeight:
                        done ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      );
    });
  }
}
