import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/stem/stem_separator.dart';

/// Persistent, smoothly-updating progress dialog for an in-flight stem
/// separation. Subscribes to [StemSeparator.progressStream] and stays on
/// screen continuously (no flicker), filling a single progress bar until
/// the service reports done/error, then dismisses itself.
class StemProgressDialog extends StatefulWidget {
  const StemProgressDialog({super.key});

  @override
  State<StemProgressDialog> createState() => _StemProgressDialogState();
}

class _StemProgressDialogState extends State<StemProgressDialog> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  double _progress = 0;
  String _status = 'Starting…';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _sub = StemSeparator.instance.progressStream.listen((e) {
      if (!mounted) return;
      switch (e['event']) {
        case 'progress':
          setState(() {
            _progress = (e['progress'] as num).toDouble();
            _status = 'Separating stems…';
          });
        case 'done':
          setState(() {
            _progress = 1;
            _status = 'Done';
          });
          Future.delayed(const Duration(milliseconds: 500), _close);
        case 'error':
          setState(() {
            _failed = true;
            _status = 'Failed: ${e['error']}';
          });
      }
    });
  }

  void _close() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                const Text('Separating stems',
                    style: TextStyle(
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 12),
            Text(_status,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            if (_failed)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _close,
                  child: const Text('Close'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
