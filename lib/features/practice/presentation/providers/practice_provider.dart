import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/storage/storage_service.dart';
import '../../data/models/practice_session.dart';

/// All Practice Mode state: a flat list of historical sessions, plus the
/// in-flight session that the player is currently accumulating into.
///
/// Sessions are persisted to Hive on close so a kill / crash still
/// preserves the time that was logged up to that point (we flush every
/// ~10s as an extra safety net).
class PracticeState {
  final List<PracticeSession> sessions;
  final PracticeSession? activeSession;

  const PracticeState({
    this.sessions = const [],
    this.activeSession,
  });

  PracticeState copyWith({
    List<PracticeSession>? sessions,
    PracticeSession? activeSession,
    bool clearActive = false,
  }) {
    return PracticeState(
      sessions: sessions ?? this.sessions,
      activeSession: clearActive ? null : (activeSession ?? this.activeSession),
    );
  }
}

final practiceProvider =
    StateNotifierProvider<PracticeNotifier, PracticeState>((ref) {
  return PracticeNotifier();
});

class PracticeNotifier extends StateNotifier<PracticeState> {
  PracticeNotifier() : super(const PracticeState()) {
    _load();
  }

  final _storage = StorageService();
  final _uuid = const Uuid();

  /// Wall-clock anchor of the active session: when we last incremented
  /// durationMs. Each tick / pause computes (now - anchor) and folds it
  /// in, so suspending while in the background doesn't lose the seconds.
  int? _activeAnchorMs;

  Future<void> _load() async {
    await _storage.init();
    state = state.copyWith(sessions: _storage.getAllPracticeSessions());
  }

  // ---- Recorder hooks -------------------------------------------------

  /// Called by the player when playback starts (initial play or resume
  /// after pause / track switch). If no session is currently open for
  /// this track, opens one.
  void onPlayStarted(String trackId, {String? trackName}) {
    final active = state.activeSession;
    if (active != null && active.trackId == trackId) {
      // Already in a session for this track. Just rebase the anchor so
      // we don't double-count the paused interval.
      _activeAnchorMs = DateTime.now().millisecondsSinceEpoch;
      return;
    }
    // Flush any other open session first.
    if (active != null) _flush();

    final now = DateTime.now().toUtc();
    final session = PracticeSession(
      id: _uuid.v4(),
      trackId: trackId,
      startedAtMs: now.millisecondsSinceEpoch,
      durationMs: 0,
      trackName: trackName,
    );
    _activeAnchorMs = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(activeSession: session);
  }

  /// Called when playback pauses, stops, or the track changes. Updates
  /// the active session's duration and persists it to Hive.
  Future<void> onPlayEnded() async {
    await _flush();
  }

  /// Persist the active session and clear it.
  Future<void> _flush() async {
    final active = state.activeSession;
    if (active == null) return;
    _accumulate();
    if (active.durationMs > 0) {
      await _storage.savePracticeSession(active);
    }
    // Reload sessions list from storage to include the new entry.
    final all = _storage.getAllPracticeSessions();
    state = state.copyWith(sessions: all, clearActive: true);
    _activeAnchorMs = null;
  }

  /// Periodic checkpoint -- the player calls this every few seconds so
  /// data is durable even if the process dies. Doesn't end the session,
  /// just folds elapsed time in and rewrites the Hive record.
  Future<void> checkpoint() async {
    final active = state.activeSession;
    if (active == null) return;
    _accumulate();
    await _storage.savePracticeSession(active);
  }

  void _accumulate() {
    final active = state.activeSession;
    final anchor = _activeAnchorMs;
    if (active == null || anchor == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final delta = now - anchor;
    if (delta <= 0) return;
    active.durationMs += delta;
    _activeAnchorMs = now;
  }

  // ---- Derived stats --------------------------------------------------

  /// Public view of all sessions including the in-flight one, so the
  /// Practice tab can render an aggregated "recent" list whose newest
  /// row ticks up live while a track is playing.
  List<PracticeSession> allSessions() => _allSessions();

  /// All sessions plus the in-flight one (with current accumulated
  /// duration), so the UI shows today's running total live.
  List<PracticeSession> _allSessions() {
    final active = state.activeSession;
    if (active == null) return state.sessions;
    // Don't mutate `active` here -- compute a snapshot.
    final anchor = _activeAnchorMs;
    final pendingMs = anchor == null
        ? 0
        : (DateTime.now().millisecondsSinceEpoch - anchor);
    final activeSnapshot = PracticeSession(
      id: active.id,
      trackId: active.trackId,
      startedAtMs: active.startedAtMs,
      durationMs: active.durationMs + (pendingMs > 0 ? pendingMs : 0),
      trackName: active.trackName,
    );
    return [activeSnapshot, ...state.sessions];
  }

  Duration totalToday() => _totalForDay(DateTime.now());

  Duration _totalForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    int ms = 0;
    for (final s in _allSessions()) {
      final local = s.startedAtLocal;
      if (local.isBefore(start) || !local.isBefore(end)) continue;
      ms += s.durationMs;
    }
    return Duration(milliseconds: ms);
  }

  /// Minutes-practised for the past `nDays` days (including today), in
  /// chronological order. Index 0 is the oldest day in the window.
  List<int> dailyMinutesWindow(int nDays) {
    final today = DateTime.now();
    final startDay = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: nDays - 1));
    return List.generate(nDays, (i) {
      final day = startDay.add(Duration(days: i));
      return _totalForDay(day).inMinutes;
    });
  }

  /// Number of consecutive days up to and including today that the user
  /// has practised at least one minute.
  int currentStreak() {
    var streak = 0;
    var day = DateTime.now();
    while (true) {
      if (_totalForDay(day).inMinutes < 1) break;
      streak += 1;
      day = day.subtract(const Duration(days: 1));
      if (streak > 365) break; // sanity cap
    }
    return streak;
  }

  /// Total practised minutes since the very first session.
  Duration totalEver() {
    int ms = 0;
    for (final s in _allSessions()) {
      ms += s.durationMs;
    }
    return Duration(milliseconds: ms);
  }
}
