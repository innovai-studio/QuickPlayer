import '../../data/models/playlist.dart';

class PlaylistsState {
  final List<Playlist> playlists;
  final bool isLoading;
  final String? error;

  const PlaylistsState({
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  PlaylistsState copyWith({
    List<Playlist>? playlists,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return PlaylistsState(
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
