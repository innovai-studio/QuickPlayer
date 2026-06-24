import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/mini_player_bar.dart';
import '../providers/library_provider.dart';
import '../widgets/imported_tracks_tab.dart';
import '../widgets/device_audio_tab.dart';
import '../widgets/track_list_item.dart';

/// LibraryTab with internal TabBar for switching between imported and device audio
class LibraryTab extends ConsumerStatefulWidget {
  const LibraryTab({super.key});

  @override
  ConsumerState<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<LibraryTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // TabBar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: AppColors.primaryStart,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(4),
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 14,
            ),
            tabs: const [
              Tab(text: 'Imported'),
              Tab(text: 'Device'),
            ],
          ),
        ),

        // TabBarView
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              ImportedTracksTab(),
              DeviceAudioTab(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Original LibraryScreen kept for backward compatibility (standalone screen)
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
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

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const MiniPlayerBar(),
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'QuickPlayer',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.textPrimary),
            onPressed: () => _importFiles(),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppColors.textPrimary),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
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
                            onTap: () => context.push('/player/${track.id}'),
                            onDelete: () => _confirmDelete(context, track.id),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
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
}
