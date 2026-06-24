class ABLoop {
  final String trackId;
  final Duration? pointA;
  final Duration? pointB;
  final bool isActive;

  const ABLoop({
    required this.trackId,
    this.pointA,
    this.pointB,
    this.isActive = false,
  });

  bool get isComplete => pointA != null && pointB != null;
  bool get hasPointA => pointA != null;
  bool get hasPointB => pointB != null;

  ABLoop copyWith({
    String? trackId,
    Duration? pointA,
    Duration? pointB,
    bool? isActive,
    bool clearPointA = false,
    bool clearPointB = false,
  }) {
    return ABLoop(
      trackId: trackId ?? this.trackId,
      pointA: clearPointA ? null : (pointA ?? this.pointA),
      pointB: clearPointB ? null : (pointB ?? this.pointB),
      isActive: isActive ?? this.isActive,
    );
  }

  ABLoop clear() {
    return ABLoop(trackId: trackId);
  }

  @override
  String toString() => 'ABLoop(A: $pointA, B: $pointB, active: $isActive)';
}
