import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/extensions/duration_extension.dart';
import '../../../library/data/models/track.dart';
import '../../data/models/stem_set.dart';

/// 4-stem practice mixer: play the separated drums/bass/other/vocals in
/// sync with per-stem mute / solo / volume. Uses four just_audio players
/// started together; a light periodic resync keeps them aligned (the
/// stems are sample-aligned slices of the same song, so they only drift
/// from independent clocks).
class StemMixerScreen extends StatefulWidget {
  final Track track;
  final StemSet stems;
  const StemMixerScreen({super.key, required this.track, required this.stems});

  @override
  State<StemMixerScreen> createState() => _StemMixerScreenState();
}

class _StemMixerScreenState extends State<StemMixerScreen> {
  static const _names = ['Drums', 'Bass', 'Other', 'Vocals'];
  static const _icons = [
    Icons.album,
    Icons.music_note,
    Icons.piano,
    Icons.mic,
  ];

  late final List<AudioPlayer> _players;
  final _volume = List<double>.filled(4, 1.0);
  final _muted = List<bool>.filled(4, false);
  final _soloed = List<bool>.filled(4, false);

  bool _ready = false;
  String? _initError;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _resync;
  StreamSubscription<Duration>? _posSub;

  @override
  void initState() {
    super.initState();
    _players = List.generate(4, (_) => AudioPlayer());
    _init();
  }

  Future<void> _init() async {
    try {
      final paths = widget.stems.paths;
      Duration? dur;
      for (var i = 0; i < 4; i++) {
        // just_audio_background is global in this app and requires a
        // MediaItem tag on every source, so set one per stem.
        dur = await _players[i].setAudioSource(AudioSource.uri(
          Uri.file(paths[i]),
          tag: MediaItem(
            id: '${widget.track.id}_${_names[i]}',
            title: '${widget.track.name} — ${_names[i]}',
          ),
        ));
      }
      await _finishInit(dur);
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  Future<void> _finishInit(Duration? dur) async {
    // Drive position/duration off the drums player (index 0) as leader.
    _duration = dur ?? Duration.zero;
    _posSub = _players[0].positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    // Resync followers to the leader if they drift more than ~50 ms.
    _resync = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!_playing) return;
      final lead = _players[0].position;
      for (var i = 1; i < 4; i++) {
        if ((_players[i].position - lead).inMilliseconds.abs() > 50) {
          await _players[i].seek(lead);
        }
      }
    });
    _applyGains();
    if (mounted) setState(() => _ready = true);
  }

  void _applyGains() {
    final anySolo = _soloed.any((s) => s);
    for (var i = 0; i < 4; i++) {
      final audible = anySolo ? _soloed[i] : !_muted[i];
      _players[i].setVolume(audible ? _volume[i] : 0.0);
    }
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      for (final p in _players) {
        p.pause();
      }
    } else {
      // Start all together for tight alignment.
      await Future.wait(_players.map((p) => p.play()));
    }
    setState(() => _playing = !_playing);
  }

  Future<void> _seek(Duration to) async {
    for (final p in _players) {
      await p.seek(to);
    }
    setState(() => _position = to);
  }

  @override
  void dispose() {
    _resync?.cancel();
    _posSub?.cancel();
    for (final p in _players) {
      p.dispose();
    }
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
      body: _initError != null
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('Mixer unavailable:\n$_initError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.error)),
              ),
            )
          : !_ready
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
    final dur = _duration.inMilliseconds == 0 ? const Duration(seconds: 1) : _duration;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        children: [
          Row(
            children: [
              Text(_position.toDisplayString(),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: _position.inMilliseconds
                      .clamp(0, dur.inMilliseconds)
                      .toDouble(),
                  max: dur.inMilliseconds.toDouble(),
                  onChanged: (v) =>
                      _seek(Duration(milliseconds: v.round())),
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
