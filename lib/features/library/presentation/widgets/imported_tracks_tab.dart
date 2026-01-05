import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../playlist/presentation/providers/playlist_provider.dart';
import '../providers/library_provider.dart';
import 'track_list_item.dart';

/// Tab showing imported tracks (copied to app directory)
class ImportedTracksTab extends ConsumerStatefulWidget {
  const ImportedTracksTab({super.key});

  @override
  ConsumerState<ImportedTracksTab> createState() => _ImportedTracksTabState();
}

class _ImportedTracksTabState extends ConsumerState<ImportedTracksTab> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryProvider.notifier).loadTracks();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);

    return Column(
      children: [
        // Search bar and import button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search tracks...',
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
                    ref.read(libraryProvider.notifier).setSearchQuery(value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add, color: AppColors.primaryStart),
                onPressed: () => _importFiles(),
              ),
            ],
          ),
        ),

        // Track list
        Expanded(
          child: libraryState.isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryStart,
                  ),
                )
              : libraryState.filteredTracks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.music_note,
                            size: 64,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            libraryState.searchQuery.isEmpty
                                ? 'No tracks yet'
                                : 'No tracks found',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 18,
                            ),
                          ),
                          if (libraryState.searchQuery.isEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => _importFiles(),
                              icon: const Icon(Icons.add),
                              label: const Text('Import audio files'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: libraryState.filteredTracks.length,
                      itemBuilder: (context, index) {
                        final track = libraryState.filteredTracks[index];
                        return TrackListItem(
                          track: track,
                          onTap: () => _playTrack(index),
                          onDelete: () => _confirmDelete(context, track.id),
                          onLongPress: () =>
                              _showAddToPlaylistDialog(track.id),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _playTrack(int index) {
    final libraryState = ref.read(libraryProvider);
    final tracks = libraryState.filteredTracks;
    final track = tracks[index];

    // Load the queue with all library tracks
    ref.read(playerProvider.notifier).loadQueue(
          tracks,
          index,
          playlistId: null, // null means from Library
        );

    context.push('/player/${track.id}');
  }

  Future<void> _importFiles() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text(
          'Import Audio Files',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Select audio files to import.\nSupported formats: MP3, WAV, M4A, AAC, FLAC, OGG',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose Files'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      ref.read(libraryProvider.notifier).importFiles();
    }
  }

  void _confirmDelete(BuildContext context, String trackId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text(
          'Delete Track',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to delete this track?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(libraryProvider.notifier).deleteTrack(trackId);
              Navigator.pop(context);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(String trackId) {
    final playlistState = ref.read(playlistsProvider);

    if (playlistState.playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a playlist first'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Add to Playlist',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          ...playlistState.playlists.map((playlist) {
            final alreadyAdded = playlist.trackIds.contains(trackId);
            return ListTile(
              leading: const Icon(
                Icons.playlist_play,
                color: AppColors.primaryStart,
              ),
              title: Text(
                playlist.name,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                '${playlist.trackIds.length} tracks',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              trailing: alreadyAdded
                  ? const Icon(Icons.check, color: AppColors.primaryStart)
                  : null,
              onTap: alreadyAdded
                  ? null
                  : () {
                      ref
                          .read(playlistsProvider.notifier)
                          .addTrackToPlaylist(playlist.id, trackId);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Added to ${playlist.name}'),
                        ),
                      );
                    },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
