import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_browser/media_browser.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/extensions/duration_extension.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../playlist/presentation/providers/playlist_provider.dart';
import '../../data/models/device_track.dart';
import '../../data/models/track.dart';
import '../providers/device_audio_provider.dart';
import '../providers/library_provider.dart';

/// Tab showing device audio files (not imported, played directly)
class DeviceAudioTab extends ConsumerStatefulWidget {
  const DeviceAudioTab({super.key});

  @override
  ConsumerState<DeviceAudioTab> createState() => _DeviceAudioTabState();
}

class _DeviceAudioTabState extends ConsumerState<DeviceAudioTab>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAudio();
    });
  }

  Future<void> _initializeAudio() async {
    final notifier = ref.read(deviceAudioProvider.notifier);
    await notifier.checkPermission();

    final state = ref.read(deviceAudioProvider);
    if (state.hasPermission && !Platform.isLinux) {
      // Load from cache first (fast), then background scan for updates
      await notifier.queryDeviceAudio();
      // Trigger background scan for any new files
      notifier.backgroundScan();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App came back to foreground, trigger background scan
      final audioState = ref.read(deviceAudioProvider);
      if (audioState.hasPermission && !Platform.isLinux) {
        ref.read(deviceAudioProvider.notifier).backgroundScan();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceAudioProvider);

    return Column(
      children: [
        // Search bar and refresh/folder button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search device audio...',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    prefixIcon:
                        const Icon(Icons.search, color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.surfaceDark,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    ref.read(deviceAudioProvider.notifier).setSearchQuery(value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Platform.isLinux ? Icons.folder_open : Icons.refresh,
                  color: AppColors.primaryStart,
                ),
                tooltip: Platform.isLinux ? 'Select Folder' : 'Force Refresh',
                onPressed: () => _refreshOrSelectFolder(),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: _buildContent(state),
        ),
      ],
    );
  }

  Widget _buildContent(DeviceAudioState state) {
    // Loading state
    if (state.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primaryStart),
            SizedBox(height: 16),
            Text(
              'Scanning audio files...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // Permission not granted (Android/iOS)
    if (!state.hasPermission && !Platform.isLinux) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.folder_off,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Permission required',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Allow access to read device audio files',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final granted =
                    await ref.read(deviceAudioProvider.notifier).requestPermission();
                if (granted) {
                  await ref.read(deviceAudioProvider.notifier).queryDeviceAudio(forceRefresh: true);
                }
              },
              icon: const Icon(Icons.lock_open),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryStart,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // Linux: No folder selected yet
    if (Platform.isLinux && state.scannedFolderPath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.folder_open,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Select a folder to scan',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose a folder containing your audio files',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _refreshOrSelectFolder(),
              icon: const Icon(Icons.folder_open),
              label: const Text('Select Folder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryStart,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // Error state
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              state.error!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _refreshOrSelectFolder(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Build list based on platform
    if (Platform.isLinux) {
      return _buildLinuxList(state);
    } else {
      return _buildMobileList(state);
    }
  }

  Widget _buildMobileList(DeviceAudioState state) {
    final songs = state.filteredSongs;

    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.music_off,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              state.searchQuery.isEmpty
                  ? 'No audio files found on device'
                  : 'No matching audio files',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 18,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return _buildSongTile(song, index);
      },
    );
  }

  Widget _buildLinuxList(DeviceAudioState state) {
    final tracks = state.filteredLinuxTracks;

    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.music_off,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              state.searchQuery.isEmpty
                  ? 'No audio files found in folder'
                  : 'No matching audio files',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 18,
              ),
            ),
            if (state.scannedFolderPath != null) ...[
              const SizedBox(height: 8),
              Text(
                state.scannedFolderPath!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        // Show scanned folder path
        if (state.scannedFolderPath != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.folder, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.scannedFolderPath!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${tracks.length} files',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              return _buildDeviceTrackTile(track, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSongTile(AudioModel song, int index) {
    final duration = Duration(milliseconds: song.duration);
    final isImported = ref.watch(libraryProvider).tracks.any((t) => t.filePath == song.data);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryStart.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.music_note,
                color: AppColors.primaryStart,
              ),
            ),
            if (isImported)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          song.title.isEmpty ? 'Unknown' : song.title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${song.artist.isEmpty ? 'Unknown artist' : song.artist} • ${duration.toDisplayString()}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(
            Icons.info_outline,
            color: AppColors.textSecondary,
          ),
          onPressed: () => _showSongInfo(song),
        ),
        onTap: () => _playSong(song),
        onLongPress: () => _showSongOptions(song),
      ),
    );
  }

  void _showSongInfo(AudioModel song) {
    final duration = Duration(milliseconds: song.duration);
    final filePath = song.data;
    final fileName = filePath.split('/').last;
    final directory = filePath.substring(0, filePath.lastIndexOf('/'));
    final fileSize = (song.size / 1024 / 1024).toStringAsFixed(2);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(
          song.title.isEmpty ? 'Unknown' : song.title,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow('Artist', song.artist.isEmpty ? 'Unknown' : song.artist),
              _buildInfoRow('Album', song.album.isEmpty ? 'Unknown' : song.album),
              _buildInfoRow('Duration', duration.toDisplayString()),
              _buildInfoRow('Extension', song.fileExtension.toUpperCase()),
              _buildInfoRow('Size', '$fileSize MB'),
              _buildInfoRow('File', fileName),
              const SizedBox(height: 8),
              const Text(
                'Path:',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                directory,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTrackTile(DeviceTrack track, int index) {
    final isImported = ref.watch(libraryProvider).tracks.any((t) => t.filePath == track.filePath);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryStart.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.music_note,
                color: AppColors.primaryStart,
              ),
            ),
            if (isImported)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          track.title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${track.artist ?? 'Unknown artist'} • ${track.duration.toDisplayString()}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(
          Icons.play_circle_outline,
          color: AppColors.primaryStart,
        ),
        onTap: () => _playDeviceTrack(track),
        onLongPress: () => _showDeviceTrackOptions(track),
      ),
    );
  }

  Future<void> _refreshOrSelectFolder() async {
    if (Platform.isLinux) {
      await ref.read(deviceAudioProvider.notifier).selectAndScanFolder();
    } else {
      await ref.read(deviceAudioProvider.notifier).forceRefresh();
    }
  }

  void _playSong(AudioModel song) {
    final filePath = song.data;
    if (filePath.isEmpty) return;

    ref.read(playerProvider.notifier).loadFromPath(
      filePath: filePath,
      title: song.title.isEmpty ? 'Unknown' : song.title,
      artist: song.artist.isEmpty ? null : song.artist,
      durationMs: song.duration,
    );

    // Navigate to player with a special ID for device audio
    context.push('/player/device_${song.id}');
  }

  void _playDeviceTrack(DeviceTrack track) {
    ref.read(playerProvider.notifier).loadFromPath(
      filePath: track.filePath,
      title: track.title,
      artist: track.artist,
      durationMs: track.durationMs,
    );

    context.push('/player/${track.id}');
  }

  /// Show options bottom sheet for a song (long-press)
  void _showSongOptions(AudioModel song) {
    final isImported = ref.read(libraryProvider).tracks.any((t) => t.filePath == song.data);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                song.title.isEmpty ? 'Unknown' : song.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(color: AppColors.divider),
            ListTile(
              leading: Icon(
                isImported ? Icons.check_circle : Icons.add_circle_outline,
                color: isImported ? AppColors.success : AppColors.primaryStart,
              ),
              title: Text(
                isImported ? 'Already in Tracks' : 'Add to Tracks',
                style: TextStyle(
                  color: isImported ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
              subtitle: isImported
                  ? const Text(
                      'This file is already imported',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    )
                  : null,
              onTap: isImported
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _addToTracks(song);
                    },
            ),
            ListTile(
              leading: const Icon(
                Icons.playlist_add,
                color: AppColors.primaryStart,
              ),
              title: const Text(
                'Add to Playlist',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const Text(
                'Will also add to Tracks if not already imported',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _showPlaylistSelector(song);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Add song to tracks (import)
  Future<void> _addToTracks(AudioModel song) async {
    final track = await ref.read(libraryProvider.notifier).importFromPath(
      filePath: song.data,
      title: song.title.isEmpty ? 'Unknown' : song.title,
      artist: song.artist.isEmpty ? null : song.artist,
      durationMs: song.duration,
      fileSize: song.size,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            track != null ? 'Added to Tracks' : 'Failed to add to Tracks',
          ),
          backgroundColor: track != null ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  /// Show playlist selector dialog
  void _showPlaylistSelector(AudioModel song) async {
    // Load playlists
    await ref.read(playlistsProvider.notifier).loadPlaylists();
    final playlists = ref.read(playlistsProvider).playlists;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Add to Playlist',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(color: AppColors.divider),
            // Create new playlist option
            ListTile(
              leading: const Icon(
                Icons.add,
                color: AppColors.primaryStart,
              ),
              title: const Text(
                'Create New Playlist',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(context);
                _createNewPlaylistAndAdd(song);
              },
            ),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No playlists yet',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              ...playlists.map((playlist) => ListTile(
                    leading: const Icon(
                      Icons.playlist_play,
                      color: AppColors.textSecondary,
                    ),
                    title: Text(
                      playlist.name,
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                    subtitle: Text(
                      '${playlist.trackIds.length} tracks',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _addToPlaylist(song, playlist.id);
                    },
                  )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Create a new playlist and add the song to it
  Future<void> _createNewPlaylistAndAdd(AudioModel song) async {
    final controller = TextEditingController();

    final playlistName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text(
          'New Playlist',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (playlistName == null || playlistName.isEmpty) return;

    // Create playlist
    final playlist = await ref.read(playlistsProvider.notifier).createPlaylist(playlistName);
    if (playlist != null) {
      await _addToPlaylist(song, playlist.id);
    }
  }

  /// Add song to a specific playlist (imports first if needed)
  Future<void> _addToPlaylist(AudioModel song, String playlistId) async {
    // First, ensure the song is imported to tracks
    String? trackId;
    final existingTrack = ref.read(libraryProvider).tracks.firstWhere(
      (t) => t.filePath == song.data,
      orElse: () => Track(
        id: '',
        name: '',
        filePath: '',
        durationMs: 0,
        fileSize: 0,
        createdAt: DateTime.now(),
      ),
    );

    if (existingTrack.id.isEmpty) {
      // Not imported yet, import first
      final track = await ref.read(libraryProvider.notifier).importFromPath(
        filePath: song.data,
        title: song.title.isEmpty ? 'Unknown' : song.title,
        artist: song.artist.isEmpty ? null : song.artist,
        durationMs: song.duration,
        fileSize: song.size,
      );
      trackId = track?.id;
    } else {
      trackId = existingTrack.id;
    }

    if (trackId == null || trackId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add to playlist'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // Add to playlist
    await ref.read(playlistsProvider.notifier).addTrackToPlaylist(playlistId, trackId);

    if (mounted) {
      final playlist = ref.read(playlistsProvider.notifier).getPlaylist(playlistId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added to ${playlist?.name ?? 'playlist'}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  /// Show options for Linux device track
  void _showDeviceTrackOptions(DeviceTrack track) {
    final isImported = ref.read(libraryProvider).tracks.any((t) => t.filePath == track.filePath);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                track.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(color: AppColors.divider),
            ListTile(
              leading: Icon(
                isImported ? Icons.check_circle : Icons.add_circle_outline,
                color: isImported ? AppColors.success : AppColors.primaryStart,
              ),
              title: Text(
                isImported ? 'Already in Tracks' : 'Add to Tracks',
                style: TextStyle(
                  color: isImported ? AppColors.textSecondary : AppColors.textPrimary,
                ),
              ),
              onTap: isImported
                  ? null
                  : () async {
                      Navigator.pop(context);
                      await _addDeviceTrackToTracks(track);
                    },
            ),
            ListTile(
              leading: const Icon(
                Icons.playlist_add,
                color: AppColors.primaryStart,
              ),
              title: const Text(
                'Add to Playlist',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(context);
                _showPlaylistSelectorForDeviceTrack(track);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _addDeviceTrackToTracks(DeviceTrack track) async {
    final imported = await ref.read(libraryProvider.notifier).importFromPath(
      filePath: track.filePath,
      title: track.title,
      artist: track.artist,
      durationMs: track.durationMs,
      fileSize: track.fileSize,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported != null ? 'Added to Tracks' : 'Failed to add to Tracks',
          ),
          backgroundColor: imported != null ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  void _showPlaylistSelectorForDeviceTrack(DeviceTrack track) async {
    await ref.read(playlistsProvider.notifier).loadPlaylists();
    final playlists = ref.read(playlistsProvider).playlists;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Add to Playlist',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(color: AppColors.divider),
            ListTile(
              leading: const Icon(Icons.add, color: AppColors.primaryStart),
              title: const Text('Create New Playlist', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _createNewPlaylistAndAddDeviceTrack(track);
              },
            ),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No playlists yet', style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              ...playlists.map((playlist) => ListTile(
                    leading: const Icon(Icons.playlist_play, color: AppColors.textSecondary),
                    title: Text(playlist.name, style: const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text('${playlist.trackIds.length} tracks',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    onTap: () {
                      Navigator.pop(context);
                      _addDeviceTrackToPlaylist(track, playlist.id);
                    },
                  )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _createNewPlaylistAndAddDeviceTrack(DeviceTrack track) async {
    final controller = TextEditingController();
    final playlistName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('New Playlist', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create')),
        ],
      ),
    );

    if (playlistName == null || playlistName.isEmpty) return;

    final playlist = await ref.read(playlistsProvider.notifier).createPlaylist(playlistName);
    if (playlist != null) {
      await _addDeviceTrackToPlaylist(track, playlist.id);
    }
  }

  Future<void> _addDeviceTrackToPlaylist(DeviceTrack track, String playlistId) async {
    String? trackId;
    final existingTrack = ref.read(libraryProvider).tracks.firstWhere(
      (t) => t.filePath == track.filePath,
      orElse: () => Track(id: '', name: '', filePath: '', durationMs: 0, fileSize: 0, createdAt: DateTime.now()),
    );

    if (existingTrack.id.isEmpty) {
      final imported = await ref.read(libraryProvider.notifier).importFromPath(
        filePath: track.filePath,
        title: track.title,
        artist: track.artist,
        durationMs: track.durationMs,
        fileSize: track.fileSize,
      );
      trackId = imported?.id;
    } else {
      trackId = existingTrack.id;
    }

    if (trackId == null || trackId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add to playlist'), backgroundColor: AppColors.error),
        );
      }
      return;
    }

    await ref.read(playlistsProvider.notifier).addTrackToPlaylist(playlistId, trackId);

    if (mounted) {
      final playlist = ref.read(playlistsProvider.notifier).getPlaylist(playlistId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to ${playlist?.name ?? 'playlist'}'), backgroundColor: AppColors.success),
      );
    }
  }
}
