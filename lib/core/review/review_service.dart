import 'package:in_app_review/in_app_review.dart';
import '../storage/storage_service.dart';

/// Asks for a Play Store rating via the In-App Review API at a positive
/// moment, exactly once.
///
/// Google's In-App Review flow is quota-controlled (calling it does not
/// guarantee the dialog shows) and must NOT be wired to a "rate us"
/// button -- so we trigger it from a milestone the user reaches while
/// actively getting value: a 3-day practice streak OR 5 logged
/// sessions, whichever lands first. A Hive flag makes it fire only once
/// per install; we never re-ask and never offer an incentive (both are
/// policy requirements).
class ReviewService {
  ReviewService._();
  static final ReviewService instance = ReviewService._();

  static const _askedKey = 'review_prompt_shown';
  static const _streakThreshold = 3;
  static const _sessionThreshold = 5;

  final _storage = StorageService();
  final _inAppReview = InAppReview.instance;

  /// In-memory latch so the Practice tab's per-second rebuild can't fire
  /// multiple requests before the persisted flag is written.
  bool _attemptedThisSession = false;

  /// Call from the Practice tab once stats are known. No-ops unless a
  /// milestone is freshly reached and we haven't asked before.
  Future<void> maybePrompt({
    required int currentStreak,
    required int totalSessions,
  }) async {
    if (_attemptedThisSession) return;
    if (_storage.getSetting<bool>(_askedKey) == true) return;
    final milestoneReached = currentStreak >= _streakThreshold ||
        totalSessions >= _sessionThreshold;
    if (!milestoneReached) return;

    _attemptedThisSession = true;
    // Persist first: even if the OS suppresses the dialog (quota), we've
    // "spent" our one ask and won't nag on every future milestone.
    await _storage.setSetting(_askedKey, true);

    if (await _inAppReview.isAvailable()) {
      await _inAppReview.requestReview();
    }
  }
}
