import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../shared/widgets/mini_player_bar.dart';
import '../../../library/presentation/screens/library_screen.dart';
import '../../../playlist/presentation/screens/playlists_screen.dart';
import '../../../practice/presentation/screens/practice_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    LibraryTab(),
    PlaylistsTab(),
    PracticeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
            icon: const Icon(Icons.settings, color: AppColors.textPrimary),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerBar(),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: AppColors.surfaceDark,
            selectedItemColor: AppColors.primaryStart,
            unselectedItemColor: AppColors.textSecondary,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music),
                label: 'Library',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.playlist_play),
                label: 'Playlists',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.trending_up),
                label: 'Practice',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
