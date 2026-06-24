import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/storage/storage_service.dart';
import '../../data/models/track.dart';

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  return LibraryNotifier();
});

class LibraryState {
  final List<Track> tracks;
  final bool isLoading;
  final String? error;
  final String searchQuery;

  const LibraryState({
    this.tracks = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
  });

  List<Track> get filteredTracks {
    if (searchQuery.isEmpty) return tracks;
    return tracks
        .where((t) => t.name.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }

  LibraryState copyWith({
    List<Track>? tracks,
    bool? isLoading,
    String? error,
    String? searchQuery,
    bool clearError = false,
  }) {
    return LibraryState(
      tracks: tracks ?? this.tracks,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  final StorageService _storage = StorageService();
  final _uuid = const Uuid();

  LibraryNotifier() : super(const LibraryState());

  /// Load all tracks from storage
  Future<void> loadTracks() async {
    state = state.copyWith(isLoading: true);
    try {
      await _storage.init();
      final tracks = _storage.getAllTracks();
      // Sort by last played, then by name
      tracks.sort((a, b) {
        if (a.lastPlayedAt != null && b.lastPlayedAt != null) {
          return b.lastPlayedAt!.compareTo(a.lastPlayedAt!);
        } else if (a.lastPlayedAt != null) {
          return -1;
        } else if (b.lastPlayedAt != null) {
          return 1;
        }
        return a.name.compareTo(b.name);
      });
      state = state.copyWith(tracks: tracks, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load tracks: $e');
    }
  }

  /// Import audio files
  Future<void> importFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: AppConstants.supportedFormats,
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      state = state.copyWith(isLoading: true, clearError: true);

      final appDir = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${appDir.path}/audio');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }

      for (final file in result.files) {
        if (file.path == null) continue;

        try {
          // Copy file to app directory
          final sourceFile = File(file.path!);
          final fileName = '${_uuid.v4()}_${file.name}';
          final destPath = '${audioDir.path}/$fileName';

          await sourceFile.copy(destPath);

          // Get duration using AudioPlayer
          final player = AudioPlayer();
          final duration = await player.setFilePath(destPath);
          await player.dispose();

          final trackId = _uuid.v4();
          final track = Track(
            id: trackId,
            name: file.name.replaceAll(RegExp(r'\.[^.]+$'), ''), // Remove extension
            filePath: destPath,
            durationMs: duration?.inMilliseconds ?? 0,
            fileSize: file.size,
            mimeType: file.extension,
            createdAt: DateTime.now(),
          );

          await _storage.saveTrack(track);
        } catch (e) {
          // Skip files that fail to import
        }
      }

      await loadTracks();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to import files: $e');
    }
  }

  /// Delete a track
  Future<void> deleteTrack(String trackId) async {
    try {
      final track = _storage.getTrack(trackId);
      if (track != null) {
        // Delete file
        final file = File(track.filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      await _storage.deleteTrack(trackId);

      state = state.copyWith(
        tracks: state.tracks.where((t) => t.id != trackId).toList(),
      );
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete track: $e');
    }
  }

  /// Set search query
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Import a single audio file from device path (doesn't copy, references original)
  /// Returns the created Track or null if failed
  Future<Track?> importFromPath({
    required String filePath,
    required String title,
    String? artist,
    int? durationMs,
    int? fileSize,
  }) async {
    try {
      await _storage.init();

      // Check if this file is already imported
      final existingTracks = _storage.getAllTracks();
      final existing = existingTracks.where((t) => t.filePath == filePath).firstOrNull;
      if (existing != null) {
        return existing; // Already imported
      }

      // Get duration if not provided
      int duration = durationMs ?? 0;
      if (duration == 0) {
        try {
          final player = AudioPlayer();
          final dur = await player.setFilePath(filePath);
          duration = dur?.inMilliseconds ?? 0;
          await player.dispose();
        } catch (_) {}
      }

      // Get file size if not provided
      int size = fileSize ?? 0;
      if (size == 0) {
        try {
          final file = File(filePath);
          size = await file.length();
        } catch (_) {}
      }

      final trackId = _uuid.v4();
      final track = Track(
        id: trackId,
        name: title,
        filePath: filePath,
        durationMs: duration,
        fileSize: size,
        createdAt: DateTime.now(),
        isExternal: true, // Mark as external (not copied to app directory)
      );

      await _storage.saveTrack(track);

      // Update state
      state = state.copyWith(tracks: [track, ...state.tracks]);

      return track;
    } catch (e) {
      state = state.copyWith(error: 'Failed to import file: $e');
      return null;
    }
  }

  /// Check if a file path is already imported
  bool isFileImported(String filePath) {
    return state.tracks.any((t) => t.filePath == filePath);
  }
}
