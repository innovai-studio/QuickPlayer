import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../library/data/models/track.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../data/models/practice_session.dart';
import '../providers/practice_provider.dart';

/// Practice Mode dashboard: today's total, current streak, a 7-day bar
/// chart and the most recent sessions. Refreshes every second while
/// playback is active so the user can watch today's minutes tick up live.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  Timer? _tick;

  /// How many aggregated rows the "Recent sessions" list shows. Starts
  /// at 10 and grows by 10 on every Load more tap, capped at 100. Reset
  /// whenever the user leaves and re-enters the tab.
  static const _pageSize = 10;
  static const _displayCap = 100;
  int _displayCount = _pageSize;

  @override
  void initState() {
    super.initState();
    // Watching practiceProvider doesn't repaint on every accumulated
    // millisecond -- the in-flight session only mutates `durationMs` in
    // place, and `_activeAnchorMs` is private. Force a rebuild once a
    // second so "today" / streak / chart stay live during a session.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Read (not watch) -- we trigger our own rebuilds via the 1 s ticker
    // and via the library provider below. Watching would double-rebuild
    // when sessions list mutates, which is fine but pointless.
    final practice = ref.watch(practiceProvider.notifier);
    final tracksById = {
      for (final t in ref.watch(libraryProvider).tracks) t.id: t,
    };

    final todayMins = practice.totalToday().inMinutes;
    final todaySecs = practice.totalToday().inSeconds % 60;
    final streak = practice.currentStreak();
    final totalEverHours = practice.totalEver().inHours;
    final totalEverMins = practice.totalEver().inMinutes % 60;
    final week = practice.dailyMinutesWindow(7);

    // Watch to trigger rebuilds on save, but actual rows are built from
    // the merged-with-active list below (so the topmost row ticks live).
    ref.watch(practiceProvider);
    final groups = _aggregate(practice.allSessions());
    final canLoadMore =
        _displayCount < groups.length && _displayCount < _displayCap;
    final shown = groups.take(_displayCount).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _HeroToday(minutes: todayMins, seconds: todaySecs),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.local_fire_department,
                iconColor: AppColors.warning,
                label: 'Streak',
                value: streak == 0 ? '0' : '$streak',
                suffix: streak == 1 ? 'day' : 'days',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                icon: Icons.schedule,
                iconColor: AppColors.primaryStart,
                label: 'Total',
                value: totalEverHours > 0
                    ? '${totalEverHours}h ${totalEverMins}m'
                    : '${totalEverMins}m',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _WeekChart(minutesByDay: week),
        const SizedBox(height: 24),
        const _SectionHeader('Recent sessions'),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          _EmptyState()
        else ...[
          ...shown.map(
            (g) => _GroupTile(
              group: g,
              track: tracksById[g.trackId],
            ),
          ),
          if (canLoadMore)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _displayCount = (_displayCount + _pageSize)
                        .clamp(_pageSize, _displayCap);
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryStart,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                  ),
                  child: const Text(
                    'Load more',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            )
          else if (groups.length > _displayCap)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(
                child: Text(
                  'Showing latest 100 entries',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// Bucket a flat session list into (trackId, local-calendar-day) groups.
  /// Each group totals duration and remembers the most recent
  /// `startedAtMs` for sort order + the count of underlying sessions
  /// (so the UI can show e.g. "3 sessions today" when relevant).
  List<_SessionGroup> _aggregate(List<PracticeSession> sessions) {
    final map = <String, _SessionGroup>{};
    for (final s in sessions) {
      final d = s.startedAtLocal;
      final dayKey = '${d.year}-${d.month}-${d.day}';
      final key = '${s.trackId}|$dayKey';
      final existing = map[key];
      if (existing == null) {
        map[key] = _SessionGroup(
          trackId: s.trackId,
          trackName: s.trackName,
          dayKey: dayKey,
          totalMs: s.durationMs,
          latestStartedMs: s.startedAtMs,
          sessionCount: 1,
        );
      } else {
        existing.totalMs += s.durationMs;
        existing.sessionCount += 1;
        if (s.startedAtMs > existing.latestStartedMs) {
          existing.latestStartedMs = s.startedAtMs;
          // Prefer the most recent non-null name in case earlier
          // sessions for this track didn't capture it.
          if (s.trackName != null) existing.trackName = s.trackName;
        }
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.latestStartedMs.compareTo(a.latestStartedMs));
    return list;
  }
}

/// Aggregated view of all sessions for one (track, calendar-day).
class _SessionGroup {
  final String trackId;
  String? trackName;
  final String dayKey;
  int totalMs;
  int latestStartedMs;
  int sessionCount;

  _SessionGroup({
    required this.trackId,
    required this.trackName,
    required this.dayKey,
    required this.totalMs,
    required this.latestStartedMs,
    required this.sessionCount,
  });
}

class _HeroToday extends StatelessWidget {
  final int minutes;
  final int seconds;

  const _HeroToday({required this.minutes, required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's practice",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$minutes',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'min',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${seconds.toString().padLeft(2, '0')} s',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? suffix;

  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 4),
                Text(
                  suffix!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  /// Chronological, length 7 (index 0 = 6 days ago, index 6 = today).
  final List<int> minutesByDay;

  const _WeekChart({required this.minutesByDay});

  @override
  Widget build(BuildContext context) {
    final maxMins = minutesByDay.fold<int>(0, (m, v) => v > m ? v : m);
    // Use at least 10 min as the visual ceiling so a tiny session doesn't
    // render the bar at full height -- gives users something to grow into.
    final ceiling = maxMins < 10 ? 10 : maxMins;

    // Day-of-week labels relative to today. weekday: 1=Mon..7=Sun.
    final today = DateTime.now();
    final labels = List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return _shortDay(d.weekday);
    });

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Last 7 days',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final mins = minutesByDay[i];
                final ratio = mins / ceiling;
                final isToday = i == 6;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (mins > 0)
                          Text(
                            '$mins',
                            style: TextStyle(
                              color: isToday
                                  ? AppColors.primaryStart
                                  : AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        else
                          const SizedBox(height: 12),
                        const SizedBox(height: 2),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            height: (ratio * 70).clamp(2.0, 70.0),
                            decoration: BoxDecoration(
                              gradient: mins > 0
                                  ? AppColors.primaryGradient
                                  : null,
                              color: mins > 0 ? null : AppColors.border,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(7, (i) {
              final isToday = i == 6;
              return Expanded(
                child: Center(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: isToday
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  static String _shortDay(int weekday) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return days[(weekday - 1) % 7];
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final _SessionGroup group;
  final Track? track;

  const _GroupTile({required this.group, required this.track});

  @override
  Widget build(BuildContext context) {
    final mins = group.totalMs ~/ 60000;
    final secs = (group.totalMs % 60000) ~/ 1000;
    final durationLabel = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    final title = group.trackName ?? track?.name ?? 'Unknown track';
    final latest =
        DateTime.fromMillisecondsSinceEpoch(group.latestStartedMs, isUtc: true)
            .toLocal();
    final subtitle = group.sessionCount > 1
        ? '${_humanDay(latest)} · ${group.sessionCount} sessions'
        : _humanWhen(latest);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.music_note,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            durationLabel,
            style: const TextStyle(
              color: AppColors.primaryStart,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _humanDay(DateTime when) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    if (!when.isBefore(startOfToday)) return 'Today';
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
    if (!when.isBefore(startOfYesterday)) return 'Yesterday';
    final diff = startOfToday
        .difference(DateTime(when.year, when.month, when.day))
        .inDays;
    if (diff < 7) return '${diff}d ago';
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
  }

  static String _humanWhen(DateTime when) {
    final day = _humanDay(when);
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    // Older dates already include "YYYY-MM-DD" -- don't tack on time.
    if (day.contains('-')) return day;
    return '$day $hh:$mm';
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.headphones, color: AppColors.textSecondary, size: 32),
          SizedBox(height: 12),
          Text(
            'No sessions yet',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Press play on any track to start logging practice.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
