/// Playback mode for queue management
enum PlayMode {
  /// Play all tracks in order, stop at end
  sequential,

  /// Repeat the entire queue indefinitely
  loopAll,

  /// Repeat the current track
  loopOne,

  /// Shuffle the queue order
  shuffle,
}
