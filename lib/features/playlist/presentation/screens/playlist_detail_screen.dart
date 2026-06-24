import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/mini_player_bar.dart';
import '../../../library/data/models/track.dart';
import '../../../library/presentation/providers/library_provider.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../data/models/playlist.dart';
import '../providers/playlist_provider.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playlistsProvider.notifier).loadPlaylists();
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlistState = ref.watch(playlistsProvider);
    final playlist = playlistState.playlists.firstWhere(
      (p) => p.id == widget.playlistId,
      orElse: () => Playlist(
        id: '',
        name: '',
        trackIds: [],
        createdAt: DateTime.now(),
      ),
    );

    if (playlist.id.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: Text(
            'Playlist not found',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final tracks =
        ref.read(playlistsProvider.notifier).getTracksForPlaylist(playlist.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const MiniPlayerBar(),
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          playlist.name,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.textPrimary),
            onPressed: () => _showAddTracksDialog(playlist),
          ),
        ],
      ),
      body: tracks.isEmpty
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
                  const Text(
                    'No tracks in this playlist',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _showAddTracksDialog(playlist),
                    icon: const Icon(Icons.add),
                    label: const Text('Add tracks'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return _PlaylistTrackTile(
                  track: track,
                  onTap: () => _playTrack(tracks, index, playlist.id),
                  onRemove: () => _removeTrack(playlist.id, track.id),
                );
              },
            ),
    );
  }

  void _playTrack(List<Track> tracks, int index, String playlistId) {
    ref.read(playerProvider.notifier).loadQueue(
          tracks,
          index,
          playlistId: playlistId,
        );
    context.push('/player/${tracks[index].id}');
  }

  void _removeTrack(String playlistId, String trackId) {
    ref
        .read(playlistsProvider.notifier)
        .removeTrackFromPlaylist(playlistId, trackId);
  }

  void _showAddTracksDialog(Playlist playlist) {
    final libraryState = ref.read(libraryProvider);
    final availableTracks = libraryState.tracks
        .where((t) => !playlist.trackIds.contains(t.id))
        .toList();

    if (availableTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All tracks are already in this playlist'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Tracks',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: availableTracks.length,
                itemBuilder: (context, index) {
                  final track = availableTracks[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.music_note,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    title: Text(
                      track.name,
                      style: const TextStyle(color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.add, color: AppColors.primaryStart),
                      onPressed: () {
                        ref
                            .read(playlistsProvider.notifier)
                            .addTrackToPlaylist(playlist.id, track.id);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _PlaylistTrackTile({
    required this.track,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.music_note,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (track.bpm != null) ...[
                            Text(
                              '${track.bpm} BPM',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (track.musicalKey != null)
                            Text(
                              track.musicalKey!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
