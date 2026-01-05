import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_browser/media_browser.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../../../../core/constants/app_constants.dart';
import '../../data/models/device_track.dart';

final deviceAudioProvider =
    StateNotifierProvider<DeviceAudioNotifier, DeviceAudioState>((ref) {
  return DeviceAudioNotifier();
});

class DeviceAudioState {
  final List<AudioModel> songs;
  final List<DeviceTrack> linuxTracks;
  final bool isLoading;
  final bool hasPermission;
  final String? error;
  final String searchQuery;
  final String? scannedFolderPath;

  const DeviceAudioState({
    this.songs = const [],
    this.linuxTracks = const [],
    this.isLoading = false,
    this.hasPermission = false,
    this.error,
    this.searchQuery = '',
    this.scannedFolderPath,
  });

  /// Get filtered songs based on search query (Android/iOS)
  List<AudioModel> get filteredSongs {
    if (searchQuery.isEmpty) return songs;
    final query = searchQuery.toLowerCase();
    return songs.where((s) {
      final title = s.title.toLowerCase();
      final artist = s.artist.toLowerCase();
      return title.contains(query) || artist.contains(query);
    }).toList();
  }

  /// Get filtered tracks based on search query (Linux)
  List<DeviceTrack> get filteredLinuxTracks {
    if (searchQuery.isEmpty) return linuxTracks;
    final query = searchQuery.toLowerCase();
    return linuxTracks.where((t) {
      final title = t.title.toLowerCase();
      final artist = (t.artist ?? '').toLowerCase();
      return title.contains(query) || artist.contains(query);
    }).toList();
  }

  /// Check if running on Linux
  static bool get isLinux => Platform.isLinux;

  DeviceAudioState copyWith({
    List<AudioModel>? songs,
    List<DeviceTrack>? linuxTracks,
    bool? isLoading,
    bool? hasPermission,
    String? error,
    String? searchQuery,
    String? scannedFolderPath,
    bool clearError = false,
  }) {
    return DeviceAudioState(
      songs: songs ?? this.songs,
      linuxTracks: linuxTracks ?? this.linuxTracks,
      isLoading: isLoading ?? this.isLoading,
      hasPermission: hasPermission ?? this.hasPermission,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      scannedFolderPath: scannedFolderPath ?? this.scannedFolderPath,
    );
  }
}

class DeviceAudioNotifier extends StateNotifier<DeviceAudioState> {
  final MediaBrowser _mediaBrowser = MediaBrowser();
  static const String _cacheBoxName = 'device_audio_cache';
  static const String _cacheKey = 'cached_songs';
  bool _isBackgroundScanning = false;

  DeviceAudioNotifier() : super(const DeviceAudioState()) {
    _loadFromCache();
  }

  /// Check if background scanning is in progress
  bool get isBackgroundScanning => _isBackgroundScanning;

  /// Load cached songs from Hive on startup
  Future<void> _loadFromCache() async {
    if (Platform.isLinux) return;

    try {
      final box = await Hive.openBox(_cacheBoxName);
      final cachedJson = box.get(_cacheKey) as String?;

      if (cachedJson != null) {
        final List<dynamic> jsonList = json.decode(cachedJson);
        final songs = jsonList.map((j) => AudioModel.fromMap(Map<String, dynamic>.from(j))).toList();
        if (songs.isNotEmpty) {
          state = state.copyWith(songs: songs, hasPermission: true);
        }
      }
    } catch (e) {
      // Cache load failed, will query fresh
    }
  }

  /// Save songs to Hive cache
  Future<void> _saveToCache(List<AudioModel> songs) async {
    try {
      final box = await Hive.openBox(_cacheBoxName);
      final jsonList = songs.map((s) => s.toMap()).toList();
      await box.put(_cacheKey, json.encode(jsonList));
    } catch (e) {
      // Cache save failed, ignore
    }
  }

  /// Request storage permission (Android/iOS)
  Future<bool> requestPermission() async {
    if (Platform.isLinux) {
      // Linux doesn't need permission, just folder selection
      state = state.copyWith(hasPermission: true);
      return true;
    }

    try {
      // Request storage permission using permission_handler
      ph.PermissionStatus status;

      if (Platform.isAndroid) {
        // For Android 13+, use audio permission; otherwise use storage
        status = await ph.Permission.audio.request();
        if (!status.isGranted) {
          status = await ph.Permission.storage.request();
        }
      } else {
        // iOS
        status = await ph.Permission.mediaLibrary.request();
      }

      final granted = status.isGranted;
      state = state.copyWith(hasPermission: granted);

      if (!granted && status.isPermanentlyDenied) {
        state = state.copyWith(
          error: 'Permission denied. Please enable in Settings.',
        );
      }

      return granted;
    } catch (e) {
      state = state.copyWith(error: 'Permission request failed: $e');
      return false;
    }
  }

  /// Check permission status
  Future<void> checkPermission() async {
    if (Platform.isLinux) {
      state = state.copyWith(hasPermission: true);
      return;
    }

    try {
      ph.PermissionStatus status;

      if (Platform.isAndroid) {
        status = await ph.Permission.audio.status;
        if (!status.isGranted) {
          status = await ph.Permission.storage.status;
        }
      } else {
        status = await ph.Permission.mediaLibrary.status;
      }

      state = state.copyWith(hasPermission: status.isGranted);
    } catch (e) {
      state = state.copyWith(hasPermission: false);
    }
  }

  /// Query all audio files from device (Android/iOS)
  /// Set forceRefresh to true to bypass cache
  Future<void> queryDeviceAudio({bool forceRefresh = false}) async {
    if (Platform.isLinux) {
      // On Linux, user needs to select a folder first
      return;
    }

    // Skip if already have songs and not forcing refresh
    if (!forceRefresh && state.songs.isNotEmpty) {
      return;
    }

    if (!state.hasPermission) {
      final granted = await requestPermission();
      if (!granted) return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      // Query from MediaStore first
      final mediaStoreSongs = await _mediaBrowser.queryAudios(
        options: AudioQueryOptions(
          sortType: AudioSortType.title,
          sortOrder: SortOrder.ascending,
        ),
      );

      // Also scan specific directories using our own scanner
      final additionalPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Music',
      ];

      final Set<String> existingPaths = mediaStoreSongs.map((s) => s.data).toSet();
      final List<AudioModel> allSongs = List.from(mediaStoreSongs);

      for (final path in additionalPaths) {
        try {
          final dir = Directory(path);
          if (await dir.exists()) {
            await for (final entity in dir.list(recursive: true, followLinks: false)) {
              if (entity is File) {
                final ext = entity.path.split('.').last.toLowerCase();
                if (AppConstants.supportedFormats.contains(ext)) {
                  // Skip if already in MediaStore results
                  if (existingPaths.contains(entity.path)) continue;
                  existingPaths.add(entity.path);

                  // Create AudioModel from file
                  final fileName = entity.path.split('/').last;
                  final title = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

                  allSongs.add(AudioModel.fromMap({
                    'id': entity.path.hashCode,
                    'title': title,
                    'artist': '',
                    'album': '',
                    'genre': '',
                    'duration': 0,
                    'data': entity.path,
                    'size': await entity.length(),
                    'date_added': 0,
                    'date_modified': 0,
                    'track': 0,
                    'year': 0,
                    'album_artist': '',
                    'composer': '',
                    'file_extension': ext,
                    'display_name': fileName,
                    'mime_type': 'audio/$ext',
                    'is_music': true,
                    'is_ringtone': false,
                    'is_alarm': false,
                    'is_notification': false,
                    'is_podcast': false,
                    'is_audiobook': false,
                  }));
                }
              }
            }
          }
        } catch (e) {
          // Path scan failed, continue with others
        }
      }

      // Sort by title
      allSongs.sort((a, b) => a.title.compareTo(b.title));

      // Save to cache for next app launch
      await _saveToCache(allSongs);

      state = state.copyWith(
        songs: allSongs,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to query audio: $e',
      );
    }
  }

  /// Select folder and scan for audio files (Linux)
  Future<void> selectAndScanFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result == null) return;

      state = state.copyWith(
        isLoading: true,
        scannedFolderPath: result,
        clearError: true,
      );

      final tracks = await _scanFolder(result);

      state = state.copyWith(
        linuxTracks: tracks,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to scan folder: $e',
      );
    }
  }

  /// Recursively scan folder for audio files
  Future<List<DeviceTrack>> _scanFolder(String path) async {
    final tracks = <DeviceTrack>[];
    final dir = Directory(path);

    if (!await dir.exists()) return tracks;

    final audioPlayer = AudioPlayer();

    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = entity.path.split('.').last.toLowerCase();
          if (AppConstants.supportedFormats.contains(ext)) {
            try {
              // Get duration using AudioPlayer
              final duration = await audioPlayer.setFilePath(entity.path);
              final fileName = entity.path.split('/').last;
              final title = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

              tracks.add(DeviceTrack(
                id: 'linux_${entity.path.hashCode}',
                title: title,
                filePath: entity.path,
                durationMs: duration?.inMilliseconds ?? 0,
                fileSize: await entity.length(),
              ));
            } catch (e) {
              // Skip files that can't be read
            }
          }
        }
      }
    } finally {
      await audioPlayer.dispose();
    }

    // Sort by title
    tracks.sort((a, b) => a.title.compareTo(b.title));
    return tracks;
  }

  /// Set search query
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Clear cache and force refresh from MediaStore
  Future<void> forceRefresh() async {
    if (Platform.isLinux) return;

    // Clear our cached songs first
    state = state.copyWith(songs: [], isLoading: true, clearError: true);

    try {
      // Clear media_browser's internal cache
      await _mediaBrowser.clearScanCache();
    } catch (e) {
      // Ignore cache clear errors
    }

    // Re-query with force refresh
    await queryDeviceAudio(forceRefresh: true);
  }

  /// Clear all data
  void clear() {
    state = const DeviceAudioState();
  }

  /// Background scan - doesn't show loading state, merges results
  /// Called on app resume and startup after initial cache load
  Future<void> backgroundScan() async {
    if (Platform.isLinux) return;
    if (_isBackgroundScanning) return; // Already scanning
    if (!state.hasPermission) return; // No permission

    _isBackgroundScanning = true;

    try {
      // Query from MediaStore
      final mediaStoreSongs = await _mediaBrowser.queryAudios(
        options: AudioQueryOptions(
          sortType: AudioSortType.title,
          sortOrder: SortOrder.ascending,
        ),
      );

      // Also scan specific directories
      final additionalPaths = [
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Music',
      ];

      final Set<String> existingPaths = mediaStoreSongs.map((s) => s.data).toSet();
      final List<AudioModel> allSongs = List.from(mediaStoreSongs);

      for (final path in additionalPaths) {
        try {
          final dir = Directory(path);
          if (await dir.exists()) {
            await for (final entity in dir.list(recursive: true, followLinks: false)) {
              if (entity is File) {
                final ext = entity.path.split('.').last.toLowerCase();
                if (AppConstants.supportedFormats.contains(ext)) {
                  if (existingPaths.contains(entity.path)) continue;
                  existingPaths.add(entity.path);

                  final fileName = entity.path.split('/').last;
                  final title = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

                  allSongs.add(AudioModel.fromMap({
                    'id': entity.path.hashCode,
                    'title': title,
                    'artist': '',
                    'album': '',
                    'genre': '',
                    'duration': 0,
                    'data': entity.path,
                    'size': await entity.length(),
                    'date_added': 0,
                    'date_modified': 0,
                    'track': 0,
                    'year': 0,
                    'album_artist': '',
                    'composer': '',
                    'file_extension': ext,
                    'display_name': fileName,
                    'mime_type': 'audio/$ext',
                    'is_music': true,
                    'is_ringtone': false,
                    'is_alarm': false,
                    'is_notification': false,
                    'is_podcast': false,
                    'is_audiobook': false,
                  }));
                }
              }
            }
          }
        } catch (e) {
          // Path scan failed, continue
        }
      }

      // Sort by title
      allSongs.sort((a, b) => a.title.compareTo(b.title));

      // Check if there are any changes
      final currentPaths = state.songs.map((s) => s.data).toSet();
      final newPaths = allSongs.map((s) => s.data).toSet();

      if (currentPaths.length != newPaths.length ||
          !currentPaths.containsAll(newPaths)) {
        // There are changes, update state and cache
        await _saveToCache(allSongs);
        state = state.copyWith(songs: allSongs);
      }
    } catch (e) {
      // Background scan failed silently
    } finally {
      _isBackgroundScanning = false;
    }
  }
}
