import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/stem/stem_mixer.dart';
import '../../../../shared/extensions/duration_extension.dart';
import '../../../library/data/models/track.dart';
import '../../data/models/stem_set.dart';

/// 4-stem practice mixer: plays the separated drums/bass/other/vocals in
/// sync with per-stem mute / solo / volume. Backed by the native 4×
/// ExoPlayer mixer (StemMixerHandler.kt) — just_audio can't be used here
/// because just_audio_background allows only one instance app-wide.
class StemMixerScreen extends StatefulWidget {
  final Track track;
  final StemSet stems;
  const StemMixerScreen({super.key, required this.track, required this.stems});

  @override
  State<StemMixerScreen> createState() => _StemMixerScreenState();
}

class _StemMixerScreenState extends State<StemMixerScreen> {
  static const _names = ['Drums', 'Bass', 'Other', 'Vocals'];
  static const _icons = [Icons.album, Icons.music_note, Icons.piano, Icons.mic];

  final _mixer = StemMixer.instance;
  final _volume = List<double>.filled(4, 1.0);
  final _muted = List<bool>.filled(4, false);
  final _soloed = List<bool>.filled(4, false);

  StreamSubscription<MixerState>? _sub;
  bool _ready = false;
  bool _playing = false;
  bool _seeking = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sub = _mixer.stateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        if (!_ready && s.ready) _ready = true;
        _playing = s.playing;
        if (s.duration > Duration.zero) _duration = s.duration;
        _buffered = s.buffered;
        if (!_seeking) _position = s.position;
      });
    });
    _mixer.prepare(widget.stems.paths).then((_) => _applyGains());
  }

  void _applyGains() {
    final anySolo = _soloed.any((s) => s);
    for (var i = 0; i < 4; i++) {
      final audible = anySolo ? _soloed[i] : !_muted[i];
      _mixer.setVolume(i, audible ? _volume[i] : 0.0);
    }
  }

  void _togglePlay() {
    if (_playing) {
      _mixer.pause();
    } else {
      _mixer.play();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mixer.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anySolo = _soloed.any((s) => s);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(widget.track.name,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 18),
            overflow: TextOverflow.ellipsis),
        centerTitle: true,
      ),
      body: !_ready
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryStart))
          : Column(
              children: [
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: 4,
                    itemBuilder: (_, i) => _stemRow(i, anySolo),
                  ),
                ),
                _transport(),
              ],
            ),
    );
  }

  Widget _stemRow(int i, bool anySolo) {
    final dimmed = anySolo ? !_soloed[i] : _muted[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Opacity(
        opacity: dimmed ? 0.45 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icons[i], color: AppColors.primaryStart, size: 20),
                const SizedBox(width: 8),
                Text(_names[i],
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                _toggle('M', _muted[i], AppColors.warning, () {
                  setState(() => _muted[i] = !_muted[i]);
                  _applyGains();
                }),
                const SizedBox(width: 8),
                _toggle('S', _soloed[i], AppColors.success, () {
                  setState(() => _soloed[i] = !_soloed[i]);
                  _applyGains();
                }),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.volume_up,
                    color: AppColors.textSecondary, size: 18),
                Expanded(
                  child: Slider(
                    value: _volume[i],
                    onChanged: (v) {
                      setState(() => _volume[i] = v);
                      _applyGains();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String label, bool on, Color onColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: on ? onColor : AppColors.border,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: on ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _transport() {
    final durMs =
        _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          // Thin buffer indicator: how far all 4 stems are buffered.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (_buffered.inMilliseconds / durMs).clamp(0.0, 1.0),
                minHeight: 2,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(
                    AppColors.primaryStart.withValues(alpha: 0.4)),
              ),
            ),
          ),
          Row(
            children: [
              Text(_position.toDisplayString(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _position.inMilliseconds.clamp(0, durMs).toDouble(),
                  max: durMs.toDouble(),
                  onChangeStart: (_) => _seeking = true,
                  onChanged: (v) => setState(
                      () => _position = Duration(milliseconds: v.round())),
                  onChangeEnd: (v) {
                    _mixer.seek(Duration(milliseconds: v.round()));
                    _seeking = false;
                  },
                ),
              ),
              Text(_duration.toDisplayString(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: Icon(_playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 34),
            ),
          ),
        ],
      ),
    );
  }
}
