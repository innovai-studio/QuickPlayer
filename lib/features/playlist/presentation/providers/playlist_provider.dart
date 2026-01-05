import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/storage/storage_service.dart';
import '../../../library/data/models/track.dart';
import '../../data/models/playlist.dart';
import 'playlist_state.dart';

final playlistsProvider =
    StateNotifierProvider<PlaylistsNotifier, PlaylistsState>((ref) {
  return PlaylistsNotifier();
});

class PlaylistsNotifier extends StateNotifier<PlaylistsState> {
  final StorageService _storage = StorageService();
  final _uuid = const Uuid();

  PlaylistsNotifier() : super(const PlaylistsState());

  /// Load all playlists from storage
  Future<void> loadPlaylists() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await _storage.init();
      final playlists = _storage.getAllPlaylists();
      state = state.copyWith(playlists: playlists, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load playlists: $e',
      );
    }
  }

  /// Create a new playlist
  Future<Playlist?> createPlaylist(String name) async {
    try {
      final playlist = Playlist(
        id: _uuid.v4(),
        name: name.trim(),
        trackIds: [],
        createdAt: DateTime.now(),
      );

      await _storage.savePlaylist(playlist);
      state = state.copyWith(playlists: [playlist, ...state.playlists]);
      return playlist;
    } catch (e) {
      state = state.copyWith(error: 'Failed to create playlist: $e');
      return null;
    }
  }

  /// Rename a playlist
  Future<void> renamePlaylist(String playlistId, String newName) async {
    try {
      final index = state.playlists.indexWhere((p) => p.id == playlistId);
      if (index < 0) return;

      final updated = state.playlists[index].copyWith(
        name: newName.trim(),
        updatedAt: DateTime.now(),
      );

      await _storage.savePlaylist(updated);

      final updatedList = List<Playlist>.from(state.playlists);
      updatedList[index] = updated;
      state = state.copyWith(playlists: updatedList);
    } catch (e) {
      state = state.copyWith(error: 'Failed to rename playlist: $e');
    }
  }

  /// Delete a playlist
  Future<void> deletePlaylist(String playlistId) async {
    try {
      await _storage.deletePlaylist(playlistId);
      final updatedList =
          state.playlists.where((p) => p.id != playlistId).toList();
      state = state.copyWith(playlists: updatedList);
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete playlist: $e');
    }
  }

  /// Add a track to a playlist
  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    try {
      final index = state.playlists.indexWhere((p) => p.id == playlistId);
      if (index < 0) return;

      final playlist = state.playlists[index];
      if (playlist.trackIds.contains(trackId)) return; // Already in playlist

      final updatedTrackIds = [...playlist.trackIds, trackId];
      final updated = playlist.copyWith(
        trackIds: updatedTrackIds,
        updatedAt: DateTime.now(),
      );

      await _storage.savePlaylist(updated);

      final updatedList = List<Playlist>.from(state.playlists);
      updatedList[index] = updated;
      state = state.copyWith(playlists: updatedList);
    } catch (e) {
      state = state.copyWith(error: 'Failed to add track to playlist: $e');
    }
  }

  /// Remove a track from a playlist
  Future<void> removeTrackFromPlaylist(
      String playlistId, String trackId) async {
    try {
      final index = state.playlists.indexWhere((p) => p.id == playlistId);
      if (index < 0) return;

      final playlist = state.playlists[index];
      final updatedTrackIds =
          playlist.trackIds.where((id) => id != trackId).toList();
      final updated = playlist.copyWith(
        trackIds: updatedTrackIds,
        updatedAt: DateTime.now(),
      );

      await _storage.savePlaylist(updated);

      final updatedList = List<Playlist>.from(state.playlists);
      updatedList[index] = updated;
      state = state.copyWith(playlists: updatedList);
    } catch (e) {
      state =
          state.copyWith(error: 'Failed to remove track from playlist: $e');
    }
  }

  /// Get tracks for a playlist
  List<Track> getTracksForPlaylist(String playlistId) {
    final playlist = state.playlists.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => Playlist(
        id: '',
        name: '',
        trackIds: [],
        createdAt: DateTime.now(),
      ),
    );
    return _storage.getTracksForPlaylist(playlist);
  }

  /// Get a specific playlist by ID
  Playlist? getPlaylist(String playlistId) {
    try {
      return state.playlists.firstWhere((p) => p.id == playlistId);
    } catch (_) {
      return null;
    }
  }
}
